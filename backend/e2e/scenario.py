"""Scénario de bout en bout (étape 5) contre un serveur LuluBoard réellement lancé.

Usage : uv run python e2e/scenario.py http://127.0.0.1:8765 <dossier des e-mails>
Le serveur doit utiliser le backend d'e-mails « filebased » pour que le scénario lise les codes.
Chaque étape affiche OK ; la première erreur arrête le scénario.
"""

import asyncio
import json
import os
import re
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
import websockets

sys.path.insert(0, str(Path(__file__).parent))
from crypto import Appareil, Trousseau, aead, derivation_lien, ouvrir  # noqa: E402

from nacl.signing import SigningKey  # noqa: E402,F401

BASE = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else "http://127.0.0.1:8765"
API = BASE + "/api/v1"
BOITE = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("e2e_mails")
MDP = "MotDePasse1"


def b64(o):
    import base64

    return base64.urlsafe_b64encode(o).rstrip(b"=").decode()


def deb64(t):
    import base64

    return base64.urlsafe_b64decode(t + "=" * (-len(t) % 4))


def maintenant(decalage_s=0):
    return (datetime.now(timezone.utc) + timedelta(seconds=decalage_s)).isoformat()


etape_n = 0


def etape(nom):
    global etape_n
    etape_n += 1
    print(f"[{etape_n:02d}] {nom} ... ", end="", flush=True)


def ok(info=""):
    print("OK" + (f" ({info})" if info else ""))


def attendu(reponse, code):
    if reponse.status_code != code:
        print(f"ÉCHEC : HTTP {reponse.status_code} au lieu de {code}\n{reponse.text[:500]}")
        sys.exit(1)
    return reponse.json() if reponse.content and "json" in reponse.headers.get("content-type", "") else None


def dernier_code(email):
    fichiers = sorted(BOITE.glob("*.log"), key=os.path.getmtime)
    for f in reversed(fichiers):
        texte = f.read_text(encoding="utf-8", errors="ignore")
        for bloc in reversed(texte.split("-" * 79)):
            if f"To: {email}" in bloc:
                trouve = re.search(r"\b(\d{6})\b", bloc.split("\n\n", 1)[-1])
                if trouve:
                    return trouve.group(1)
    raise RuntimeError(f"Aucun code trouvé pour {email}")


def client(jeton=None):
    entetes = {"X-App-Version": "0.1.0"}
    if jeton:
        entetes["Authorization"] = f"Bearer {jeton}"
    return httpx.Client(base_url=API, headers=entetes, timeout=60)


def main():
    email = f"e2e-{uuid.uuid4().hex[:8]}@exemple.test"
    anonyme = client()

    etape("Santé du serveur")
    sante = attendu(anonyme.get("/health"), 200)
    ok(f"base={sante['verifications']['base']} redis={sante['verifications']['redis']}")

    etape("Inscription")
    conditions = [c["id"] for c in attendu(anonyme.get("/conditions/actuelles"), 200)]
    attendu(anonyme.post("/auth/inscription", json={"email": email, "nomAffichage": "E2E", "motDePasse": MDP, "conditionsAcceptees": conditions}), 201)
    ok(email)

    etape("Vérification de l'e-mail + clés initiales (chiffrement de bout en bout)")
    trousseau = Trousseau()
    pc = Appareil()
    corps = {
        "email": email,
        "code": dernier_code(email),
        "appareil": {"nom": "PC e2e", "type": "DESKTOP", "plateforme": "Windows", "versionApp": "0.1.0", "clePublique": b64(pc.publique)},
        "cles": {
            "enveloppeRecuperation": b64(trousseau.enveloppe_recuperation()),
            "enveloppeAppareil": b64(Appareil.sceller_pour(pc.publique, trousseau.maitre)),
            "clePubliqueVerification": b64(bytes(trousseau.cle_verification.verify_key)),
        },
    }
    session_pc = attendu(anonyme.post("/auth/inscription/verifier", json=corps), 201)
    api_pc = client(session_pc["session"]["jeton"])
    ok()

    etape("Avant confirmation de la clé de récupération, la synchro est refusée")
    r = api_pc.get("/synchro/changements?depuis=0")
    assert r.status_code == 403 and r.json()["erreur"]["code"] == "cle_recuperation_non_confirmee"
    attendu(api_pc.post("/compte/cle-recuperation/confirmer"), 204)
    ok()

    etape("Relecture de l'enveloppe de l'appareil et ouverture de la clé maître")
    env = deb64(attendu(api_pc.get("/appareils/courant/enveloppe"), 200)["cleMaitreEnveloppee"])
    assert pc.desceller(env) == trousseau.maitre
    ok()

    etape("Création d'un tableau et d'un post-it chiffrés, poussés par la synchro")
    tableau_id, post_it_id = str(uuid.uuid4()), str(uuid.uuid4())
    contenu_tableau = aead(trousseau.maitre, json.dumps({"nom": "Perso", "ordre": 0}).encode(), f"tb:{tableau_id}")
    donnees_post_it = {"contenu": "**Acheter** du pain", "couleurFond": "#FFE066", "x": 10, "y": 20, "largeur": 220, "hauteur": 180, "ordreEmpilement": 0}
    cle_post_it, contenu_post_it, cle_env = trousseau.nouvel_element(post_it_id, donnees_post_it)
    resultat = attendu(
        api_pc.post(
            "/synchro/envoyer",
            json={
                "changements": [
                    {"entite": "tableau", "id": tableau_id, "modifieLe": maintenant(), "donnees": {"contenuChiffre": b64(contenu_tableau)}},
                    {
                        "entite": "element",
                        "id": post_it_id,
                        "modifieLe": maintenant(),
                        "donnees": {"type": "POST_IT", "parentId": tableau_id, "cleElementEnveloppee": b64(cle_env), "contenuChiffre": b64(contenu_post_it)},
                    },
                ]
            },
        ),
        200,
    )
    assert [x["statut"] for x in resultat["resultats"]] == ["accepte", "accepte"]
    ok(f"version {resultat['versionCourante']}")

    etape("Nouvel appareil : connexion, demande de déverrouillage, approbation par le PC")
    tel = Appareil()
    session_tel = attendu(
        anonyme.post("/auth/connexion", json={"email": email, "motDePasse": MDP, "appareil": {"nom": "Téléphone e2e", "type": "MOBILE", "plateforme": "Android", "versionApp": "0.1.0", "clePublique": b64(tel.publique)}}),
        200,
    )
    api_tel = client(session_tel["session"]["jeton"])
    assert session_tel["appareil"]["statut"] == "EN_ATTENTE_DEVERROUILLAGE"
    demande = attendu(api_tel.post("/appareils/courant/deverrouillage"), 201)
    en_attente = attendu(api_pc.get("/deverrouillages/en-attente"), 200)[0]
    enveloppe_tel = Appareil.sceller_pour(deb64(en_attente["clePubliqueDemandeur"]), trousseau.maitre)
    attendu(api_pc.post(f"/deverrouillages/{en_attente['id']}/approuver", json={"codeAffiche": demande["codeAffiche"], "cleMaitreEnveloppee": b64(enveloppe_tel)}), 204)
    maitre_tel = tel.desceller(deb64(attendu(api_tel.get("/appareils/courant/enveloppe"), 200)["cleMaitreEnveloppee"]))
    assert maitre_tel == trousseau.maitre
    ok()

    etape("Le téléphone tire les changements et déchiffre le post-it")
    t = attendu(api_tel.get("/synchro/changements?depuis=0"), 200)
    recu = next(c for c in t["changements"] if c["id"] == post_it_id)
    cle = Trousseau(maitre_tel).cle_element(post_it_id, deb64(recu["donnees"]["cleElementEnveloppee"]))
    clair = json.loads(ouvrir(cle, deb64(recu["donnees"]["contenuChiffre"]), f"el:{post_it_id}"))
    assert clair == donnees_post_it
    ok(clair["contenu"])

    etape("WebSocket : le PC est prévenu quand le téléphone modifie le post-it")

    async def ecouter():
        async with websockets.connect(BASE.replace("http", "ws") + "/api/v1/ws") as ws:
            await ws.send(json.dumps({"type": "auth", "jeton": session_pc["session"]["jeton"]}))
            assert json.loads(await ws.recv())["type"] == "pret"
            nouveau = dict(donnees_post_it, contenu="Pain **et** lait")
            _, contenu2, _ = trousseau.nouvel_element(post_it_id, nouveau, cle=cle_post_it)
            await asyncio.to_thread(
                api_tel.post,
                "/synchro/envoyer",
                json={"changements": [{"entite": "element", "id": post_it_id, "modifieLe": maintenant(1), "donnees": {"type": "POST_IT", "parentId": tableau_id, "cleElementEnveloppee": b64(cle_env), "contenuChiffre": b64(contenu2)}}]},
            )
            evenement = json.loads(await asyncio.wait_for(ws.recv(), 10))
            assert evenement["type"] == "changements", evenement
            return evenement["versionCourante"]

    ok(f"version annoncée {asyncio.run(ecouter())}")

    etape("Historique : l'ancienne version du post-it est conservée")
    t = attendu(api_pc.get("/synchro/changements?depuis=0"), 200)
    versions = [c for c in t["changements"] if c["entite"] == "version_post_it"]
    ancien = json.loads(ouvrir(cle_post_it, deb64(versions[0]["donnees"]["contenuChiffre"]), f"el:{post_it_id}"))
    assert ancien["contenu"] == donnees_post_it["contenu"]
    ok()

    etape("Lien public sans mot de passe : un inconnu déchiffre avec la clé du fragment")
    lien = attendu(api_pc.post("/liens", json={"elementId": post_it_id, "duree": "H24", "protegeParMotDePasse": False}), 201)
    public = attendu(anonyme.get(f"/public/liens/{lien['jeton']}"), 200)
    clair = json.loads(ouvrir(cle_post_it, deb64(public["element"]["contenuChiffre"]), f"el:{post_it_id}"))
    assert clair["contenu"] == "Pain **et** lait"  # contenu en direct
    ok()

    etape("Lien public protégé par mot de passe (Argon2id, vérification côté serveur)")
    sel = os.urandom(16)
    k_lien, verificateur = derivation_lien("secret du lien", sel)
    lien2 = attendu(
        api_pc.post(
            "/liens",
            json={
                "elementId": post_it_id,
                "duree": "J7",
                "protegeParMotDePasse": True,
                "selDerivation": b64(sel),
                "cleElementEnveloppee": b64(aead(k_lien, cle_post_it, f"lien:{post_it_id}")),
                "verificateurMotDePasse": b64(verificateur),
            },
        ),
        201,
    )
    meta = attendu(anonyme.get(f"/public/liens/{lien2['jeton']}"), 200)
    k2, verif2 = derivation_lien("secret du lien", deb64(meta["selDerivation"]))
    ouvert = attendu(anonyme.post(f"/public/liens/{lien2['jeton']}/deverrouiller", json={"verificateurMotDePasse": b64(verif2)}), 200)
    cle_retrouvee = ouvrir(k2, deb64(ouvert["cleElementEnveloppee"]), f"lien:{post_it_id}")
    assert json.loads(ouvrir(cle_retrouvee, deb64(ouvert["element"]["contenuChiffre"]), f"el:{post_it_id}"))["contenu"] == "Pain **et** lait"
    ok()

    etape("Troisième appareil déverrouillé par la clé de récupération (preuve Ed25519)")
    tablette = Appareil()
    session_tab = attendu(
        anonyme.post("/auth/connexion", json={"email": email, "motDePasse": MDP, "appareil": {"nom": "Tablette", "type": "WEB", "plateforme": "Chrome", "versionApp": "0.1.0", "clePublique": b64(tablette.publique)}}),
        200,
    )
    api_tab = client(session_tab["session"]["jeton"])
    rec = attendu(api_tab.get("/compte/enveloppe-recuperation"), 200)
    retrouve = Trousseau.depuis_recuperation(trousseau.recup, deb64(rec["cleMaitreEnveloppee"]))
    signature = retrouve.cle_verification.sign(deb64(rec["defi"])).signature
    attendu(
        api_tab.post(
            "/appareils/courant/deverrouiller-par-recuperation",
            json={"cleMaitreEnveloppee": b64(Appareil.sceller_pour(tablette.publique, retrouve.maitre)), "signatureDefi": b64(signature)},
        ),
        204,
    )
    ok()

    etape("Limite de 3 appareils")
    r = anonyme.post("/auth/connexion", json={"email": email, "motDePasse": MDP, "appareil": {"nom": "4e", "type": "WEB", "plateforme": "Firefox", "versionApp": "0.1.0", "clePublique": b64(Appareil().publique)}})
    assert r.status_code == 409 and r.json()["erreur"]["code"] == "limite_appareils"
    ok()

    etape("Envoi du PC vers le téléphone")
    envoi_id = str(uuid.uuid4())
    attendu(api_pc.post("/envois", json={"id": envoi_id, "appareilCibleId": session_tel["appareil"]["id"], "contenuChiffre": b64(aead(trousseau.maitre, b"https://exemple.test", f"envoi:{envoi_id}"))}), 201)
    recus = attendu(api_tel.get("/envois/recus"), 200)
    assert ouvrir(maitre_tel, deb64(recus[0]["contenuChiffre"]), f"envoi:{envoi_id}") == b"https://exemple.test"
    attendu(api_tel.post(f"/envois/{envoi_id}/recupere"), 204)
    ok()

    etape("Révocation de la tablette : sa session ne fonctionne plus")
    attendu(api_pc.delete(f"/appareils/{session_tab['appareil']['id']}"), 204)
    assert api_tab.get("/compte").status_code == 401
    ok()

    etape("Export des données chiffrées")
    export = attendu(api_pc.get("/export"), 200)
    ok(f"{len(export['entites'])} entités")

    etape("Programmation de la suppression du compte, puis annulation par reconnexion")
    attendu(api_pc.request("DELETE", "/compte", json={"motDePasse": MDP}), 200)
    reco = attendu(anonyme.post("/auth/connexion", json={"email": email, "motDePasse": MDP, "appareil": {"appareilId": session_pc["appareil"]["id"]}}), 200)
    assert reco["compte"]["statut"] == "ACTIF"
    ok()

    print(f"\nScénario de bout en bout : {etape_n} étapes réussies.")


if __name__ == "__main__":
    main()

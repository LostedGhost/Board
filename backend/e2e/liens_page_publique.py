"""Prépare des liens publics pour tester la page `public/l/index.html` dans un navigateur.

Usage : uv run python e2e/liens_page_publique.py http://127.0.0.1:8000 <dossier des e-mails> [url de la page]
Le serveur doit utiliser le backend d'e-mails « filebased » (EMAIL_FILE_PATH = dossier des e-mails).
Crée le compte lien-test@exemple.test (ou une variante s'il existe déjà), un post-it, un snippet et une
liste de tâches avec sous-tâches, puis des liens sans et avec mot de passe (« test-lien-1 »), et imprime les URL.
"""

import base64
import json
import os
import re
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).parent))
from crypto import Appareil, Trousseau, aead, derivation_lien  # noqa: E402

BASE = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else "http://127.0.0.1:8000"
BOITE = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("e2e_mails")
PAGE = sys.argv[3].rstrip("/") if len(sys.argv) > 3 else "http://127.0.0.1:5191/l/"
MDP_COMPTE = "MotDePasse1"
MDP_LIEN = "test-lien-1"


def b64(o):
    return base64.urlsafe_b64encode(o).rstrip(b"=").decode()


def attendu(r, code):
    if r.status_code != code:
        sys.exit(f"ÉCHEC : HTTP {r.status_code} au lieu de {code}\n{r.text[:500]}")
    return r.json() if r.content and "json" in r.headers.get("content-type", "") else None


def dernier_code(email):
    for f in sorted(BOITE.glob("*.log"), key=os.path.getmtime, reverse=True):
        for bloc in reversed(f.read_text(encoding="utf-8", errors="ignore").split("-" * 79)):
            if f"To: {email}" in bloc:
                trouve = re.search(r"\b(\d{6})\b", bloc.split("\n\n", 1)[-1])
                if trouve:
                    return trouve.group(1)
    raise RuntimeError(f"Aucun code trouvé pour {email}")


def client(jeton=None):
    entetes = {"X-App-Version": "0.1.0"}
    if jeton:
        entetes["Authorization"] = f"Bearer {jeton}"
    return httpx.Client(base_url=BASE + "/api/v1", headers=entetes, timeout=60)


def inscrire(anonyme):
    conditions = [c["id"] for c in attendu(anonyme.get("/conditions/actuelles"), 200)]
    email = "lien-test@exemple.test"
    r = anonyme.post("/auth/inscription", json={"email": email, "nomAffichage": "Test lien", "motDePasse": MDP_COMPTE, "conditionsAcceptees": conditions})
    if r.status_code == 409:  # compte déjà créé par un essai précédent (sa clé maître n'est pas conservée)
        email = f"lien-test-{uuid.uuid4().hex[:6]}@exemple.test"
        r = anonyme.post("/auth/inscription", json={"email": email, "nomAffichage": "Test lien", "motDePasse": MDP_COMPTE, "conditionsAcceptees": conditions})
    attendu(r, 201)
    trousseau, pc = Trousseau(), Appareil()
    corps = {
        "email": email,
        "code": dernier_code(email),
        "appareil": {"nom": "PC test liens", "type": "DESKTOP", "plateforme": "Windows", "versionApp": "0.1.0", "clePublique": b64(pc.publique)},
        "cles": {
            "enveloppeRecuperation": b64(trousseau.enveloppe_recuperation()),
            "enveloppeAppareil": b64(Appareil.sceller_pour(pc.publique, trousseau.maitre)),
            "clePubliqueVerification": b64(bytes(trousseau.cle_verification.verify_key)),
        },
    }
    session = attendu(anonyme.post("/auth/inscription/verifier", json=corps), 201)
    api = client(session["session"]["jeton"])
    attendu(api.post("/compte/cle-recuperation/confirmer"), 204)
    return email, trousseau, api


def main():
    maintenant = datetime.now(timezone.utc).isoformat()
    email, trousseau, api = inscrire(client())
    tableau = str(uuid.uuid4())
    changements = [{"entite": "tableau", "id": tableau, "modifieLe": maintenant,
                    "donnees": {"contenuChiffre": b64(aead(trousseau.maitre, json.dumps({"nom": "Test liens", "ordre": 0}).encode(), f"tb:{tableau}"))}}]
    cles = {}

    def element(type_, donnees, parent=tableau, cle=None):
        id_ = str(uuid.uuid4())
        cle_el, contenu, enveloppe = trousseau.nouvel_element(id_, donnees, cle=cle)
        d = {"type": type_, "parentId": parent, "contenuChiffre": b64(contenu)}
        if cle is None:
            d["cleElementEnveloppee"] = b64(enveloppe)
            cles[id_] = cle_el
        changements.append({"entite": "element", "id": id_, "modifieLe": maintenant, "donnees": d})
        return id_

    post_it = element("POST_IT", {
        "contenu": "# Courses\n\n**Acheter** du pain et *du lait*.\n\n- [x] Pain\n- [ ] Lait\n  - entier\n\n> Pas oublier `<script>alert(1)</script>`\n\n[LuluBoard](https://exemple.test)",
        "couleurFond": "#FFE066", "x": 0, "y": 0, "largeur": 220, "hauteur": 180, "ordreEmpilement": 0})
    snippet = element("SNIPPET", {"titre": "Bonjour en Python", "contenu": "def bonjour(nom):\n    return f\"Bonjour {nom} <b>!</b>\"\n", "langage": "python"})
    liste = element("LISTE_TACHES", {"titre": "Préparer la démo"})
    t1 = element("TACHE", {"titre": "Écrire le **script**", "faite": True, "echeance": None, "priorite": "HAUTE", "ordre": 0}, parent=liste, cle=cles[liste])
    element("TACHE", {"titre": "Tester la page", "faite": False, "echeance": "2026-10-20T10:00:00+00:00", "priorite": "NORMALE", "ordre": 1}, parent=liste, cle=cles[liste])
    element("TACHE", {"titre": "Sous-tâche faite", "faite": True, "echeance": None, "priorite": "BASSE", "ordre": 0}, parent=t1, cle=cles[liste])
    element("TACHE", {"titre": "Sous-tâche à faire", "faite": False, "echeance": None, "priorite": "NORMALE", "ordre": 1}, parent=t1, cle=cles[liste])

    resultat = attendu(api.post("/synchro/envoyer", json={"changements": changements}), 200)
    assert all(x["statut"] == "accepte" for x in resultat["resultats"]), resultat

    def lien(id_, mot_de_passe=None):
        corps = {"elementId": id_, "duree": "J7", "protegeParMotDePasse": mot_de_passe is not None}
        if mot_de_passe:
            sel = os.urandom(16)
            k_lien, verificateur = derivation_lien(mot_de_passe, sel)
            corps.update({"selDerivation": b64(sel), "cleElementEnveloppee": b64(aead(k_lien, cles[id_], f"lien:{id_}")), "verificateurMotDePasse": b64(verificateur)})
        jeton = attendu(api.post("/liens", json=corps), 201)["jeton"]
        return f"{PAGE}?t={jeton}" + ("" if mot_de_passe else f"#{b64(cles[id_])}")

    print(f"Compte : {email}")
    print(f"POST_IT sans mot de passe : {lien(post_it)}")
    print(f"POST_IT avec mot de passe « {MDP_LIEN} » : {lien(post_it, MDP_LIEN)}")
    print(f"SNIPPET sans mot de passe : {lien(snippet)}")
    print(f"LISTE_TACHES sans mot de passe : {lien(liste)}")
    print(f"LISTE_TACHES avec mot de passe « {MDP_LIEN} » : {lien(liste, MDP_LIEN)}")


if __name__ == "__main__":
    main()

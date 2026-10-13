"""Prépare des liens publics pour tester la page `public/l/index.html` dans un navigateur.

Usage : uv run python e2e/liens_page_publique.py http://127.0.0.1:8000 <dossier des e-mails> [url de la page]
Le serveur doit utiliser le backend d'e-mails « filebased » (EMAIL_FILE_PATH = dossier des e-mails).
Crée le compte lien-test-<aléa>@exemple.test, un post-it, un snippet, une liste de tâches avec sous-tâches et un
FICHIER chiffré en secretstream (docs/07 §5), puis des liens sans et avec mot de passe (« test-lien-1 »).
Vérifie le téléchargement public du fichier par l'API (déchiffrement + comparaison), vérifie le signalement
(UC-I20), et imprime les URL à ouvrir dans le navigateur.

Stockage des fichiers sans Telegram ni LuluFiles réels : faux LuluFiles local, à lancer d'abord :
  uv run python e2e/liens_page_publique.py faux-lulufiles 8099 <dossier de stockage>
puis lancer le backend avec, en variables d'environnement (sans toucher à .env) :
  FILES_USE_DIRECT_TELEGRAM=false LULUFILES_BASE_URL=http://127.0.0.1:8099 LULUFILES_API_KEY=cle-de-test
"""

import base64
import hashlib
import json
import os
import re
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import httpx
from nacl import bindings

sys.path.insert(0, str(Path(__file__).parent))
from crypto import Appareil, Trousseau, aead, derivation_lien, ouvrir  # noqa: E402

BASE = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else "http://127.0.0.1:8000"
BOITE = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("e2e_mails")
PAGE = sys.argv[3].rstrip("/") if len(sys.argv) > 3 else "http://127.0.0.1:5191/l/"
MDP_COMPTE = "MotDePasse1"
MDP_LIEN = "test-lien-1"
BLOC_CLAIR = 64 * 1024


def b64(o):
    return base64.urlsafe_b64encode(o).rstrip(b"=").decode()


def b64d(texte):
    return base64.urlsafe_b64decode(texte + "=" * (-len(texte) % 4))


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


# --- Fichiers : crypto_secretstream_xchacha20poly1305 (docs/07 §5) -------------------------------


def chiffrer_fichier(cle, clair):
    """en-tête(24) ‖ blocs de 64 Kio de clair + 17 o ; le dernier porte TAG_FINAL."""
    etat = bindings.crypto_secretstream_xchacha20poly1305_state()
    sortie = bytearray(bindings.crypto_secretstream_xchacha20poly1305_init_push(etat, cle))
    morceaux = [clair[i : i + BLOC_CLAIR] for i in range(0, len(clair), BLOC_CLAIR)] or [b""]
    for i, morceau in enumerate(morceaux):
        final = i == len(morceaux) - 1
        tag = bindings.crypto_secretstream_xchacha20poly1305_TAG_FINAL if final else bindings.crypto_secretstream_xchacha20poly1305_TAG_MESSAGE
        sortie += bindings.crypto_secretstream_xchacha20poly1305_push(etat, morceau, None, tag)
    return bytes(sortie)


def dechiffrer_fichier(cle, chiffre):
    etat = bindings.crypto_secretstream_xchacha20poly1305_state()
    bindings.crypto_secretstream_xchacha20poly1305_init_pull(etat, chiffre[:24], cle)
    clair, fini, bloc = bytearray(), False, BLOC_CLAIR + 17
    for i in range(24, len(chiffre), bloc):
        assert not fini, "données après le bloc final"
        morceau, tag = bindings.crypto_secretstream_xchacha20poly1305_pull(etat, chiffre[i : i + bloc], None)
        clair += morceau
        fini = tag == bindings.crypto_secretstream_xchacha20poly1305_TAG_FINAL
    assert fini, "flux tronqué"
    return bytes(clair)


# --- Scénario -----------------------------------------------------------------------------------


def inscrire(anonyme):
    conditions = [c["id"] for c in attendu(anonyme.get("/conditions/actuelles"), 200)]
    email = f"lien-test-{uuid.uuid4().hex[:8]}@exemple.test"
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


def televerser_fichier(api, trousseau, maintenant):
    """~150 Kio (3 blocs secretstream, dernier partiel), contenu reproductible ; attend le statut PRET."""
    clair = (b"LuluBoard - fichier de test du lien public\n" + bytes(range(256)) * 700)[: 150 * 1024 + 123]
    id_ = str(uuid.uuid4())
    meta = {"nom": "rapport-test.bin", "typeMime": "application/octet-stream", "taille": len(clair)}
    cle, contenu, enveloppe = trousseau.nouvel_element(id_, meta)
    chiffre = chiffrer_fichier(cle, clair)
    assert dechiffrer_fichier(cle, chiffre) == clair
    metadonnees = {"id": id_, "modifieLe": maintenant, "tailleOctets": len(chiffre), "cleElementEnveloppee": b64(enveloppe), "contenuChiffre": b64(contenu)}
    attendu(api.post("/fichiers", data={"metadonnees": json.dumps(metadonnees)}, files={"fichier": ("fichier.bin", chiffre, "application/octet-stream")}), 202)
    for _ in range(60):
        statut = attendu(api.get(f"/fichiers/{id_}"), 200)
        if statut["statut"] in ("PRET", "ECHEC"):
            break
        time.sleep(1)
    if statut["statut"] != "PRET":
        sys.exit(f"ÉCHEC : fichier {statut['statut']} ({statut.get('messageErreur')}). Stockage (Telegram / LuluFiles / faux LuluFiles) configuré ?")
    return id_, cle, clair, len(chiffre)


def verifier_fichier_public(jeton, jeton_mdp, cle, clair):
    """Même chemin que la page : GET /public/liens/{jeton}/fichier (+ ?t= après déverrouillage)."""
    public = httpx.Client(base_url=BASE + "/api/v1", timeout=60, follow_redirects=True)
    r = public.get(f"/public/liens/{jeton}/fichier")
    assert r.status_code == 200, (r.status_code, r.text[:300])
    assert dechiffrer_fichier(cle, r.content) == clair, "fichier public (sans mot de passe) différent"
    sans_jeton = public.get(f"/public/liens/{jeton_mdp}/fichier").status_code
    assert sans_jeton in (401, 403), f"fichier protégé servi sans jeton de téléchargement ({sans_jeton})"
    sel = b64d(attendu(public.get(f"/public/liens/{jeton_mdp}"), 200)["selDerivation"])
    k_lien, verificateur = derivation_lien(MDP_LIEN, sel)
    corps = attendu(public.post(f"/public/liens/{jeton_mdp}/deverrouiller", json={"verificateurMotDePasse": b64(verificateur)}), 200)
    assert ouvrir(k_lien, b64d(corps["cleElementEnveloppee"]), f"lien:{corps['element']['id']}") == cle
    r = public.get(f"/public/liens/{jeton_mdp}/fichier", params={"t": corps["jetonTelechargement"]})
    assert r.status_code == 200 and dechiffrer_fichier(cle, r.content) == clair, "fichier public (avec mot de passe) différent"
    print("API : fichier public téléchargé et déchiffré à l'identique (sans et avec mot de passe).")


def verifier_signalement(api, element_id):
    """UC-I20 : motif invalide → 422, signalement valide → 201, lien révoqué → 410."""
    corps = {"elementId": element_id, "duree": "J7", "protegeParMotDePasse": False}
    jeton = attendu(api.post("/liens", json=corps), 201)
    public = httpx.Client(base_url=BASE + "/api/v1", timeout=30)
    url = f"/public/liens/{jeton['jeton']}/signalements"
    assert public.post(url, json={"motif": "INCONNU"}).status_code in (400, 422)
    attendu(public.post(url, json={"motif": "AUTRE", "commentaire": "Test e2e du signalement"}), 201)
    attendu(api.delete(f"/liens/{jeton['lien']['id']}"), 204)
    assert public.post(url, json={"motif": "AUTRE"}).status_code == 410
    print("API : signalement accepté (201), motif invalide refusé, lien révoqué → 410.")


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

    fichier, cle_f, clair, taille_chiffree = televerser_fichier(api, trousseau, maintenant)
    cles[fichier] = cle_f
    jetons = {}

    def lien(id_, mot_de_passe=None):
        corps = {"elementId": id_, "duree": "J7", "protegeParMotDePasse": mot_de_passe is not None}
        if mot_de_passe:
            sel = os.urandom(16)
            k_lien, verificateur = derivation_lien(mot_de_passe, sel)
            corps.update({"selDerivation": b64(sel), "cleElementEnveloppee": b64(aead(k_lien, cles[id_], f"lien:{id_}")), "verificateurMotDePasse": b64(verificateur)})
        jeton = attendu(api.post("/liens", json=corps), 201)["jeton"]
        jetons[id_, mot_de_passe] = jeton
        return f"{PAGE}?t={jeton}" + ("" if mot_de_passe else f"#{b64(cles[id_])}")

    print(f"Compte : {email}")
    print(f"POST_IT sans mot de passe : {lien(post_it)}")
    print(f"POST_IT avec mot de passe « {MDP_LIEN} » : {lien(post_it, MDP_LIEN)}")
    print(f"SNIPPET sans mot de passe : {lien(snippet)}")
    print(f"LISTE_TACHES sans mot de passe : {lien(liste)}")
    print(f"LISTE_TACHES avec mot de passe « {MDP_LIEN} » : {lien(liste, MDP_LIEN)}")
    url_f, url_f_mdp = lien(fichier), lien(fichier, MDP_LIEN)
    print(f"FICHIER ({len(clair)} o en clair, {taille_chiffree} o chiffrés, sha256 {hashlib.sha256(clair).hexdigest()})")
    print(f"FICHIER sans mot de passe : {url_f}")
    print(f"FICHIER avec mot de passe « {MDP_LIEN} » : {url_f_mdp}")
    verifier_fichier_public(jetons[fichier, None], jetons[fichier, MDP_LIEN], cle_f, clair)
    verifier_signalement(api, post_it)


# --- Faux LuluFiles (tests locaux uniquement) -----------------------------------------------------


def faux_lulufiles(port, dossier):
    """Imite les routes LuluFiles appelées par le backend : upload, état, lien signé, download (Range), suppression."""
    from email import policy
    from email.parser import BytesParser
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    dossier = Path(dossier)
    dossier.mkdir(parents=True, exist_ok=True)
    signes = {}

    class Gestion(BaseHTTPRequestHandler):
        def _json(self, code, corps):
            octets = json.dumps(corps).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(octets)))
            self.end_headers()
            self.wfile.write(octets)

        def _autorise(self):
            if self.headers.get("X-API-Key"):
                return True
            self._json(401, {"error": {"code": "unauthorized"}})
            return False

        def _chemin(self, id_):
            return dossier / f"{uuid.UUID(id_)}.bin"

        def do_POST(self):
            if not self._autorise():
                return
            if self.path == "/files/upload":
                brut = self.rfile.read(int(self.headers["Content-Length"]))
                message = BytesParser(policy=policy.default).parsebytes(b"Content-Type: " + self.headers["Content-Type"].encode() + b"\r\n\r\n" + brut)
                partie = next(p for p in message.iter_parts() if p.get_param("name", header="content-disposition") == "upload")
                id_ = str(uuid.uuid4())
                self._chemin(id_).write_bytes(partie.get_payload(decode=True))
                return self._json(201, {"id": id_, "status": "ready"})
            m = re.fullmatch(r"/files/([0-9a-f-]{36})/link", self.path)
            if m and self._chemin(m[1]).exists():
                signe = uuid.uuid4().hex
                signes[signe] = m[1]
                return self._json(200, {"url": f"/s/{signe}", "expires_at": datetime.now(timezone.utc).isoformat()})
            self._json(404, {"error": {"code": "not_found"}})

        def do_GET(self):
            m = re.fullmatch(r"/s/([0-9a-f]{32})", self.path)
            if m and m[1] in signes:
                return self._envoyer(signes[m[1]])
            if not self._autorise():
                return
            m = re.fullmatch(r"/files/([0-9a-f-]{36})(/download)?", self.path)
            if not m or not self._chemin(m[1]).exists():
                return self._json(404, {"error": {"code": "not_found"}})
            if m[2]:
                return self._envoyer(m[1])
            self._json(200, {"id": m[1], "status": "ready"})

        def do_DELETE(self):
            if not self._autorise():
                return
            m = re.match(r"/files/([0-9a-f-]{36})", self.path)
            if m and self._chemin(m[1]).exists():
                self._chemin(m[1]).unlink()
            self._json(200, {})

        def _envoyer(self, id_):
            octets = self._chemin(id_).read_bytes()
            plage = re.fullmatch(r"bytes=(\d+)-(\d*)", self.headers.get("Range", ""))
            debut, fin = (int(plage[1]), int(plage[2]) if plage[2] else len(octets) - 1) if plage else (0, len(octets) - 1)
            self.send_response(206 if plage else 200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(fin - debut + 1))
            self.send_header("Access-Control-Allow-Origin", "*")
            if plage:
                self.send_header("Content-Range", f"bytes {debut}-{fin}/{len(octets)}")
            self.end_headers()
            self.wfile.write(octets[debut : fin + 1])

    print(f"Faux LuluFiles sur http://127.0.0.1:{port} (dossier {dossier})", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Gestion).serve_forever()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "faux-lulufiles":
        faux_lulufiles(int(sys.argv[2]) if len(sys.argv) > 2 else 8099, sys.argv[3] if len(sys.argv) > 3 else "e2e_lulufiles")
    else:
        main()

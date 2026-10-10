"""Second appareil simulé : se connecte, attend l'approbation depuis l'app, puis déchiffre le Board.

Usage : uv run python e2e/second_appareil.py <email> <mot de passe>
Vérifie l'interopérabilité réelle app Flutter ↔ serveur ↔ implémentation de référence.
"""

import json
import sys
import time
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).parent))
from crypto import Appareil, Trousseau, ouvrir  # noqa: E402
from scenario import b64, deb64  # noqa: E402

API = "http://127.0.0.1:8000/api/v1"


def main(email, mdp):
    app = Appareil()
    c = httpx.Client(base_url=API, headers={"X-App-Version": "0.1.0"}, timeout=30)
    r = c.post("/auth/connexion", json={"email": email, "motDePasse": mdp, "appareil": {"nom": "Script de test", "type": "DESKTOP", "plateforme": "Python", "versionApp": "0.1.0", "clePublique": b64(app.publique)}})
    r.raise_for_status()
    c.headers["Authorization"] = "Bearer " + r.json()["session"]["jeton"]
    demande = c.post("/appareils/courant/deverrouillage").json()
    print(f"CODE A SAISIR DANS L'APP : {demande['codeAffiche']}", flush=True)
    for _ in range(120):
        r = c.get("/appareils/courant/enveloppe")
        if r.status_code == 200:
            break
        time.sleep(2)
    else:
        sys.exit("Pas d'approbation dans les 4 minutes.")
    maitre = app.desceller(deb64(r.json()["cleMaitreEnveloppee"]))
    t = Trousseau(maitre)
    changements = c.get("/synchro/changements", params={"depuis": 0}).json()["changements"]
    for ch in changements:
        if ch["entite"] != "element" or ch["supprimeLe"]:
            continue
        d = ch["donnees"]
        cle = t.cle_element(ch["id"], deb64(d["cleElementEnveloppee"]))
        clair = json.loads(ouvrir(cle, deb64(d["contenuChiffre"]), f"el:{ch['id']}"))
        print(f"DECHIFFRE {d['type']} : {clair}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

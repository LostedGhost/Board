"""Génère des vecteurs de test du format de chiffrement v1 pour vérifier l'implémentation Dart.

Usage : uv run python e2e/vecteurs.py ../app/test/vecteurs_crypto.json
"""

import json
import os
import sys
from pathlib import Path

from nacl import bindings
from nacl.public import PrivateKey

sys.path.insert(0, str(Path(__file__).parent))
from crypto import Appareil, Trousseau, aead, derivation_lien  # noqa: E402


def b64(o):
    import base64

    return base64.urlsafe_b64encode(o).rstrip(b"=").decode()


def secretstream(cle, clair, bloc=64 * 1024):
    etat = bindings.crypto_secretstream_xchacha20poly1305_state()
    entete = bindings.crypto_secretstream_xchacha20poly1305_init_push(etat, cle)
    sortie = bytearray(entete)
    morceaux = [clair[i : i + bloc] for i in range(0, len(clair), bloc)] or [b""]
    for i, m in enumerate(morceaux):
        tag = (
            bindings.crypto_secretstream_xchacha20poly1305_TAG_FINAL
            if i == len(morceaux) - 1
            else bindings.crypto_secretstream_xchacha20poly1305_TAG_MESSAGE
        )
        sortie += bindings.crypto_secretstream_xchacha20poly1305_push(etat, m, None, tag)
    return bytes(sortie)


def main():
    t = Trousseau()
    appareil = Appareil()
    id_el = "0192f5b4-0000-7000-8000-000000000001"
    cle_el, contenu, cle_env = t.nouvel_element(id_el, {"contenu": "Salut **Lulu** é€", "x": 1})
    sel = os.urandom(16)
    k_lien, verif = derivation_lien("mot de passe du lien", sel)
    fichier = os.urandom(150 * 1024)
    vecteurs = {
        "cleMaitre": b64(t.maitre),
        "cleRecup": b64(t.recup),
        "enveloppeRecuperation": b64(t.enveloppe_recuperation()),
        "clePubliqueVerification": b64(bytes(t.cle_verification.verify_key)),
        "defi": b64(b"defi-de-test-32-octets-exactemen"),
        "signatureDefi": b64(t.cle_verification.sign(b"defi-de-test-32-octets-exactemen").signature),
        "appareilPublique": b64(appareil.publique),
        "appareilPrivee": b64(bytes(appareil.prive)),
        "enveloppeAppareil": b64(Appareil.sceller_pour(appareil.publique, t.maitre)),
        "idElement": id_el,
        "cleElement": b64(cle_el),
        "cleElementEnveloppee": b64(cle_env),
        "contenuChiffre": b64(contenu),
        "contenuClair": {"contenu": "Salut **Lulu** é€", "x": 1},
        "lien": {"motDePasse": "mot de passe du lien", "sel": b64(sel), "cleLien": b64(k_lien), "verificateur": b64(verif)},
        "fichierClair": b64(fichier),
        "fichierChiffre": b64(secretstream(cle_el, fichier)),
        "tableau": {"id": "tb-1", "chiffre": b64(aead(t.maitre, b'{"nom":"Perso"}', "tb:tb-1"))},
    }
    Path(sys.argv[1]).write_text(json.dumps(vecteurs, indent=1), encoding="utf-8")
    print("vecteurs écrits :", sys.argv[1])


if __name__ == "__main__":
    PrivateKey  # noqa: B018 (import utilisé par crypto.Appareil)
    main()

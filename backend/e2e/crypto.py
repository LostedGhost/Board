"""Implémentation de référence du format de chiffrement v1 (docs/07-format-chiffrement.md), en Python.

Sert au scénario de bout en bout et de modèle pour l'implémentation Dart (mêmes octets attendus).
"""

import json
import os

from nacl import bindings, pwhash
from nacl.encoding import RawEncoder
from nacl.hash import blake2b
from nacl.public import PrivateKey, PublicKey, SealedBox
from nacl.signing import SigningKey

VERSION = b"\x01"
NONCE = 24


def aead(cle, clair, ad):
    nonce = os.urandom(NONCE)
    return VERSION + nonce + bindings.crypto_aead_xchacha20poly1305_ietf_encrypt(clair, ad.encode(), nonce, cle)


def ouvrir(cle, chiffre, ad):
    assert chiffre[:1] == VERSION, "version de format inconnue"
    nonce, corps = chiffre[1 : 1 + NONCE], chiffre[1 + NONCE :]
    return bindings.crypto_aead_xchacha20poly1305_ietf_decrypt(corps, ad.encode(), nonce, cle)


class Trousseau:
    """Clés d'un compte vues depuis un appareil."""

    def __init__(self, maitre=None, recup=None):
        self.maitre = maitre or os.urandom(32)
        self.recup = recup or os.urandom(32)

    @property
    def cle_verification(self):
        graine = blake2b(b"luluboard-verification-v1", digest_size=32, key=self.maitre, encoder=RawEncoder)
        return SigningKey(graine)

    def enveloppe_recuperation(self):
        return aead(self.recup, self.maitre, "recup:v1")

    @staticmethod
    def depuis_recuperation(recup, enveloppe):
        return Trousseau(ouvrir(recup, enveloppe, "recup:v1"), recup)

    # Éléments
    def nouvel_element(self, id_, donnees, cle=None):
        cle_el = cle or os.urandom(32)
        contenu = aead(cle_el, json.dumps(donnees).encode(), f"el:{id_}")
        return cle_el, contenu, aead(self.maitre, cle_el, f"cle:{id_}")

    def cle_element(self, id_, enveloppee):
        return ouvrir(self.maitre, enveloppee, f"cle:{id_}")


class Appareil:
    def __init__(self):
        self.prive = PrivateKey.generate()

    @property
    def publique(self):
        return bytes(self.prive.public_key)

    @staticmethod
    def sceller_pour(cle_publique, maitre):
        return SealedBox(PublicKey(cle_publique)).encrypt(maitre)

    def desceller(self, enveloppe):
        return SealedBox(self.prive).decrypt(enveloppe)


def derivation_lien(mot_de_passe, sel):
    s = pwhash.argon2id.kdf(
        64, mot_de_passe.encode(), sel, opslimit=pwhash.argon2id.OPSLIMIT_INTERACTIVE, memlimit=pwhash.argon2id.MEMLIMIT_INTERACTIVE
    )
    return s[:32], s[32:]

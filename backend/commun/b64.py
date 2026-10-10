"""Données chiffrées et clés publiques : échangées en base64url sans remplissage (contrat, section 1)."""

import base64
import binascii

from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers


def encoder(octets: bytes) -> str:
    return base64.urlsafe_b64encode(octets).rstrip(b"=").decode("ascii")


def decoder(texte: str) -> bytes:
    remplissage = "=" * (-len(texte) % 4)
    return base64.urlsafe_b64decode(texte + remplissage)


@extend_schema_field({"type": "string", "format": "base64url"})
class ChampBase64Url(serializers.Field):
    """Champ base64url : renvoie des octets ; taille contrôlée après décodage."""

    default_error_messages = {
        "invalide": "Encodage base64url invalide.",
        "taille": "Taille invalide.",
    }

    def __init__(self, *, taille_min=1, taille_max=1024, taille_exacte=None, **kwargs):
        self.taille_min = taille_min
        self.taille_max = taille_max
        self.taille_exacte = taille_exacte
        super().__init__(**kwargs)

    def to_internal_value(self, donnee):
        if not isinstance(donnee, str) or "=" in donnee:
            self.fail("invalide")
        try:
            octets = decoder(donnee)
        except (binascii.Error, ValueError):
            self.fail("invalide")
        if self.taille_exacte is not None and len(octets) != self.taille_exacte:
            self.fail("taille")
        if not self.taille_min <= len(octets) <= self.taille_max:
            self.fail("taille")
        return octets

    def to_representation(self, valeur):
        return encoder(bytes(valeur))

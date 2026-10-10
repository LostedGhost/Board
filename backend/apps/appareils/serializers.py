import re

from rest_framework import serializers

from apps.appareils.models import Appareil, TypeAppareil
from commun.b64 import ChampBase64Url

_VERSION = re.compile(r"^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$")


class AppareilNouveauSerializer(serializers.Serializer):
    nom = serializers.CharField(min_length=1, max_length=100)
    type = serializers.ChoiceField(choices=TypeAppareil.choices)
    plateforme = serializers.CharField(min_length=1, max_length=50)
    versionApp = serializers.RegexField(_VERSION, max_length=20)
    # Clé publique X25519 de l'appareil (32 octets).
    clePublique = ChampBase64Url(taille_exacte=32)

    def validate_clePublique(self, valeur):
        from commun.b64 import encoder

        return encoder(valeur)


class AppareilExistantSerializer(serializers.Serializer):
    appareilId = serializers.UUIDField()


class ClesInitialesSerializer(serializers.Serializer):
    enveloppeRecuperation = ChampBase64Url(taille_min=32, taille_max=512)
    enveloppeAppareil = ChampBase64Url(taille_min=32, taille_max=512)
    # Clé publique Ed25519 dérivée de la clé maître (32 octets).
    clePubliqueVerification = ChampBase64Url(taille_exacte=32)

    def validate_clePubliqueVerification(self, valeur):
        from commun.b64 import encoder

        return encoder(valeur)


class AppareilSerializer(serializers.ModelSerializer):
    versionApp = serializers.CharField(source="version_app")
    ajouteLe = serializers.DateTimeField(source="ajoute_le")
    derniereActiviteLe = serializers.DateTimeField(source="derniere_activite_le")
    courant = serializers.SerializerMethodField()

    class Meta:
        model = Appareil
        fields = ["id", "nom", "type", "plateforme", "versionApp", "statut", "ajouteLe", "derniereActiviteLe", "courant"]
        read_only_fields = fields

    def get_courant(self, appareil) -> bool:
        courant = self.context.get("appareil_courant")
        return courant is not None and courant.id == appareil.id


class SessionSerializer(serializers.Serializer):
    jeton = serializers.CharField()
    expireLe = serializers.DateTimeField()

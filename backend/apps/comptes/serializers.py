import re

from drf_spectacular.utils import PolymorphicProxySerializer, extend_schema_field
from rest_framework import serializers

from apps.appareils.serializers import (
    AppareilExistantSerializer,
    AppareilNouveauSerializer,
    AppareilSerializer,
    ClesInitialesSerializer,
    SessionSerializer,
)
from apps.comptes.models import Compte, TypeCode

_MAJUSCULE = re.compile(r"[A-ZÀ-ÖØ-Þ]")
_CHIFFRE = re.compile(r"\d")


def valider_mot_de_passe(valeur):
    """A1 : au moins 8 caractères, une majuscule et un chiffre."""
    if len(valeur) < 8 or not _MAJUSCULE.search(valeur) or not _CHIFFRE.search(valeur):
        raise serializers.ValidationError("Mot de passe trop faible.", code="trop_faible")
    return valeur


class InscriptionSerializer(serializers.Serializer):
    email = serializers.EmailField(max_length=254)
    nomAffichage = serializers.CharField(min_length=1, max_length=100, trim_whitespace=True)
    motDePasse = serializers.CharField(max_length=128, trim_whitespace=False, validators=[valider_mot_de_passe])
    conditionsAcceptees = serializers.ListField(child=serializers.UUIDField(), max_length=10, default=list)


class RenvoyerCodeSerializer(serializers.Serializer):
    email = serializers.EmailField(max_length=254)
    type = serializers.ChoiceField(choices=[TypeCode.INSCRIPTION])


class VerificationSerializer(serializers.Serializer):
    email = serializers.EmailField(max_length=254)
    code = serializers.RegexField(r"^\d{6}$")
    appareil = AppareilNouveauSerializer()
    cles = ClesInitialesSerializer()


@extend_schema_field(
    PolymorphicProxySerializer(
        component_name="AppareilNouveauOuExistant",
        serializers=[AppareilNouveauSerializer, AppareilExistantSerializer],
        resource_type_field_name=None,
    )
)
class ChampAppareil(serializers.Field):
    """AppareilNouveau ou { appareilId } (contrat 2.2)."""

    def to_internal_value(self, donnee):
        if isinstance(donnee, dict) and "appareilId" in donnee:
            s = AppareilExistantSerializer(data=donnee)
        else:
            s = AppareilNouveauSerializer(data=donnee)
        s.is_valid(raise_exception=True)
        return s.validated_data


class ConnexionSerializer(serializers.Serializer):
    email = serializers.EmailField(max_length=254)
    motDePasse = serializers.CharField(max_length=128, trim_whitespace=False)
    appareil = ChampAppareil()


class OubliSerializer(serializers.Serializer):
    email = serializers.EmailField(max_length=254)


class ReinitialisationSerializer(serializers.Serializer):
    email = serializers.EmailField(max_length=254)
    code = serializers.RegexField(r"^\d{6}$")
    nouveauMotDePasse = serializers.CharField(max_length=128, trim_whitespace=False, validators=[valider_mot_de_passe])


class GoogleSerializer(serializers.Serializer):
    idTokenGoogle = serializers.CharField(max_length=4096)
    appareil = ChampAppareil()
    conditionsAcceptees = serializers.ListField(child=serializers.UUIDField(), max_length=10, required=False)
    cles = ClesInitialesSerializer(required=False)


class CompteSerializer(serializers.ModelSerializer):
    nomAffichage = serializers.CharField(source="nom_affichage")
    aMotDePasse = serializers.SerializerMethodField()
    googleLie = serializers.BooleanField(source="google_lie")
    cleRecuperationConfirmee = serializers.SerializerMethodField()
    suppressionPrevueLe = serializers.DateTimeField(source="suppression_prevue_le")
    creeLe = serializers.DateTimeField(source="cree_le")

    class Meta:
        model = Compte
        fields = [
            "id",
            "email",
            "nomAffichage",
            "role",
            "statut",
            "aMotDePasse",
            "googleLie",
            "cleRecuperationConfirmee",
            "suppressionPrevueLe",
            "creeLe",
        ]
        read_only_fields = fields

    def get_aMotDePasse(self, compte) -> bool:
        return compte.has_usable_password()

    def get_cleRecuperationConfirmee(self, compte) -> bool:
        return compte.cle_recuperation_confirmee_le is not None


class ReponseSessionSerializer(serializers.Serializer):
    """Réponse commune à l'inscription vérifiée, à Google et à la connexion."""

    session = SessionSerializer()
    compte = CompteSerializer()
    appareil = AppareilSerializer()

"""Contrat 2.8 — envois entre appareils (🔐)."""

from datetime import timedelta

from django.db.models import Q
from django.utils import timezone
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.appareils.models import Appareil, StatutAppareil
from apps.elements.models import Element
from apps.envois.models import EnvoiAppareil, StatutEnvoi
from commun import push
from commun.b64 import ChampBase64Url
from commun.erreurs import ErreurApi
from commun.evenements import publier
from commun.limitation import limiter

DUREE_CONSERVATION = timedelta(days=7)  # D1


class EnvoiCreationSerializer(serializers.Serializer):
    id = serializers.UUIDField(required=False)  # choisi par le client : il sert de données associées au chiffrement
    appareilCibleId = serializers.UUIDField(required=False, allow_null=True)
    elementId = serializers.UUIDField(required=False, allow_null=True)
    contenuChiffre = ChampBase64Url(taille_min=1, taille_max=10 * 1024 * 1024 + 1024, required=False, allow_null=True)

    def validate(self, d):
        if not d.get("elementId") and not d.get("contenuChiffre"):
            raise serializers.ValidationError({"contenuChiffre": "Un élément ou un contenu est requis."}, code="requis")
        return d


class EnvoiSerializer(serializers.ModelSerializer):
    appareilSourceId = serializers.UUIDField(source="appareil_source_id")
    appareilCibleId = serializers.UUIDField(source="appareil_cible_id", allow_null=True)
    elementId = serializers.UUIDField(source="element_id", allow_null=True)
    contenuChiffre = ChampBase64Url(source="contenu_chiffre", allow_null=True)
    envoyeLe = serializers.DateTimeField(source="envoye_le")
    expireLe = serializers.DateTimeField(source="expire_le")

    class Meta:
        model = EnvoiAppareil
        fields = ["id", "appareilSourceId", "appareilCibleId", "elementId", "contenuChiffre", "statut", "envoyeLe", "expireLe"]
        read_only_fields = fields

    def to_representation(self, envoi):
        donnees = super().to_representation(envoi)
        if envoi.contenu_chiffre is None:
            donnees["contenuChiffre"] = None
        return donnees


def _recus(request):
    moi = request.appareil
    return EnvoiAppareil.objects.filter(compte=request.user, statut=StatutEnvoi.EN_ATTENTE, expire_le__gt=timezone.now()).filter(
        Q(appareil_cible=moi) | (Q(appareil_cible__isnull=True) & ~Q(appareil_source=moi) & ~Q(recupere_par__contains=[str(moi.id)]))
    )


class EnvoisView(APIView):
    @extend_schema(request=EnvoiCreationSerializer, responses={201: EnvoiSerializer})
    def post(self, request):
        limiter("envois", request.user.id, maximum=300, fenetre_s=3600)
        s = EnvoiCreationSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        cible = None
        if d.get("appareilCibleId"):
            cible = Appareil.objects.filter(id=d["appareilCibleId"], compte=request.user, statut=StatutAppareil.ACTIF).first()
            if cible is None or cible.id == request.appareil.id:
                raise ErreurApi("introuvable", "Appareil destinataire introuvable.", status.HTTP_404_NOT_FOUND)
        if d.get("elementId") and not Element.objects.filter(id=d["elementId"], compte=request.user, supprime_le__isnull=True).exists():
            raise ErreurApi("introuvable", "Élément introuvable.", status.HTTP_404_NOT_FOUND)
        if d.get("id") and EnvoiAppareil.objects.filter(id=d["id"]).exists():
            raise ErreurApi("deja_traite", "Cet identifiant existe déjà.", status.HTTP_409_CONFLICT)

        extra = {"id": d["id"]} if d.get("id") else {}
        envoi = EnvoiAppareil.objects.create(
            compte=request.user,
            appareil_source=request.appareil,
            appareil_cible=cible,
            element_id=d.get("elementId"),
            contenu_chiffre=d.get("contenuChiffre"),
            expire_le=timezone.now() + DUREE_CONSERVATION,
            **extra,
        )
        publier(request.user.id, "envoi_recu", envoiId=envoi.id)
        destinataires = [cible] if cible else list(
            Appareil.objects.select_related("preferences").filter(compte=request.user, statut=StatutAppareil.ACTIF).exclude(id=request.appareil.id)
        )
        push.notifier(destinataires, "ENVOIS_APPAREILS", {"envoiId": envoi.id})
        return Response(EnvoiSerializer(envoi).data, status=status.HTTP_201_CREATED)


class RecusView(APIView):
    @extend_schema(parameters=[OpenApiParameter("statut", str, required=False)], responses=EnvoiSerializer(many=True))
    def get(self, request):
        return Response(EnvoiSerializer(_recus(request).order_by("envoye_le"), many=True).data)


class RecupereView(APIView):
    @extend_schema(request=None, responses={204: None})
    def post(self, request, envoi_id):
        envoi = _recus(request).filter(id=envoi_id).first()
        if envoi is None:
            raise ErreurApi("introuvable", "Envoi introuvable.", status.HTTP_404_NOT_FOUND)
        if envoi.appareil_cible_id:
            envoi.statut = StatutEnvoi.REMIS
            envoi.recupere_le = timezone.now()
            envoi.contenu_chiffre = None  # remis : le serveur n'a plus de raison de le garder
        else:
            envoi.recupere_par = [*envoi.recupere_par, str(request.appareil.id)]
            envoi.recupere_le = timezone.now()
        envoi.save()
        return Response(status=status.HTTP_204_NO_CONTENT)

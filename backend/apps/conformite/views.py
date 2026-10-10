"""Contrat 2.11 — annonces, support, export."""

from django.conf import settings
from django.core.mail import send_mail
from django.db.models import Q
from django.utils import timezone
from drf_spectacular.utils import extend_schema, inline_serializer
from rest_framework import serializers, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.appareils.authentification import AuthentificationSession
from apps.comptes.serializers import CompteSerializer
from apps.conformite.models import Annonce, DemandeSupport
from apps.fichiers.models import Fichier
from apps.synchro.services import ENTITES, representer
from commun.limitation import ip_client, limiter


class AnnonceSerializer(serializers.ModelSerializer):
    messageFr = serializers.CharField(source="message_fr")
    messageEn = serializers.CharField(source="message_en")
    debutLe = serializers.DateTimeField(source="debut_le")
    finLe = serializers.DateTimeField(source="fin_le", allow_null=True)

    class Meta:
        model = Annonce
        fields = ["id", "messageFr", "messageEn", "debutLe", "finLe"]


class SupportSerializer(serializers.Serializer):
    emailContact = serializers.EmailField(max_length=254)
    message = serializers.CharField(min_length=5, max_length=5000)
    infosTechniques = serializers.CharField(max_length=5000, required=False, allow_blank=True)


class AnnoncesActivesView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    @extend_schema(responses=AnnonceSerializer(many=True))
    def get(self, request):
        maintenant = timezone.now()
        annonces = Annonce.objects.filter(debut_le__lte=maintenant).filter(Q(fin_le__isnull=True) | Q(fin_le__gt=maintenant))
        return Response(AnnonceSerializer(annonces.order_by("-debut_le"), many=True).data)


class SupportView(APIView):
    permission_classes = [AllowAny]

    def get_authenticators(self):
        # Facultative : un utilisateur connecté voit sa demande rattachée à son compte.
        return [AuthentificationSession()]

    @extend_schema(request=SupportSerializer, responses={201: None})
    def post(self, request):
        limiter("support_ip", ip_client(request), maximum=5, fenetre_s=3600)
        s = SupportSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        DemandeSupport.objects.create(
            compte=request.user if request.user is not None else None,
            email_contact=d["emailContact"],
            message=d["message"],
            infos_techniques=d.get("infosTechniques") or None,
        )
        if settings.SUPPORT_EMAIL:
            send_mail(
                "LuluBoard : nouvelle demande de support",
                f"De : {d['emailContact']}\n\n{d['message']}\n\n--- Infos techniques ---\n{d.get('infosTechniques') or '-'}",
                settings.DEFAULT_FROM_EMAIL,
                [settings.SUPPORT_EMAIL],
                fail_silently=True,
            )
        return Response(status=status.HTTP_201_CREATED)


class ExportView(APIView):
    """A6 : toutes les données CHIFFRÉES du compte ; l'app les déchiffre et assemble l'export en local."""

    dispenses = {"conditions"}

    @extend_schema(responses=inline_serializer("Export", {"compte": CompteSerializer(), "entites": serializers.ListField(), "fichiers": serializers.ListField()}))
    def get(self, request):
        limiter("export", request.user.id, maximum=10, fenetre_s=3600)
        entites = []
        for entite, definition in ENTITES.items():
            for objet in definition.modele.objects.filter(compte=request.user, supprime_le__isnull=True).order_by("version"):
                entites.append(representer(entite, objet))
        fichiers = [
            {"id": f.element_id, "tailleOctets": f.taille_octets, "statut": f.statut}
            for f in Fichier.objects.filter(element__compte=request.user, element__supprime_le__isnull=True)
        ]
        reponse = Response({"compte": CompteSerializer(request.user).data, "exporteLe": timezone.now(), "entites": entites, "fichiers": fichiers})
        reponse["Cache-Control"] = "no-store"
        return reponse

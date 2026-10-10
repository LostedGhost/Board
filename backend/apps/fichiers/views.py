"""Contrat 2.7 — fichiers (comptes uniquement, 🔐)."""

import json

from django.http import StreamingHttpResponse
from drf_spectacular.utils import extend_schema, inline_serializer
from rest_framework import serializers, status
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.fichiers import services, stockage
from apps.fichiers.models import FournisseurStockage, Fichier
from commun.b64 import ChampBase64Url
from commun.erreurs import ErreurApi
from commun.limitation import limiter


class MetadonneesSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    modifieLe = serializers.DateTimeField()
    tailleOctets = serializers.IntegerField(min_value=1)
    cleElementEnveloppee = ChampBase64Url(taille_min=32, taille_max=512)
    contenuChiffre = ChampBase64Url(taille_min=1, taille_max=16 * 1024)  # nom + type MIME chiffrés


class FichierSerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(source="element_id")
    tailleOctets = serializers.IntegerField(source="taille_octets")
    messageErreur = serializers.CharField(source="message_erreur")
    creeLe = serializers.DateTimeField(source="cree_le")

    class Meta:
        model = Fichier
        fields = ["id", "statut", "tailleOctets", "fournisseur", "messageErreur", "creeLe"]
        read_only_fields = fields


class FichiersView(APIView):
    parser_classes = [MultiPartParser]

    @extend_schema(
        request={"multipart/form-data": inline_serializer("Televersement", {"metadonnees": serializers.CharField(), "fichier": serializers.FileField()})},
        responses={202: FichierSerializer},
    )
    def post(self, request):
        limiter("televersement", request.user.id, maximum=120, fenetre_s=3600)
        televerse = request.FILES.get("fichier")
        if televerse is None:
            raise ErreurApi("validation", "Fichier manquant.", status.HTTP_422_UNPROCESSABLE_ENTITY, champs=[{"champ": "fichier", "raison": "requis"}])
        try:
            brut = json.loads(request.data.get("metadonnees") or "")
        except ValueError:
            raise ErreurApi("validation", "Métadonnées illisibles.", status.HTTP_422_UNPROCESSABLE_ENTITY, champs=[{"champ": "metadonnees", "raison": "invalide"}])
        s = MetadonneesSerializer(data=brut)
        s.is_valid(raise_exception=True)
        fichier = services.creer(request.user, request.appareil, s.validated_data, televerse)
        return Response(FichierSerializer(fichier).data, status=status.HTTP_202_ACCEPTED)


class FichierView(APIView):
    @extend_schema(responses=FichierSerializer)
    def get(self, request, fichier_id):
        return Response(FichierSerializer(services.fichier_du_compte(request.user, fichier_id)).data)


class AccesView(APIView):
    @extend_schema(responses=inline_serializer("AccesFichier", {"mode": serializers.CharField(), "url": serializers.CharField()}))
    def get(self, request, fichier_id):
        return Response(services.acces(services.fichier_du_compte(request.user, fichier_id)))


def reponse_flux(request, fichier):
    """Octets chiffrés, avec prise en charge de Range (reprise de téléchargement)."""
    plage = services.analyser_plage(request.headers.get("Range"), fichier.taille_octets)
    debut, fin = plage or (0, fichier.taille_octets - 1)
    if fichier.fournisseur == FournisseurStockage.TELEGRAM_DIRECT:
        corps = services.flux_telegram(fichier, debut, fin)
    else:
        client, distant = stockage.LuluFiles().flux(fichier.id_lulufiles, f"bytes={debut}-{fin}" if plage else None)

        def corps():
            try:
                yield from distant.iter_bytes()
            finally:
                distant.close()
                client.close()

        corps = corps()
    reponse = StreamingHttpResponse(corps, content_type="application/octet-stream", status=206 if plage else 200)
    reponse["Content-Length"] = str(fin - debut + 1)
    reponse["Accept-Ranges"] = "bytes"
    if plage:
        reponse["Content-Range"] = f"bytes {debut}-{fin}/{fichier.taille_octets}"
    reponse["Cache-Control"] = "private, no-store"
    return reponse


class ContenuView(APIView):
    @extend_schema(responses={(200, "application/octet-stream"): bytes})
    def get(self, request, fichier_id):
        fichier = services.fichier_du_compte(request.user, fichier_id)
        if fichier.statut != "PRET":
            raise ErreurApi("deja_traite", "Le fichier n'est pas encore prêt.", status.HTTP_409_CONFLICT)
        return reponse_flux(request, fichier)


class ReessayerView(APIView):
    @extend_schema(request=None, responses={202: FichierSerializer})
    def post(self, request, fichier_id):
        fichier = services.reessayer(services.fichier_du_compte(request.user, fichier_id))
        return Response(FichierSerializer(fichier).data, status=status.HTTP_202_ACCEPTED)

"""Contrat 2.3 — appareils et clés."""

from drf_spectacular.utils import extend_schema, inline_serializer
from rest_framework import serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.appareils import deverrouillage
from apps.appareils.models import Appareil, StatutAppareil
from apps.appareils.permissions import AppareilDeverrouille, SessionRequise
from apps.appareils.serializers import AppareilSerializer
from apps.comptes.google import verifier_id_token
from commun.b64 import ChampBase64Url, encoder
from commun.erreurs import ErreurApi

class EnveloppeSerializer(serializers.Serializer):
    cleMaitreEnveloppee = ChampBase64Url(taille_min=32, taille_max=512)


class RenommerSerializer(serializers.Serializer):
    nom = serializers.CharField(min_length=1, max_length=100)


class ApprobationSerializer(serializers.Serializer):
    codeAffiche = serializers.RegexField(r"^\d{6}$")
    cleMaitreEnveloppee = ChampBase64Url(taille_min=32, taille_max=512)


class RecuperationSerializer(serializers.Serializer):
    cleMaitreEnveloppee = ChampBase64Url(taille_min=32, taille_max=512)
    signatureDefi = ChampBase64Url(taille_exacte=64)


class RegenerationSerializer(serializers.Serializer):
    """Mot de passe requis ; pour un compte Google sans mot de passe, un jeton Google récent (décision D8)."""

    motDePasse = serializers.CharField(max_length=128, trim_whitespace=False, required=False)
    idTokenGoogle = serializers.CharField(max_length=4096, required=False)
    cleMaitreEnveloppee = ChampBase64Url(taille_min=32, taille_max=512)


class DemandeSerializer(serializers.Serializer):
    """DemandeDeverrouillageDTO. Le code n'est montré qu'à l'appareil demandeur."""

    id = serializers.UUIDField()
    statut = serializers.CharField()
    expireLe = serializers.DateTimeField(source="expire_le")
    appareilDemandeur = serializers.SerializerMethodField()
    clePubliqueDemandeur = serializers.CharField(source="appareil.cle_publique")

    def get_appareilDemandeur(self, demande) -> dict:
        return AppareilSerializer(demande.appareil).data


class DemandeAvecCodeSerializer(DemandeSerializer):
    codeAffiche = serializers.CharField(source="code_affiche")


class ListeAppareilsView(APIView):
    permission_classes = [SessionRequise]

    @extend_schema(responses=AppareilSerializer(many=True))
    def get(self, request):
        appareils = Appareil.objects.filter(compte=request.user).exclude(statut=StatutAppareil.REVOQUE).order_by("ajoute_le")
        return Response(AppareilSerializer(appareils, many=True, context={"appareil_courant": request.appareil}).data)


class AppareilView(APIView):
    @extend_schema(request=RenommerSerializer, responses=AppareilSerializer)
    def patch(self, request, appareil_id):
        s = RenommerSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        appareil = Appareil.objects.filter(id=appareil_id, compte=request.user).exclude(statut=StatutAppareil.REVOQUE).first()
        if appareil is None:
            raise ErreurApi("introuvable", "Ressource introuvable.", status.HTTP_404_NOT_FOUND)
        appareil.nom = s.validated_data["nom"]
        appareil.save(update_fields=["nom"])
        return Response(AppareilSerializer(appareil, context={"appareil_courant": request.appareil}).data)

    @extend_schema(responses={204: None})
    def delete(self, request, appareil_id):
        deverrouillage.revoquer(request.user, appareil_id)
        return Response(status=status.HTTP_204_NO_CONTENT)


class EnveloppeCouranteView(APIView):
    @extend_schema(responses=EnveloppeSerializer)
    def get(self, request):
        return Response({"cleMaitreEnveloppee": encoder(deverrouillage.enveloppe_appareil(request.appareil))})


class DemandeCouranteView(APIView):
    permission_classes = [SessionRequise]

    @extend_schema(request=None, responses={201: DemandeAvecCodeSerializer})
    def post(self, request):
        demande = deverrouillage.creer_demande(request.appareil)
        return Response(DemandeAvecCodeSerializer(demande).data, status=status.HTTP_201_CREATED)


class DemandesEnAttenteView(APIView):
    @extend_schema(responses=DemandeSerializer(many=True))
    def get(self, request):
        return Response(DemandeSerializer(deverrouillage.demandes_en_attente(request.user), many=True).data)


class ApprouverView(APIView):
    @extend_schema(request=ApprobationSerializer, responses={204: None})
    def post(self, request, demande_id):
        s = ApprobationSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        deverrouillage.approuver(request.user, demande_id, request.appareil, d["codeAffiche"], d["cleMaitreEnveloppee"])
        return Response(status=status.HTTP_204_NO_CONTENT)


class RefuserView(APIView):
    @extend_schema(request=None, responses={204: None})
    def post(self, request, demande_id):
        deverrouillage.refuser(request.user, demande_id, request.appareil)
        return Response(status=status.HTTP_204_NO_CONTENT)


class EnveloppeRecuperationView(APIView):
    def get_permissions(self):
        # GET : nouvel appareil pas encore déverrouillé (🔑) ; PUT : régénération (🔐).
        return [SessionRequise()] if self.request.method == "GET" else [AppareilDeverrouille()]

    dispenses = {"cle_recuperation"}

    @extend_schema(
        responses=inline_serializer(
            "EnveloppeRecuperation",
            {"cleMaitreEnveloppee": serializers.CharField(), "defi": serializers.CharField()},
        )
    )
    def get(self, request):
        enveloppe, defi = deverrouillage.enveloppe_recuperation(request.user, request.appareil)
        reponse = Response({"cleMaitreEnveloppee": encoder(enveloppe), "defi": encoder(defi)})
        reponse["Cache-Control"] = "no-store"
        return reponse

    @extend_schema(request=RegenerationSerializer, responses={204: None})
    def put(self, request):
        s = RegenerationSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        compte = request.user
        if compte.has_usable_password():
            if not compte.check_password(d.get("motDePasse") or ""):
                raise ErreurApi("identifiants_incorrects", "Mot de passe incorrect.", status.HTTP_401_UNAUTHORIZED)
        else:
            identite = verifier_id_token(d.get("idTokenGoogle") or "")
            if not compte.google_lie or identite["sujet"] != compte.identite_google.sujet_google:
                raise ErreurApi("identifiants_incorrects", "Identité Google incorrecte.", status.HTTP_401_UNAUTHORIZED)
        deverrouillage.regenerer_cle_recuperation(compte, d["cleMaitreEnveloppee"])
        return Response(status=status.HTTP_204_NO_CONTENT)


class DeverrouillerParRecuperationView(APIView):
    permission_classes = [SessionRequise]

    @extend_schema(request=RecuperationSerializer, responses={204: None})
    def post(self, request):
        s = RecuperationSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        deverrouillage.deverrouiller_par_recuperation(request.appareil, d["cleMaitreEnveloppee"], d["signatureDefi"])
        return Response(status=status.HTTP_204_NO_CONTENT)

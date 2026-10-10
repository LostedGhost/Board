"""Contrat 2.1 — inscription et vérification (A1, A1b)."""

from drf_spectacular.utils import extend_schema, inline_serializer
from rest_framework import serializers
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.appareils.permissions import AppareilDeverrouille
from apps.comptes import services
from apps.comptes.emails import envoyer_code, langue_de
from apps.comptes.google import verifier_id_token
from apps.comptes.models import TypeCode
from apps.comptes import codes
from apps.comptes.serializers import (
    CompteSerializer,
    GoogleSerializer,
    ReponseSessionSerializer,
    InscriptionSerializer,
    RenvoyerCodeSerializer,
    VerificationSerializer,
)
from apps.appareils.serializers import AppareilSerializer
from commun.limitation import ip_client, limiter


def reponse_session(compte, appareil, jeton, expire_le, statut=status.HTTP_200_OK, extra=None):
    corps = {
        "session": {"jeton": jeton, "expireLe": expire_le},
        "compte": CompteSerializer(compte).data,
        "appareil": AppareilSerializer(appareil, context={"appareil_courant": appareil}).data,
    }
    if extra:
        corps.update(extra)
    reponse = Response(corps, status=statut)
    reponse["Cache-Control"] = "no-store"  # la réponse contient le jeton de session
    return reponse


class VuePublique(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []


class InscriptionView(VuePublique):
    @extend_schema(
        request=InscriptionSerializer,
        responses={201: inline_serializer("InscriptionReponse", {"compteId": serializers.UUIDField()})},
    )
    def post(self, request):
        limiter("inscription_ip", ip_client(request), maximum=10, fenetre_s=3600)
        s = InscriptionSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        compte, code = services.inscrire(d["email"], d["nomAffichage"], d["motDePasse"], d["conditionsAcceptees"])
        envoyer_code(compte.email, TypeCode.INSCRIPTION, code, langue_de(request))
        return Response({"compteId": str(compte.id)}, status=status.HTTP_201_CREATED)


class RenvoyerCodeView(VuePublique):
    @extend_schema(request=RenvoyerCodeSerializer, responses={204: None})
    def post(self, request):
        s = RenvoyerCodeSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        email = s.validated_data["email"].strip().lower()
        limiter("renvoi_ip", ip_client(request), maximum=20, fenetre_s=3600)
        limiter("renvoi_email", email, maximum=5, fenetre_s=3600)
        compte = services.compte_en_attente(email)
        if compte is not None:
            envoyer_code(compte.email, TypeCode.INSCRIPTION, codes.emettre_code(compte, TypeCode.INSCRIPTION), langue_de(request))
        # Toujours 204 : on ne révèle pas si le compte existe.
        return Response(status=status.HTTP_204_NO_CONTENT)


class VerificationView(VuePublique):
    @extend_schema(request=VerificationSerializer, responses={201: ReponseSessionSerializer})
    def post(self, request):
        limiter("verification_ip", ip_client(request), maximum=30, fenetre_s=900)
        s = VerificationSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        compte, appareil, jeton, expire_le = services.verifier_inscription(d["email"], d["code"], d["appareil"], d["cles"])
        return reponse_session(compte, appareil, jeton, expire_le, status.HTTP_201_CREATED)


class GoogleView(VuePublique):
    @extend_schema(
        request=GoogleSerializer,
        responses={
            200: inline_serializer(
                "GoogleReponse",
                {
                    "session": ReponseSessionSerializer().fields["session"].__class__(),
                    "compte": CompteSerializer(),
                    "appareil": AppareilSerializer(),
                    "nouveauCompte": serializers.BooleanField(),
                },
            )
        },
    )
    def post(self, request):
        limiter("google_ip", ip_client(request), maximum=30, fenetre_s=900)
        s = GoogleSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        identite = verifier_id_token(d["idTokenGoogle"])
        compte, appareil, jeton, expire_le, nouveau = services.connexion_google(
            identite, d["appareil"], d.get("conditionsAcceptees"), d.get("cles")
        )
        return reponse_session(compte, appareil, jeton, expire_le, extra={"nouveauCompte": nouveau})


class ConfirmerCleRecuperationView(APIView):
    permission_classes = [AppareilDeverrouille]
    dispenses = {"cle_recuperation"}

    @extend_schema(request=None, responses={204: None})
    def post(self, request):
        services.confirmer_cle_recuperation(request.user)
        return Response(status=status.HTTP_204_NO_CONTENT)

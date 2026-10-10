"""Contrat 2.4 — compte, préférences, conditions."""

from django.conf import settings
from django.core.mail import send_mail
from drf_spectacular.utils import extend_schema, inline_serializer
from rest_framework import serializers, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.appareils.models import CategorieNotification, PreferencesAppareil, TypePush, VerrouLocal
from apps.appareils.permissions import SessionRequise
from apps.comptes import gestion
from apps.comptes.emails import envoyer_code, langue_de
from apps.comptes.models import DureeConservation, Langue, PreferencesCompte, Theme, TypeCode
from apps.comptes.serializers import CompteSerializer, valider_mot_de_passe
from apps.conformite.models import VersionConditions
from apps.conformite.services import conditions_a_accepter, conditions_actuelles, enregistrer_acceptations
from commun.erreurs import ErreurApi
from commun.limitation import limiter


class VersionConditionsSerializer(serializers.ModelSerializer):
    publieeLe = serializers.DateTimeField(source="publiee_le")
    urlTexte = serializers.URLField(source="url_texte")

    class Meta:
        model = VersionConditions
        fields = ["id", "type", "numero", "publieeLe", "urlTexte"]


class CompteDetailSerializer(CompteSerializer):
    conditionsAAccepter = serializers.SerializerMethodField()

    class Meta(CompteSerializer.Meta):
        fields = CompteSerializer.Meta.fields + ["conditionsAAccepter"]
        read_only_fields = fields

    def get_conditionsAAccepter(self, compte) -> list:
        return VersionConditionsSerializer(conditions_a_accepter(compte), many=True).data


class ConfirmationIdentite(serializers.Serializer):
    motDePasse = serializers.CharField(max_length=128, trim_whitespace=False, required=False)
    idTokenGoogle = serializers.CharField(max_length=4096, required=False)


class ChangementEmailSerializer(ConfirmationIdentite):
    nouvelEmail = serializers.EmailField(max_length=254)


class ChangementMotDePasseSerializer(serializers.Serializer):
    ancienMotDePasse = serializers.CharField(max_length=128, trim_whitespace=False, required=False, allow_blank=True)
    nouveauMotDePasse = serializers.CharField(max_length=128, trim_whitespace=False, validators=[valider_mot_de_passe])
    deconnecterAutresAppareils = serializers.BooleanField(default=False)


class PreferencesCompteSerializer(serializers.ModelSerializer):
    fuseauHoraire = serializers.CharField(source="fuseau_horaire", max_length=64)
    retentionPressePapier = serializers.ChoiceField(source="retention_presse_papier", choices=DureeConservation.choices)
    retentionVersions = serializers.ChoiceField(source="retention_versions", choices=DureeConservation.choices)
    theme = serializers.ChoiceField(choices=Theme.choices)
    langue = serializers.ChoiceField(choices=Langue.choices)

    class Meta:
        model = PreferencesCompte
        fields = ["theme", "langue", "fuseauHoraire", "retentionPressePapier", "retentionVersions"]

    def validate_fuseauHoraire(self, valeur):
        from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

        try:
            ZoneInfo(valeur)
        except (ZoneInfoNotFoundError, ValueError):
            raise serializers.ValidationError("Fuseau horaire inconnu.", code="invalide")
        return valeur

    def validate_retentionPressePapier(self, valeur):
        if valeur == DureeConservation.H1:  # B4 : 1 h n'existe que pour les versions (C3)
            raise serializers.ValidationError("Durée non proposée pour le presse-papier.", code="invalide")
        return valeur


class PreferencesAppareilSerializer(serializers.ModelSerializer):
    raccourciHistorique = serializers.CharField(source="raccourci_historique", max_length=40)
    raccourciCaptureRapide = serializers.CharField(source="raccourci_capture_rapide", max_length=40)
    demarrageAuto = serializers.BooleanField(source="demarrage_auto")
    capturePressePapierEnPause = serializers.BooleanField(source="capture_presse_papier_en_pause")
    notificationsActives = serializers.ListField(
        source="notifications_actives", child=serializers.ChoiceField(choices=CategorieNotification.choices), max_length=10
    )
    verrouLocal = serializers.ChoiceField(source="verrou_local", choices=VerrouLocal.choices)
    jetonPush = serializers.CharField(max_length=4096, required=False, allow_null=True, write_only=True)
    typePush = serializers.ChoiceField(choices=TypePush.choices, required=False, allow_null=True, write_only=True)

    class Meta:
        model = PreferencesAppareil
        fields = [
            "raccourciHistorique",
            "raccourciCaptureRapide",
            "demarrageAuto",
            "capturePressePapierEnPause",
            "notificationsActives",
            "verrouLocal",
            "jetonPush",
            "typePush",
        ]

    def validate_notificationsActives(self, valeur):
        # Les notifications de sécurité ne peuvent pas être désactivées (I7).
        return sorted(set(valeur) | {CategorieNotification.SECURITE})

    def update(self, instance, donnees):
        appareil = instance.appareil
        if "jetonPush" in donnees or "typePush" in donnees:
            appareil.jeton_push = donnees.pop("jetonPush", appareil.jeton_push)
            appareil.type_push = donnees.pop("typePush", appareil.type_push)
            appareil.save(update_fields=["jeton_push", "type_push"])
        return super().update(instance, donnees)


class CompteView(APIView):
    # Refuser les nouvelles conditions doit rester possible en supprimant son compte.
    dispenses = {"conditions", "cle_recuperation"}

    def get_permissions(self):
        return [SessionRequise()] if self.request.method == "GET" else super().get_permissions()

    @extend_schema(responses=CompteDetailSerializer)
    def get(self, request):
        return Response(CompteDetailSerializer(request.user).data)

    @extend_schema(
        request=inline_serializer("CompteModification", {"nomAffichage": serializers.CharField(max_length=100)}),
        responses=CompteSerializer,
    )
    def patch(self, request):
        nom = serializers.CharField(min_length=1, max_length=100).run_validation(request.data.get("nomAffichage"))
        request.user.nom_affichage = nom
        request.user.save(update_fields=["nom_affichage"])
        return Response(CompteSerializer(request.user).data)

    @extend_schema(
        request=ConfirmationIdentite,
        responses=inline_serializer("SuppressionCompte", {"suppressionPrevueLe": serializers.DateTimeField()}),
    )
    def delete(self, request):
        s = ConfirmationIdentite(data=request.data)
        s.is_valid(raise_exception=True)
        date = gestion.programmer_suppression(request.user, s.validated_data.get("motDePasse"), s.validated_data.get("idTokenGoogle"))
        return Response({"suppressionPrevueLe": date})


class MotDePasseView(APIView):
    @extend_schema(request=ChangementMotDePasseSerializer, responses={204: None})
    def post(self, request):
        limiter("changement_mdp", request.user.id, maximum=10, fenetre_s=3600)
        s = ChangementMotDePasseSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        gestion.changer_mot_de_passe(request.user, request.auth, d.get("ancienMotDePasse"), d["nouveauMotDePasse"], d["deconnecterAutresAppareils"])
        return Response(status=status.HTTP_204_NO_CONTENT)


class EmailView(APIView):
    @extend_schema(request=ChangementEmailSerializer, responses={204: None})
    def post(self, request):
        limiter("changement_email", request.user.id, maximum=5, fenetre_s=3600)
        s = ChangementEmailSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        code = gestion.demander_changement_email(request.user, d["nouvelEmail"], d.get("motDePasse"), d.get("idTokenGoogle"))
        langue = langue_de(request)
        envoyer_code(d["nouvelEmail"], TypeCode.CHANGEMENT_EMAIL, code, langue)
        send_mail(
            "LuluBoard : changement d'adresse demandé" if langue == "fr" else "LuluBoard: address change requested",
            "Un changement d'adresse e-mail a été demandé pour votre compte. Si ce n'est pas vous, changez votre mot de passe."
            if langue == "fr"
            else "An e-mail address change was requested for your account. If it wasn't you, change your password.",
            settings.DEFAULT_FROM_EMAIL,
            [request.user.email],
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class EmailVerificationView(APIView):
    @extend_schema(request=inline_serializer("CodeEmail", {"code": serializers.CharField()}), responses=CompteSerializer)
    def post(self, request):
        code = serializers.RegexField(r"^\d{6}$").run_validation(request.data.get("code"))
        gestion.confirmer_changement_email(request.user, code)
        return Response(CompteSerializer(request.user).data)


class GoogleLiaisonView(APIView):
    @extend_schema(request=inline_serializer("LiaisonGoogle", {"idTokenGoogle": serializers.CharField()}), responses={204: None})
    def post(self, request):
        jeton = serializers.CharField(max_length=4096).run_validation(request.data.get("idTokenGoogle"))
        gestion.lier_google(request.user, jeton)
        return Response(status=status.HTTP_204_NO_CONTENT)

    @extend_schema(responses={204: None})
    def delete(self, request):
        gestion.delier_google(request.user)
        return Response(status=status.HTTP_204_NO_CONTENT)


class PreferencesCompteView(APIView):
    @extend_schema(responses=PreferencesCompteSerializer)
    def get(self, request):
        prefs, _ = PreferencesCompte.objects.get_or_create(compte=request.user)
        return Response(PreferencesCompteSerializer(prefs).data)

    @extend_schema(request=PreferencesCompteSerializer, responses=PreferencesCompteSerializer)
    def put(self, request):
        prefs, _ = PreferencesCompte.objects.get_or_create(compte=request.user)
        s = PreferencesCompteSerializer(prefs, data=request.data)
        s.is_valid(raise_exception=True)
        s.save()
        return Response(s.data)


class PreferencesAppareilView(APIView):
    @extend_schema(responses=PreferencesAppareilSerializer)
    def get(self, request):
        prefs, _ = PreferencesAppareil.objects.get_or_create(appareil=request.appareil)
        return Response(PreferencesAppareilSerializer(prefs).data)

    @extend_schema(request=PreferencesAppareilSerializer, responses=PreferencesAppareilSerializer)
    def put(self, request):
        prefs, _ = PreferencesAppareil.objects.get_or_create(appareil=request.appareil)
        s = PreferencesAppareilSerializer(prefs, data=request.data)
        s.is_valid(raise_exception=True)
        s.save()
        return Response(s.data)


class ConditionsActuellesView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    @extend_schema(responses=VersionConditionsSerializer(many=True))
    def get(self, request):
        return Response(VersionConditionsSerializer(conditions_actuelles(), many=True).data)


class AccepterConditionsView(APIView):
    permission_classes = [SessionRequise]

    @extend_schema(
        request=inline_serializer("AcceptationConditions", {"versionIds": serializers.ListField(child=serializers.UUIDField())}),
        responses={204: None},
    )
    def post(self, request):
        ids = serializers.ListField(child=serializers.UUIDField(), max_length=10).run_validation(request.data.get("versionIds"))
        actuelles = {v.id for v in conditions_actuelles()}
        if not set(ids) <= actuelles:
            raise ErreurApi("validation", "Version de conditions inconnue ou périmée.", status.HTTP_422_UNPROCESSABLE_ENTITY,
                            champs=[{"champ": "versionIds", "raison": "invalide"}])
        enregistrer_acceptations(request.user, ids)
        return Response(status=status.HTTP_204_NO_CONTENT)

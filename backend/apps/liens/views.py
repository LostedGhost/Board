"""Contrats 2.9 (gestion, 🔐) et 2.10 (consultation publique, 🔓 limitée par IP)."""

from django.conf import settings
from django.http import HttpResponseRedirect
from drf_spectacular.utils import OpenApiParameter, extend_schema, inline_serializer
from rest_framework import serializers, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.comptes.models import DureeConservation
from apps.elements.models import TypeElement
from apps.fichiers import stockage
from apps.fichiers.models import FournisseurStockage
from apps.liens import services
from apps.liens.models import LienPublic
from apps.moderation.models import MotifSignalement, Signalement
from commun.b64 import ChampBase64Url, encoder
from commun.erreurs import ErreurApi
from commun.limitation import ip_client, limiter


class LienCreationSerializer(serializers.Serializer):
    elementId = serializers.UUIDField()
    duree = serializers.ChoiceField(choices=DureeConservation.choices)
    protegeParMotDePasse = serializers.BooleanField(default=False)
    selDerivation = ChampBase64Url(taille_exacte=16, required=False, allow_null=True)
    cleElementEnveloppee = ChampBase64Url(taille_min=32, taille_max=512, required=False, allow_null=True)
    verificateurMotDePasse = ChampBase64Url(taille_exacte=32, required=False, allow_null=True)


class LienSerializer(serializers.ModelSerializer):
    elementId = serializers.UUIDField(source="element_id")
    typeElement = serializers.CharField(source="element.type")
    expireLe = serializers.DateTimeField(source="expire_le", allow_null=True)
    protegeParMotDePasse = serializers.BooleanField(source="protege_par_mot_de_passe")
    nbTelechargements = serializers.IntegerField(source="nb_telechargements")
    creeLe = serializers.DateTimeField(source="cree_le")
    statut = serializers.SerializerMethodField()

    class Meta:
        model = LienPublic
        fields = ["id", "elementId", "typeElement", "duree", "expireLe", "protegeParMotDePasse", "nbTelechargements", "creeLe", "statut"]
        read_only_fields = fields

    def get_statut(self, lien) -> str:
        return services.statut(lien)


# --- 2.9 Gestion ----------------------------------------------------------------------------


class LiensView(APIView):
    @extend_schema(responses=LienSerializer(many=True))
    def get(self, request):
        liens = LienPublic.objects.select_related("element").filter(compte=request.user).order_by("-cree_le")
        return Response(LienSerializer(liens, many=True).data)

    @extend_schema(
        request=LienCreationSerializer,
        responses={201: inline_serializer("LienCree", {"lien": LienSerializer(), "jeton": serializers.CharField()})},
    )
    def post(self, request):
        limiter("creation_liens", request.user.id, maximum=200, fenetre_s=3600)
        s = LienCreationSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        lien, jeton = services.creer(request.user, s.validated_data)
        reponse = Response({"lien": LienSerializer(lien).data, "jeton": jeton}, status=status.HTTP_201_CREATED)
        reponse["Cache-Control"] = "no-store"
        return reponse


def _lien_du_compte(request, lien_id):
    lien = LienPublic.objects.select_related("element").filter(id=lien_id, compte=request.user).first()
    if lien is None:
        raise ErreurApi("introuvable", "Lien introuvable.", status.HTTP_404_NOT_FOUND)
    return lien


class LienView(APIView):
    @extend_schema(
        request=inline_serializer("Prolongation", {"duree": serializers.ChoiceField(choices=DureeConservation.choices)}),
        responses=LienSerializer,
    )
    def patch(self, request, lien_id):
        lien = _lien_du_compte(request, lien_id)
        if lien.revoque_le or lien.desactive_par_admin_le:
            raise ErreurApi("deja_traite", "Ce lien n'est plus actif.", status.HTTP_409_CONFLICT)
        duree = serializers.ChoiceField(choices=DureeConservation.choices).run_validation(request.data.get("duree"))
        lien.duree = duree
        lien.expire_le = services.expiration(duree)
        lien.save(update_fields=["duree", "expire_le"])
        return Response(LienSerializer(lien).data)

    @extend_schema(responses={204: None})
    def delete(self, request, lien_id):
        lien = _lien_du_compte(request, lien_id)
        if lien.revoque_le is None:
            from django.utils import timezone

            lien.revoque_le = timezone.now()
            lien.save(update_fields=["revoque_le"])
        return Response(status=status.HTTP_204_NO_CONTENT)


# --- 2.10 Consultation publique -------------------------------------------------------------


def _representation_element(element):
    donnees = {
        "id": element.id,
        "type": element.type,
        "contenuChiffre": encoder(bytes(element.contenu_chiffre)) if element.contenu_chiffre else None,
        "modifieLe": element.modifie_le,
    }
    if element.type == TypeElement.LISTE_TACHES:
        donnees["taches"] = [
            {
                "id": t.id,
                "parentId": t.parent_id,
                "contenuChiffre": encoder(bytes(t.contenu_chiffre)) if t.contenu_chiffre else None,
                "modifieLe": t.modifie_le,
            }
            for t in services.taches_de_la_liste(element)
        ]
    if element.type == TypeElement.FICHIER:
        fichier = element.fichier
        donnees["tailleOctets"] = fichier.taille_octets
    return donnees


class VuePublique(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    def initial(self, request, *args, **kwargs):
        super().initial(request, *args, **kwargs)
        limiter("public_ip", ip_client(request), maximum=120, fenetre_s=60)


class PublicLienView(VuePublique):
    @extend_schema(responses=inline_serializer("LienPublicConsultation", {"type": serializers.CharField(), "protegeParMotDePasse": serializers.BooleanField()}))
    def get(self, request, jeton):
        lien = services.lien_actif(jeton)
        corps = {"type": lien.element.type, "protegeParMotDePasse": lien.protege_par_mot_de_passe}
        if lien.protege_par_mot_de_passe:
            corps["selDerivation"] = encoder(bytes(lien.sel_derivation))
        else:
            corps["element"] = _representation_element(lien.element)
        reponse = Response(corps)
        reponse["Cache-Control"] = "no-store"
        reponse["Referrer-Policy"] = "no-referrer"
        return reponse


class PublicDeverrouillerView(VuePublique):
    @extend_schema(request=inline_serializer("Deverrouillage", {"verificateurMotDePasse": serializers.CharField()}), responses={200: dict})
    def post(self, request, jeton):
        lien = services.lien_actif(jeton)
        if not lien.protege_par_mot_de_passe:
            raise ErreurApi("requete_invalide", "Ce lien n'est pas protégé.", status.HTTP_400_BAD_REQUEST)
        verificateur = ChampBase64Url(taille_exacte=32).run_validation(request.data.get("verificateurMotDePasse"))
        services.verifier_mot_de_passe(lien, verificateur, ip_client(request))
        corps = {
            "cleElementEnveloppee": encoder(bytes(lien.cle_element_enveloppee)),
            "element": _representation_element(lien.element),
        }
        if lien.element.type == TypeElement.FICHIER:
            corps["jetonTelechargement"] = services.jeton_telechargement(lien)
        reponse = Response(corps)
        reponse["Cache-Control"] = "no-store"
        return reponse


class PublicFichierView(VuePublique):
    @extend_schema(parameters=[OpenApiParameter("t", str, required=False)], responses={(200, "application/octet-stream"): bytes})
    def get(self, request, jeton):
        from apps.fichiers.views import reponse_flux

        lien = services.lien_actif(jeton)
        if lien.element.type != TypeElement.FICHIER:
            raise ErreurApi("introuvable", "Aucun fichier derrière ce lien.", status.HTTP_404_NOT_FOUND)
        if lien.protege_par_mot_de_passe:
            services.verifier_jeton_telechargement(lien, request.query_params.get("t"))
        fichier = lien.element.fichier
        if fichier.statut != "PRET":
            raise ErreurApi("deja_traite", "Le fichier n'est pas encore prêt.", status.HTTP_409_CONFLICT)
        plage = request.headers.get("Range", "")
        if not plage or plage.startswith("bytes=0-"):
            services.compter_telechargement(lien)
        if fichier.fournisseur == FournisseurStockage.LULUFILES and settings.LULUFILES_CORS_OUVERT:
            url, _ = stockage.LuluFiles().lien_signe(fichier.id_lulufiles)
            return HttpResponseRedirect(url)
        return reponse_flux(request, fichier)


class PublicSignalementView(VuePublique):
    @extend_schema(
        request=inline_serializer(
            "SignalementCreation",
            {"motif": serializers.ChoiceField(choices=MotifSignalement.choices), "commentaire": serializers.CharField(required=False)},
        ),
        responses={201: None},
    )
    def post(self, request, jeton):
        limiter("signalements_ip", ip_client(request), maximum=10, fenetre_s=3600)
        lien = services.lien_actif(jeton)
        motif = serializers.ChoiceField(choices=MotifSignalement.choices).run_validation(request.data.get("motif"))
        commentaire = serializers.CharField(max_length=2000, required=False, allow_blank=True, allow_null=True).run_validation(
            request.data.get("commentaire")
        )
        Signalement.objects.create(lien=lien, motif=motif, commentaire=commentaire or None)
        return Response(status=status.HTTP_201_CREATED)

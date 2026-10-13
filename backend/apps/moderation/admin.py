"""Modération dans l'interface d'administration (I28) : décisions sur des métadonnées, jamais sur un contenu."""

from django.contrib import admin, messages
from django.db import transaction
from django.utils import timezone

from apps.appareils.models import Session
from apps.comptes.models import StatutCompte
from apps.moderation.models import Signalement, StatutSignalement, Suspension
from commun.courriels import envoyer_courriel

MOTIF_SUSPENSION_DEFAUT = "Contenu signalé et confirmé par la modération."


def _informer_proprietaire(compte, sujet, corps):
    envoyer_courriel(compte.email, sujet, sujet.removeprefix("LuluBoard : "), [corps], fail_silently=True)


@admin.register(Signalement)
class SignalementAdmin(admin.ModelAdmin):
    list_display = ["cree_le", "motif", "statut", "lien", "proprietaire"]
    list_filter = ["statut", "motif"]
    readonly_fields = ["lien", "motif", "commentaire", "cree_le", "traite_le", "traite_par"]
    actions = ["classer_sans_suite", "desactiver_lien", "suspendre_compte"]

    @admin.display(description="Propriétaire du lien")
    def proprietaire(self, signalement):
        return signalement.lien.compte.email

    def _cloturer(self, request, signalement, statut):
        signalement.statut = statut
        signalement.traite_le = timezone.now()
        signalement.traite_par = request.user
        signalement.save(update_fields=["statut", "traite_le", "traite_par"])

    @admin.action(description="Classer sans suite")
    def classer_sans_suite(self, request, queryset):
        for s in queryset.filter(statut=StatutSignalement.OUVERT):
            self._cloturer(request, s, StatutSignalement.CLASSE_SANS_SUITE)

    @admin.action(description="Désactiver le lien")
    @transaction.atomic
    def desactiver_lien(self, request, queryset):
        for s in queryset.select_related("lien__compte"):
            s.lien.desactive_par_admin_le = timezone.now()
            s.lien.save(update_fields=["desactive_par_admin_le"])
            self._cloturer(request, s, StatutSignalement.LIEN_DESACTIVE)
            _informer_proprietaire(
                s.lien.compte,
                "LuluBoard : un de vos liens a été désactivé",
                "Un lien public que vous aviez créé a été désactivé à la suite d'un signalement.",
            )
        self.message_user(request, "Lien(s) désactivé(s).", messages.SUCCESS)

    @admin.action(description="Suspendre le compte propriétaire")
    @transaction.atomic
    def suspendre_compte(self, request, queryset):
        for s in queryset.select_related("lien__compte"):
            compte = s.lien.compte
            compte.statut = StatutCompte.SUSPENDU
            compte.save(update_fields=["statut"])
            Session.objects.filter(appareil__compte=compte).delete()
            Suspension.objects.create(compte=compte, motif=MOTIF_SUSPENSION_DEFAUT, decidee_par=request.user, signalement=s)
            s.lien.desactive_par_admin_le = timezone.now()
            s.lien.save(update_fields=["desactive_par_admin_le"])
            self._cloturer(request, s, StatutSignalement.COMPTE_SUSPENDU)
            _informer_proprietaire(
                compte,
                "LuluBoard : votre compte est suspendu",
                "Votre compte a été suspendu à la suite d'un signalement. Vous pouvez exporter vos données "
                "et contester cette décision en répondant à cet e-mail.",
            )
        self.message_user(request, "Compte(s) suspendu(s).", messages.SUCCESS)


@admin.register(Suspension)
class SuspensionAdmin(admin.ModelAdmin):
    list_display = ["compte", "debut_le", "levee_le", "decidee_par"]
    actions = ["lever"]

    @admin.action(description="Lever la suspension")
    def lever(self, request, queryset):
        for suspension in queryset.filter(levee_le__isnull=True).select_related("compte"):
            suspension.levee_le = timezone.now()
            suspension.save(update_fields=["levee_le"])
            suspension.compte.statut = StatutCompte.ACTIF
            suspension.compte.save(update_fields=["statut"])

"""Tâches planifiées des comptes : suppressions échues (A5), inactivité (I27), ménage des sessions."""

import logging
from datetime import timedelta

from celery import shared_task
from django.conf import settings
from django.core.mail import send_mail
from django.db import transaction
from django.utils import timezone

from apps.appareils.models import DemandeDeverrouillage, Session, StatutDemande
from apps.comptes.models import Compte, RoleCompte, StatutCompte

journal = logging.getLogger(__name__)

INACTIVITE = timedelta(days=365)  # I27 : 12 mois (validé)
DELAI_APRES_AVERTISSEMENT = timedelta(days=30)


def supprimer_definitivement(compte):
    """Efface les fichiers chez le fournisseur, puis toutes les données du compte (cascade)."""
    from apps.fichiers.models import Fichier
    from apps.fichiers.taches import effacer_du_stockage

    for fichier in Fichier.objects.filter(element__compte=compte):
        effacer_du_stockage.delay(
            {
                "fournisseur": fichier.fournisseur,
                "id_lulufiles": str(fichier.id_lulufiles) if fichier.id_lulufiles else None,
                "messages": list(fichier.morceaux.values_list("message_id", flat=True)),
                "chemin": fichier.chemin_temporaire,
            }
        )
    email = compte.email
    with transaction.atomic():
        compte.delete()
    send_mail(
        "LuluBoard : votre compte a été supprimé",
        "Votre compte et toutes vos données ont été définitivement supprimés.",
        settings.DEFAULT_FROM_EMAIL,
        [email],
        fail_silently=True,
    )


@shared_task(ignore_result=True)
def supprimer_comptes_echus():
    for compte in Compte.objects.filter(statut=StatutCompte.SUPPRESSION_PROGRAMMEE, suppression_prevue_le__lte=timezone.now())[:200]:
        supprimer_definitivement(compte)


@shared_task(ignore_result=True)
def gerer_inactivite():
    maintenant = timezone.now()
    actifs = Compte.objects.exclude(role=RoleCompte.ADMINISTRATEUR).exclude(statut=StatutCompte.EN_ATTENTE_VERIFICATION)
    for compte in actifs.filter(derniere_connexion_le__lt=maintenant - INACTIVITE, averti_inactivite_le__isnull=True)[:500]:
        send_mail(
            "LuluBoard : votre compte va être supprimé",
            "Vous ne vous êtes pas connecté depuis 12 mois. Sans connexion de votre part dans les 30 jours, "
            "votre compte et toutes vos données seront supprimés.",
            settings.DEFAULT_FROM_EMAIL,
            [compte.email],
            fail_silently=True,
        )
        compte.averti_inactivite_le = maintenant
        compte.save(update_fields=["averti_inactivite_le"])
    for compte in actifs.filter(
        derniere_connexion_le__lt=maintenant - INACTIVITE, averti_inactivite_le__lt=maintenant - DELAI_APRES_AVERTISSEMENT
    )[:200]:
        supprimer_definitivement(compte)
    # Comptes jamais vérifiés depuis 7 jours : supprimés (aucune donnée utile).
    Compte.objects.filter(statut=StatutCompte.EN_ATTENTE_VERIFICATION, cree_le__lt=maintenant - timedelta(days=7)).delete()


@shared_task(ignore_result=True)
def menage():
    maintenant = timezone.now()
    Session.objects.filter(expire_le__lt=maintenant).delete()
    DemandeDeverrouillage.objects.filter(statut=StatutDemande.EN_ATTENTE, expire_le__lt=maintenant).update(statut=StatutDemande.EXPIREE)
    from apps.envois.models import EnvoiAppareil, StatutEnvoi

    EnvoiAppareil.objects.filter(statut=StatutEnvoi.EN_ATTENTE, expire_le__lt=maintenant).update(statut=StatutEnvoi.EXPIRE, contenu_chiffre=None)

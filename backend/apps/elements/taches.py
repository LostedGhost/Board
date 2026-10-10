"""Tâches planifiées du Board : rappels (F3) et purges de rétention (B4, C3)."""

import logging
from datetime import timedelta

from celery import shared_task
from django.db import transaction
from django.utils import timezone

from apps.appareils.models import Appareil, StatutAppareil
from apps.comptes.models import Compte, DureeConservation, PreferencesCompte
from apps.elements.models import Element, Rappel, TypeElement, VersionPostIt
from apps.elements.recurrence import prochaine_apres
from apps.synchro.services import _Compteur
from commun import push
from commun.evenements import publier

journal = logging.getLogger(__name__)

DUREES = {
    DureeConservation.J90: timedelta(days=90),
    DureeConservation.J30: timedelta(days=30),
    DureeConservation.J7: timedelta(days=7),
    DureeConservation.H24: timedelta(hours=24),
    DureeConservation.H1: timedelta(hours=1),
    DureeConservation.MIN30: timedelta(minutes=30),
}


@shared_task(ignore_result=True)
def envoyer_rappels_dus():
    maintenant = timezone.now()
    dus = Rappel.objects.filter(actif=True, supprime_le__isnull=True, prochaine_echeance__lte=maintenant).order_by("compte_id")[:1000]
    for rappel in dus:
        with transaction.atomic():
            rappel = Rappel.objects.select_for_update().get(pk=rappel.pk)
            if not rappel.actif or rappel.prochaine_echeance > maintenant:
                continue
            appareils = Appareil.objects.select_related("preferences").filter(compte_id=rappel.compte_id, statut=StatutAppareil.ACTIF)
            langue = getattr(PreferencesCompte.objects.filter(compte_id=rappel.compte_id).first(), "langue", "fr")
            push.notifier(list(appareils), "RAPPELS", {"rappelId": rappel.id, "elementId": rappel.element_id}, langue)
            prochaine = (
                prochaine_apres(rappel.prochaine_echeance, rappel.recurrence, rappel.jours_semaine, rappel.fuseau_horaire, maintenant)
                if rappel.recurrence
                else None
            )
            compteur = _Compteur(Compte(id=rappel.compte_id))
            if prochaine:
                rappel.prochaine_echeance = prochaine
            else:
                rappel.actif = False
            rappel.modifie_le = maintenant
            rappel.version = compteur.suivante()
            rappel.save()
            compteur.enregistrer()
            publier(rappel.compte_id, "changements", versionCourante=rappel.version)


def _supprimer(compte_id, objets):
    """Suppression côté serveur, propagée aux appareils par la synchro."""
    if not objets:
        return
    maintenant = timezone.now()
    with transaction.atomic():
        compteur = _Compteur(Compte(id=compte_id))
        for objet in objets:
            objet.supprime_le = maintenant
            objet.modifie_le = maintenant
            objet.contenu_chiffre = None
            if isinstance(objet, Element):
                objet.cle_element_enveloppee = None
            objet.version = compteur.suivante()
            objet.save()
        compteur.enregistrer()
        publier(compte_id, "changements", versionCourante=compteur.ligne.version)


@shared_task(ignore_result=True)
def purger_retention():
    maintenant = timezone.now()
    for prefs in PreferencesCompte.objects.exclude(retention_presse_papier=DureeConservation.INFINIE, retention_versions=DureeConservation.INFINIE):
        if prefs.retention_presse_papier in DUREES:
            limite = maintenant - DUREES[prefs.retention_presse_papier]
            perimees = Element.objects.filter(
                compte_id=prefs.compte_id,
                type=TypeElement.PRESSE_PAPIER,
                supprime_le__isnull=True,
                epingle=False,
                epingle_acces_rapide=False,  # H8 : épingler en accès rapide protège aussi de la purge
                cree_le__lt=limite,
            )[:500]
            _supprimer(prefs.compte_id, list(perimees))
        if prefs.retention_versions in DUREES:
            limite = maintenant - DUREES[prefs.retention_versions]
            versions = VersionPostIt.objects.filter(compte_id=prefs.compte_id, supprime_le__isnull=True, cree_le__lt=limite)[:500]
            _supprimer(prefs.compte_id, list(versions))

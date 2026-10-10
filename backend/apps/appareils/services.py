"""Création d'appareils et ouverture de sessions (A2, A4, I11, I17, I26)."""

import hashlib
import secrets
from datetime import timedelta

from django.db import transaction
from django.utils import timezone
from rest_framework import status

from apps.appareils.models import (
    LIMITE_APPAREILS_ACTIFS,
    Appareil,
    EnveloppeCle,
    MethodeEnveloppe,
    PreferencesAppareil,
    Session,
    StatutAppareil,
)
from apps.comptes.models import StatutCompte
from commun.erreurs import ErreurApi

DUREE_SESSION = timedelta(days=30)  # I17 : 30 jours sans activité


def hacher_jeton(jeton):
    return hashlib.sha256(jeton.encode("ascii")).hexdigest()


def appareils_occupant_une_place(compte):
    return Appareil.objects.filter(compte=compte).exclude(statut=StatutAppareil.REVOQUE)


def verifier_limite_appareils(compte):
    """Au-delà de 3 appareils non révoqués : 409 avec la liste, pour en révoquer un (I11)."""
    existants = list(appareils_occupant_une_place(compte).order_by("ajoute_le"))
    if len(existants) >= LIMITE_APPAREILS_ACTIFS:
        from apps.appareils.serializers import AppareilSerializer

        raise ErreurApi(
            "limite_appareils",
            f"Vous avez déjà {LIMITE_APPAREILS_ACTIFS} appareils. Révoquez-en un pour continuer.",
            status.HTTP_409_CONFLICT,
            details={"appareils": AppareilSerializer(existants, many=True).data},
        )


def creer_appareil(compte, donnees, statut):
    appareil = Appareil.objects.create(
        compte=compte,
        nom=donnees["nom"],
        type=donnees["type"],
        plateforme=donnees["plateforme"],
        version_app=donnees["versionApp"],
        cle_publique=donnees["clePublique"],
        statut=statut,
    )
    PreferencesAppareil.objects.create(appareil=appareil)
    return appareil


def enregistrer_cles_initiales(compte, appareil, cles):
    """Clé maître enveloppée par la clé de récupération et par le premier appareil (ADR-004)."""
    EnveloppeCle.objects.create(
        compte=compte,
        methode=MethodeEnveloppe.CLE_RECUPERATION,
        cle_maitre_enveloppee=cles["enveloppeRecuperation"],
    )
    EnveloppeCle.objects.create(
        compte=compte,
        appareil=appareil,
        methode=MethodeEnveloppe.APPAREIL,
        cle_maitre_enveloppee=cles["enveloppeAppareil"],
    )
    compte.cle_publique_verification = cles["clePubliqueVerification"]
    compte.save(update_fields=["cle_publique_verification"])


def ouvrir_session(appareil):
    """Crée (ou remplace) la session de l'appareil. Le jeton n'est renvoyé qu'ici, en clair."""
    jeton = secrets.token_urlsafe(32)
    maintenant = timezone.now()
    Session.objects.update_or_create(
        appareil=appareil,
        defaults={
            "jeton_hash": hacher_jeton(jeton),
            "derniere_activite_le": maintenant,
            "expire_le": maintenant + DUREE_SESSION,
        },
    )
    return jeton, maintenant + DUREE_SESSION


def verifier_compte_utilisable(compte):
    if compte.statut == StatutCompte.SUSPENDU:
        raise ErreurApi("compte_suspendu", "Ce compte est suspendu.", status.HTTP_403_FORBIDDEN)


@transaction.atomic
def connecter_appareil(compte, donnees_appareil):
    """Connexion d'un compte existant sur un appareil (A2, I11, I26).

    `donnees_appareil` : soit un nouvel appareil (AppareilNouveau), soit {"appareilId": …}.
    """
    verifier_compte_utilisable(compte)
    maintenant = timezone.now()

    if compte.statut == StatutCompte.SUPPRESSION_PROGRAMMEE:  # I26 : se reconnecter annule la suppression
        compte.statut = StatutCompte.ACTIF
        compte.suppression_prevue_le = None

    appareil_id = donnees_appareil.get("appareilId")
    if appareil_id:
        appareil = Appareil.objects.filter(id=appareil_id, compte=compte).first()
        if appareil is None:
            raise ErreurApi("introuvable", "Appareil inconnu.", status.HTTP_404_NOT_FOUND)
        if appareil.statut == StatutAppareil.REVOQUE:
            raise ErreurApi("appareil_revoque", "Cet appareil a été révoqué.", status.HTTP_403_FORBIDDEN)
    else:
        verifier_limite_appareils(compte)
        appareil = creer_appareil(compte, donnees_appareil, StatutAppareil.EN_ATTENTE_DEVERROUILLAGE)

    appareil.derniere_activite_le = maintenant
    appareil.save(update_fields=["derniere_activite_le"])
    compte.derniere_connexion_le = maintenant
    compte.averti_inactivite_le = None
    compte.save(update_fields=["statut", "suppression_prevue_le", "derniere_connexion_le", "averti_inactivite_le"])
    jeton, expire_le = ouvrir_session(appareil)
    return appareil, jeton, expire_le

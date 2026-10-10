"""Contrat 2.3 — déverrouillage d'un appareil, révocation, clé de récupération (A4, I11, I12, I15).

Le serveur ne voit jamais la clé maître : il ne stocke que des enveloppes produites par les appareils.
"""

import hmac
import secrets
from datetime import timedelta

from django.core.cache import cache
from django.db import transaction
from django.utils import timezone
from nacl.exceptions import BadSignatureError
from nacl.signing import VerifyKey
from rest_framework import status

from apps.appareils.models import (
    Appareil,
    DemandeDeverrouillage,
    EnveloppeCle,
    MethodeEnveloppe,
    Session,
    StatutAppareil,
    StatutDemande,
)
from commun.b64 import decoder, encoder
from commun.erreurs import ErreurApi
from commun.evenements import publier

DUREE_DEMANDE = timedelta(minutes=10)
ESSAIS_CODE_MAX = 5
DUREE_DEFI_S = 300


def _introuvable():
    return ErreurApi("introuvable", "Ressource introuvable.", status.HTTP_404_NOT_FOUND)


# --- Révocation ---------------------------------------------------------------------------


@transaction.atomic
def revoquer(compte, appareil_id):
    appareil = Appareil.objects.select_for_update().filter(id=appareil_id, compte=compte).first()
    if appareil is None or appareil.statut == StatutAppareil.REVOQUE:
        raise _introuvable()
    maintenant = timezone.now()
    appareil.statut = StatutAppareil.REVOQUE
    appareil.revoque_le = maintenant
    appareil.jeton_push = None
    appareil.save(update_fields=["statut", "revoque_le", "jeton_push"])
    Session.objects.filter(appareil=appareil).delete()
    # L'enveloppe est vidée : même une fuite de la base ne la rendrait plus exploitable.
    EnveloppeCle.objects.filter(appareil=appareil, invalidee_le__isnull=True).update(
        invalidee_le=maintenant, cle_maitre_enveloppee=b""
    )
    DemandeDeverrouillage.objects.filter(appareil=appareil, statut=StatutDemande.EN_ATTENTE).update(
        statut=StatutDemande.EXPIREE
    )
    publier(compte.id, "appareil_revoque", appareilId=appareil.id)
    return appareil


# --- Enveloppe de l'appareil courant --------------------------------------------------------


def enveloppe_appareil(appareil):
    enveloppe = EnveloppeCle.objects.filter(appareil=appareil, invalidee_le__isnull=True).first()
    if enveloppe is None:
        raise _introuvable()
    return bytes(enveloppe.cle_maitre_enveloppee)


def _activer(appareil, cle_maitre_enveloppee):
    EnveloppeCle.objects.filter(appareil=appareil).delete()
    EnveloppeCle.objects.create(
        compte=appareil.compte,
        appareil=appareil,
        methode=MethodeEnveloppe.APPAREIL,
        cle_maitre_enveloppee=cle_maitre_enveloppee,
    )
    appareil.statut = StatutAppareil.ACTIF
    appareil.save(update_fields=["statut"])


# --- Déverrouillage par un autre appareil (I11) ----------------------------------------------


@transaction.atomic
def creer_demande(appareil):
    if appareil.statut != StatutAppareil.EN_ATTENTE_DEVERROUILLAGE:
        raise ErreurApi("deja_traite", "Cet appareil est déjà déverrouillé.", status.HTTP_409_CONFLICT)
    DemandeDeverrouillage.objects.filter(appareil=appareil, statut=StatutDemande.EN_ATTENTE).update(
        statut=StatutDemande.EXPIREE
    )
    demande = DemandeDeverrouillage.objects.create(
        appareil=appareil,
        code_affiche=f"{secrets.randbelow(1_000_000):06d}",
        expire_le=timezone.now() + DUREE_DEMANDE,
    )
    publier(appareil.compte_id, "deverrouillage_demande", demandeId=demande.id)
    return demande


def demandes_en_attente(compte):
    return (
        DemandeDeverrouillage.objects.select_related("appareil")
        .filter(
            appareil__compte=compte,
            appareil__statut=StatutAppareil.EN_ATTENTE_DEVERROUILLAGE,
            statut=StatutDemande.EN_ATTENTE,
            expire_le__gt=timezone.now(),
        )
        .order_by("-expire_le")
    )


def _demande_traitable(compte, demande_id, approbateur):
    demande = (
        DemandeDeverrouillage.objects.select_for_update()
        .select_related("appareil")
        .filter(id=demande_id, appareil__compte=compte)
        .first()
    )
    if demande is None or demande.appareil_id == approbateur.id:
        raise _introuvable()
    if demande.statut != StatutDemande.EN_ATTENTE:
        raise ErreurApi("deja_traite", "Cette demande a déjà été traitée.", status.HTTP_409_CONFLICT)
    if demande.expire_le <= timezone.now():
        demande.statut = StatutDemande.EXPIREE
        demande.save(update_fields=["statut"])
        raise ErreurApi("code_expire", "Cette demande a expiré.", status.HTTP_410_GONE)
    return demande


def approuver(compte, demande_id, approbateur, code, cle_maitre_enveloppee):
    """Le code affiché sur le nouvel appareil prouve qu'on l'a sous les yeux (5 essais, puis refus)."""
    erreur = None
    with transaction.atomic():
        demande = _demande_traitable(compte, demande_id, approbateur)
        cle_essais = f"deverrouillage_essais:{demande.id}"
        if not hmac.compare_digest(demande.code_affiche, str(code)):
            essais = cache.get(cle_essais, 0) + 1
            cache.set(cle_essais, essais, int(DUREE_DEMANDE.total_seconds()))
            if essais >= ESSAIS_CODE_MAX:
                demande.statut = StatutDemande.REFUSEE
                demande.save(update_fields=["statut"])
                publier(compte.id, "deverrouillage_resolu", demandeId=demande.id, statut=StatutDemande.REFUSEE)
            erreur = ErreurApi(
                "validation",
                "Code incorrect.",
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                champs=[{"champ": "codeAffiche", "raison": "incorrect"}],
                details={"essaisRestants": max(0, ESSAIS_CODE_MAX - essais)},
            )
        else:
            _activer(demande.appareil, cle_maitre_enveloppee)
            demande.statut = StatutDemande.APPROUVEE
            demande.approuvee_par = approbateur
            demande.save(update_fields=["statut", "approuvee_par"])
            publier(compte.id, "deverrouillage_resolu", demandeId=demande.id, statut=StatutDemande.APPROUVEE)
    if erreur is not None:
        raise erreur
    return demande


@transaction.atomic
def refuser(compte, demande_id, approbateur):
    """Refuser = « ce n'est pas moi » : l'appareil demandeur est révoqué (décision D7)."""
    demande = _demande_traitable(compte, demande_id, approbateur)
    demande.statut = StatutDemande.REFUSEE
    demande.save(update_fields=["statut"])
    publier(compte.id, "deverrouillage_resolu", demandeId=demande.id, statut=StatutDemande.REFUSEE)
    revoquer(compte, demande.appareil_id)
    return demande


# --- Déverrouillage par la clé de récupération --------------------------------------------


def _cle_defi(appareil):
    return f"defi_recuperation:{appareil.id}"


def enveloppe_recuperation(compte, appareil):
    enveloppe = EnveloppeCle.objects.filter(
        compte=compte, methode=MethodeEnveloppe.CLE_RECUPERATION, invalidee_le__isnull=True
    ).first()
    if enveloppe is None:
        raise _introuvable()
    defi = secrets.token_bytes(32)
    cache.set(_cle_defi(appareil), encoder(defi), DUREE_DEFI_S)
    return bytes(enveloppe.cle_maitre_enveloppee), defi


def deverrouiller_par_recuperation(appareil, cle_maitre_enveloppee, signature):
    """Le client signe le défi avec la clé Ed25519 dérivée de la clé maître : preuve qu'il la possède."""
    compte = appareil.compte
    if appareil.statut != StatutAppareil.EN_ATTENTE_DEVERROUILLAGE:
        raise ErreurApi("deja_traite", "Cet appareil est déjà déverrouillé.", status.HTTP_409_CONFLICT)
    defi = cache.get(_cle_defi(appareil))
    cache.delete(_cle_defi(appareil))  # un défi ne sert qu'une fois
    if not defi or not compte.cle_publique_verification:
        raise ErreurApi("code_expire", "Défi expiré. Recommencez.", status.HTTP_410_GONE)
    try:
        VerifyKey(decoder(compte.cle_publique_verification)).verify(decoder(defi), signature)
    except (BadSignatureError, ValueError):
        raise ErreurApi(
            "validation",
            "Clé de récupération incorrecte.",
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            champs=[{"champ": "signatureDefi", "raison": "invalide"}],
        )
    with transaction.atomic():
        appareil = Appareil.objects.select_for_update().get(id=appareil.id)
        _activer(appareil, cle_maitre_enveloppee)
        DemandeDeverrouillage.objects.filter(appareil=appareil, statut=StatutDemande.EN_ATTENTE).update(
            statut=StatutDemande.EXPIREE
        )
    return appareil


@transaction.atomic
def regenerer_cle_recuperation(compte, cle_maitre_enveloppee):
    """I15 : l'ancienne enveloppe est invalidée ET vidée, la nouvelle la remplace."""
    maintenant = timezone.now()
    EnveloppeCle.objects.filter(
        compte=compte, methode=MethodeEnveloppe.CLE_RECUPERATION, invalidee_le__isnull=True
    ).update(invalidee_le=maintenant, cle_maitre_enveloppee=b"")
    EnveloppeCle.objects.create(
        compte=compte, methode=MethodeEnveloppe.CLE_RECUPERATION, cle_maitre_enveloppee=cle_maitre_enveloppee
    )
    compte.cle_recuperation_confirmee_le = None  # la nouvelle clé doit être sauvegardée à son tour
    compte.save(update_fields=["cle_recuperation_confirmee_le"])

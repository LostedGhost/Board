"""Codes de vérification à 6 chiffres (A1, A3, I14) : valables 15 min, 5 essais, stockés hachés."""

import hashlib
import hmac
import secrets
from datetime import timedelta

from django.conf import settings
from django.db import transaction
from django.utils import timezone
from rest_framework import status

from apps.comptes.models import CodeVerification
from commun.erreurs import ErreurApi

DUREE_VALIDITE = timedelta(minutes=15)
ESSAIS_MAX = 5


def _hacher(code):
    return hmac.new(settings.SECRET_KEY.encode(), code.encode(), hashlib.sha256).hexdigest()


def emettre_code(compte, type_code, nouvel_email=None):
    """Invalide les codes précédents du même type et renvoie un nouveau code en clair (à envoyer par e-mail)."""
    maintenant = timezone.now()
    CodeVerification.objects.filter(compte=compte, type=type_code, utilise_le__isnull=True).update(utilise_le=maintenant)
    code = f"{secrets.randbelow(1_000_000):06d}"
    CodeVerification.objects.create(
        compte=compte,
        type=type_code,
        code_hash=_hacher(code),
        nouvel_email=nouvel_email,
        expire_le=maintenant + DUREE_VALIDITE,
    )
    return code


def erreur_code_invalide(essais_restants=None):
    details = {"essaisRestants": essais_restants} if essais_restants is not None else None
    return ErreurApi(
        "validation",
        "Code incorrect.",
        status.HTTP_422_UNPROCESSABLE_ENTITY,
        champs=[{"champ": "code", "raison": "incorrect"}],
        details=details,
    )


def consommer_code(compte, type_code, code):
    """Vérifie le code ; le consomme s'il est bon. Lève 410 s'il a expiré, 422 s'il est faux.

    Doit être appelée HORS de toute transaction englobante : l'essai raté doit être
    enregistré même si l'appel se termine par une erreur (sinon la limite de 5 essais ne joue jamais).
    """
    maintenant = timezone.now()
    erreur = None
    with transaction.atomic():
        actif = (
            CodeVerification.objects.select_for_update()
            .filter(compte=compte, type=type_code, utilise_le__isnull=True)
            .order_by("-expire_le")
            .first()
        )
        if actif is None:
            erreur = erreur_code_invalide(0)
        elif actif.expire_le <= maintenant or actif.tentatives >= ESSAIS_MAX:
            erreur = ErreurApi("code_expire", "Ce code a expiré. Demandez-en un nouveau.", status.HTTP_410_GONE)
        elif not hmac.compare_digest(actif.code_hash, _hacher(str(code))):
            actif.tentatives += 1
            actif.save(update_fields=["tentatives"])
            erreur = erreur_code_invalide(ESSAIS_MAX - actif.tentatives)
        else:
            actif.utilise_le = maintenant
            actif.save(update_fields=["utilise_le"])
    if erreur is not None:
        raise erreur
    return actif

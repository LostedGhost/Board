"""Format d'erreur unique de l'API (contrat, section 1).

{ "erreur": { "code", "message", "champs"?, "requestId" } }
Le client se fie à `code`, jamais à `message`.
"""

import logging

from django.http import Http404
from rest_framework import exceptions, status
from rest_framework.response import Response
from rest_framework.views import exception_handler

from commun.middleware import request_id_courant

journal = logging.getLogger(__name__)


class ErreurApi(exceptions.APIException):
    """Erreur métier : un code stable, un statut HTTP, un message lisible."""

    def __init__(self, code, message, statut=status.HTTP_400_BAD_REQUEST, champs=None, details=None):
        super().__init__(detail=message)
        self.code_erreur = code
        self.status_code = statut
        self.champs = champs
        self.details = details


def corps_erreur(code, message, champs=None, details=None):
    erreur = {"code": code, "message": message, "requestId": request_id_courant()}
    if champs:
        erreur["champs"] = champs
    if details is not None:
        erreur["details"] = details
    return {"erreur": erreur}


def _champs_validation(detail, prefixe=""):
    champs = []
    if isinstance(detail, dict):
        for cle, valeur in detail.items():
            nom = f"{prefixe}.{cle}" if prefixe else str(cle)
            champs.extend(_champs_validation(valeur, nom))
    elif isinstance(detail, list):
        for item in detail:
            if isinstance(item, (dict, list)):
                champs.extend(_champs_validation(item, prefixe))
            else:
                champs.append({"champ": prefixe or "corps", "raison": getattr(item, "code", "invalide")})
    else:
        champs.append({"champ": prefixe or "corps", "raison": getattr(detail, "code", "invalide")})
    return champs


def gestionnaire_exceptions(exc, context):
    if isinstance(exc, ErreurApi):
        return Response(corps_erreur(exc.code_erreur, str(exc.detail), exc.champs, exc.details), status=exc.status_code)

    if isinstance(exc, Http404):
        exc = exceptions.NotFound()

    response = exception_handler(exc, context)
    if response is None:
        journal.exception("Erreur non gérée")
        return Response(
            corps_erreur("service_indisponible", "Erreur interne. Réessayez plus tard."),
            status=status.HTTP_500_INTERNAL_SERVER_ERROR,
        )

    if isinstance(exc, exceptions.ValidationError):
        response.data = corps_erreur("validation", "Données invalides.", _champs_validation(exc.detail))
        response.status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    elif isinstance(exc, (exceptions.NotAuthenticated, exceptions.AuthenticationFailed)):
        response.data = corps_erreur("non_authentifie", "Authentification requise.")
        response.status_code = status.HTTP_401_UNAUTHORIZED
    elif isinstance(exc, exceptions.PermissionDenied):
        response.data = corps_erreur("interdit", "Action non autorisée.")
    elif isinstance(exc, exceptions.NotFound):
        response.data = corps_erreur("introuvable", "Ressource introuvable.")
    elif isinstance(exc, exceptions.Throttled):
        response.data = corps_erreur("trop_de_requetes", "Trop de requêtes. Réessayez plus tard.")
    elif isinstance(exc, exceptions.ParseError):
        response.data = corps_erreur("requete_invalide", "Requête mal formée.")
    else:
        response.data = corps_erreur("requete_invalide", str(getattr(exc, "detail", "Requête invalide.")))
    return response

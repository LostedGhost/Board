"""Niveaux d'accès du contrat : 🔑 session requise, 🔐 session + appareil déverrouillé.

Une vue 🔐 peut se dispenser de certaines vérifications avec l'attribut
`dispenses = {"cle_recuperation", "conditions"}`.
"""

from rest_framework import permissions, status

from apps.appareils.models import StatutAppareil
from commun.erreurs import ErreurApi


class SessionRequise(permissions.BasePermission):
    """🔑"""

    def has_permission(self, request, view):
        if request.user is None or request.auth is None:
            raise ErreurApi("non_authentifie", "Authentification requise.", status.HTTP_401_UNAUTHORIZED)
        return True


class AppareilDeverrouille(SessionRequise):
    """🔐 : appareil ACTIF, clé de récupération confirmée si obligatoire, conditions acceptées."""

    def has_permission(self, request, view):
        super().has_permission(request, view)
        dispenses = getattr(view, "dispenses", set())

        if request.appareil.statut != StatutAppareil.ACTIF:
            raise ErreurApi(
                "appareil_non_deverrouille",
                "Déverrouillez cet appareil depuis un autre appareil ou avec votre clé de récupération.",
                status.HTTP_403_FORBIDDEN,
            )
        if "cle_recuperation" not in dispenses and request.user.cle_recuperation_obligatoire:
            raise ErreurApi(
                "cle_recuperation_non_confirmee",
                "Confirmez d'abord que vous avez sauvegardé votre clé de récupération.",
                status.HTTP_403_FORBIDDEN,
            )
        if "conditions" not in dispenses:
            from apps.conformite.services import conditions_a_accepter

            if conditions_a_accepter(request.user):
                raise ErreurApi(
                    "conditions_a_accepter",
                    "Acceptez les nouvelles conditions d'utilisation pour continuer.",
                    status.HTTP_403_FORBIDDEN,
                )
        return True

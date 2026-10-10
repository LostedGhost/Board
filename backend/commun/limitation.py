"""Limitation de fréquence simple, adossée au cache (Redis en production).

Utilisée pour : bourrage d'identifiants (A2), renvoi de codes, routes publiques (I19, I22).
"""

from django.core.cache import cache
from rest_framework import status

from commun.erreurs import ErreurApi


def _cle(espace, identifiant):
    return f"limite:{espace}:{identifiant}"


def compter(espace, identifiant, fenetre_s):
    """Incrémente le compteur et renvoie sa valeur dans la fenêtre courante."""
    cle = _cle(espace, identifiant)
    if cache.add(cle, 1, fenetre_s):
        return 1
    try:
        return cache.incr(cle)
    except ValueError:
        cache.set(cle, 1, fenetre_s)
        return 1


def valeur(espace, identifiant):
    return cache.get(_cle(espace, identifiant), 0)


def reinitialiser(espace, identifiant):
    cache.delete(_cle(espace, identifiant))


def limiter(espace, identifiant, maximum, fenetre_s):
    """Lève 429 si `maximum` est dépassé dans la fenêtre."""
    if compter(espace, identifiant, fenetre_s) > maximum:
        raise ErreurApi(
            "trop_de_requetes",
            "Trop de requêtes. Réessayez plus tard.",
            status.HTTP_429_TOO_MANY_REQUESTS,
        )


def ip_client(request):
    # Derrière le proxy du PaaS, l'IP réelle sera lue depuis l'en-tête de confiance configuré à l'étape 8.
    return request.META.get("REMOTE_ADDR", "inconnue")

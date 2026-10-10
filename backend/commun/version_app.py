"""Refus des apps trop anciennes (I10) : en-tête X-App-Version → 426 mise_a_jour_requise.

Un client sans en-tête (page publique d'un lien, outil de test) n'est pas bloqué.
"""

import re

from django.conf import settings
from django.http import JsonResponse

from commun.erreurs import corps_erreur

_NUMEROS = re.compile(r"^(\d+)\.(\d+)\.(\d+)")


def _tuple(version):
    trouve = _NUMEROS.match(version or "")
    return tuple(int(x) for x in trouve.groups()) if trouve else None


class VersionAppMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        recue = request.headers.get("X-App-Version")
        if recue and request.path.startswith("/api/") and not request.path.startswith("/api/v1/health"):
            version, minimum = _tuple(recue), _tuple(settings.MIN_APP_VERSION)
            if version is not None and minimum is not None and version < minimum:
                return JsonResponse(
                    corps_erreur("mise_a_jour_requise", "Mettez à jour l'application pour continuer."),
                    status=426,
                )
        return self.get_response(request)

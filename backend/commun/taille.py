"""Refus précoce des corps trop gros (413), avant toute lecture.

DRF lit le flux directement : DATA_UPLOAD_MAX_MEMORY_SIZE ne le protège pas.
"""

from django.http import JsonResponse

from commun.erreurs import corps_erreur

TAILLE_MAX_JSON = 12 * 1024 * 1024  # un élément de 10 Mo chiffré + enveloppe JSON
TAILLE_MAX_FICHIER = 101 * 1024 * 1024  # 100 Mo chiffrés + métadonnées (E1)


class TailleRequeteMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        try:
            longueur = int(request.META.get("CONTENT_LENGTH") or 0)
        except ValueError:
            longueur = 0
        maximum = TAILLE_MAX_FICHIER if request.path.startswith("/api/v1/fichiers") else TAILLE_MAX_JSON
        if longueur > maximum:
            return JsonResponse(corps_erreur("fichier_trop_volumineux", "Requête trop volumineuse."), status=413)
        return self.get_response(request)

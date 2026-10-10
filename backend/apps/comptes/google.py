"""Vérification d'un jeton d'identité Google (A1b, I16)."""

from django.conf import settings
from rest_framework import status

from commun.erreurs import ErreurApi


def verifier_id_token(id_token):
    """Renvoie {sujet, email, nom} si le jeton est valide et destiné à l'une de nos applications."""
    from google.auth.transport import requests as transport
    from google.oauth2 import id_token as google_id_token

    if not settings.GOOGLE_CLIENT_IDS:
        raise ErreurApi("service_indisponible", "Connexion Google non configurée.", status.HTTP_503_SERVICE_UNAVAILABLE)
    try:
        infos = google_id_token.verify_oauth2_token(id_token, transport.Request(), audience=None)
    except ValueError:
        raise ErreurApi("non_authentifie", "Jeton Google invalide.", status.HTTP_401_UNAUTHORIZED)

    if infos.get("aud") not in settings.GOOGLE_CLIENT_IDS:
        raise ErreurApi("non_authentifie", "Jeton Google invalide.", status.HTTP_401_UNAUTHORIZED)
    if infos.get("iss") not in ("accounts.google.com", "https://accounts.google.com"):
        raise ErreurApi("non_authentifie", "Jeton Google invalide.", status.HTTP_401_UNAUTHORIZED)
    if not infos.get("email_verified"):
        raise ErreurApi("non_authentifie", "Adresse Google non vérifiée.", status.HTTP_401_UNAUTHORIZED)

    return {
        "sujet": infos["sub"],
        "email": infos["email"],
        "nom": (infos.get("name") or infos["email"].split("@")[0])[:100],
    }

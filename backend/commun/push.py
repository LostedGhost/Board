"""Notifications push via Firebase Cloud Messaging, API HTTP v1 (gratuite, décision D29).

Le texte d'une notification ne contient JAMAIS de contenu utilisateur (chiffrement de bout en bout) :
seulement un message générique et des identifiants.
Sans configuration (FCM_PROJECT_ID + FCM_FICHIER_COMPTE_SERVICE), l'envoi est ignoré (journalisé).
"""

import logging

import httpx
from django.conf import settings

journal = logging.getLogger(__name__)

_MESSAGES = {
    "RAPPELS": {"fr": "Vous avez un rappel", "en": "You have a reminder"},
    "ENVOIS_APPAREILS": {"fr": "Nouvel élément reçu", "en": "New item received"},
    "NOUVEL_APPAREIL": {"fr": "Un nouvel appareil demande l'accès", "en": "A new device is requesting access"},
    "SECURITE": {"fr": "Alerte de sécurité LuluBoard", "en": "LuluBoard security alert"},
}


def _jeton_acces():
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    identifiants = service_account.Credentials.from_service_account_file(
        settings.FCM_FICHIER_COMPTE_SERVICE, scopes=["https://www.googleapis.com/auth/firebase.messaging"]
    )
    identifiants.refresh(Request())
    return identifiants.token


def configure():
    return bool(settings.FCM_PROJECT_ID and settings.FCM_FICHIER_COMPTE_SERVICE)


def notifier(appareils, categorie, donnees=None, langue="fr"):
    """Envoie à chaque appareil qui a un jeton et qui accepte cette catégorie. Ne lève jamais d'exception."""
    cibles = [
        a for a in appareils
        if a.jeton_push and categorie in (getattr(getattr(a, "preferences", None), "notifications_actives", None) or [categorie])
    ]
    if not cibles:
        return 0
    if not configure():
        journal.info("Push %s ignoré (FCM non configuré) pour %d appareil(s)", categorie, len(cibles))
        return 0
    try:
        jeton = _jeton_acces()
    except Exception:
        journal.warning("Authentification FCM impossible")
        return 0
    titre = _MESSAGES[categorie][langue if langue in ("fr", "en") else "fr"]
    envoyes = 0
    with httpx.Client(timeout=10) as client:
        for appareil in cibles:
            message = {
                "message": {
                    "token": appareil.jeton_push,
                    "notification": {"title": "LuluBoard", "body": titre},
                    "data": {"categorie": categorie, **{k: str(v) for k, v in (donnees or {}).items()}},
                }
            }
            try:
                r = client.post(
                    f"https://fcm.googleapis.com/v1/projects/{settings.FCM_PROJECT_ID}/messages:send",
                    headers={"Authorization": f"Bearer {jeton}"},
                    json=message,
                )
                if r.status_code == 200:
                    envoyes += 1
                elif r.status_code in (400, 404):  # jeton périmé : on l'oublie
                    type(appareil).objects.filter(pk=appareil.pk).update(jeton_push=None)
            except httpx.HTTPError:
                journal.warning("Envoi push impossible")
    return envoyes

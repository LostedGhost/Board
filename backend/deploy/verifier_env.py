"""Contrôle des variables d'environnement au démarrage sur Render (noms seulement, jamais les valeurs).

Affiché dans les logs du service : variables attendues absentes, et variables obsolètes encore définies.
"""

import os

ATTENDUES = [
    "PYTHON_VERSION",
    "DJANGO_SECRET_KEY",
    "DJANGO_DEBUG",
    "DATABASE_URL",
    "REDIS_URL",
    "CELERY_TASK_ALWAYS_EAGER",
    "MIN_APP_VERSION",
    "CORS_ALLOWED_ORIGINS",
    "DJANGO_SUPERUSER_EMAIL",
    "DJANGO_SUPERUSER_PASSWORD",
    "DJANGO_SUPERUSER_NOM_AFFICHAGE",
    "FILES_USE_DIRECT_TELEGRAM",
    "TELEGRAM_BOT_TOKEN",
    "TELEGRAM_CHANNEL_ID",
    "BREVO_API_KEY",
    "DEFAULT_FROM_EMAIL",
    "SUPPORT_EMAIL",
]
OBSOLETES = ["EMAIL_BACKEND", "EMAIL_HOST", "EMAIL_PORT", "EMAIL_USE_TLS", "EMAIL_HOST_USER", "EMAIL_HOST_PASSWORD"]

manquantes = [n for n in ATTENDUES if not os.environ.get(n)]
en_trop = [n for n in OBSOLETES if n in os.environ]

print("[variables] attendues présentes :", f"{len(ATTENDUES) - len(manquantes)}/{len(ATTENDUES)}")
print("[variables] manquantes :", ", ".join(manquantes) or "aucune")
print("[variables] obsolètes encore définies (à supprimer) :", ", ".join(en_trop) or "aucune")
if os.environ.get("DEFAULT_FROM_EMAIL"):
    print("[variables] expéditeur :", os.environ["DEFAULT_FROM_EMAIL"])

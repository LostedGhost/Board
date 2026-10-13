"""Réglages Django de LuluBoard. Toute valeur sensible vient de l'environnement (.env en local)."""

import os
from pathlib import Path
from urllib.parse import parse_qsl, unquote, urlparse

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")


def env(nom, defaut=None, obligatoire=False):
    valeur = os.environ.get(nom, defaut)
    if obligatoire and not valeur:
        raise RuntimeError(f"Variable d'environnement manquante : {nom}")
    return valeur


def env_bool(nom, defaut=False):
    return str(env(nom, str(defaut))).strip().lower() in {"1", "true", "yes", "oui"}


SECRET_KEY = env("DJANGO_SECRET_KEY", obligatoire=True)
DEBUG = env_bool("DJANGO_DEBUG")
ALLOWED_HOSTS = [h.strip() for h in env("DJANGO_ALLOWED_HOSTS", "localhost").split(",") if h.strip()]
# Render fournit le nom d'hôte public du service : il est accepté sans configuration supplémentaire.
RENDER_EXTERNAL_HOSTNAME = env("RENDER_EXTERNAL_HOSTNAME", "")
if RENDER_EXTERNAL_HOSTNAME:
    ALLOWED_HOSTS.append(RENDER_EXTERNAL_HOSTNAME)

VERSION_API = "0.1.0"
MIN_APP_VERSION = env("MIN_APP_VERSION", "0.1.0")

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "corsheaders",
    "rest_framework",
    "drf_spectacular",
    "channels",
    "commun",
    "apps.sante",
    "apps.comptes",
    "apps.appareils",
    "apps.conformite",
    "apps.elements",
    "apps.synchro",
    "apps.fichiers",
    "apps.envois",
    "apps.liens",
    "apps.moderation",
]

AUTH_USER_MODEL = "comptes.Compte"

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "commun.middleware.RequestIdMiddleware",
    "commun.version_app.VersionAppMiddleware",
    "commun.taille.TailleRequeteMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
ASGI_APPLICATION = "config.asgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": env("DATABASE_NAME", "luluboard"),
        "USER": env("DATABASE_USER", "luluboard"),
        "PASSWORD": env("DATABASE_PASSWORD", ""),
        "HOST": env("DATABASE_HOST", "localhost"),
        "PORT": env("DATABASE_PORT", "5432"),
        "CONN_MAX_AGE": 60,
        "OPTIONS": {"connect_timeout": 5},
    }
}

# En production, une URL unique (Render, Neon…) remplace les DATABASE_* séparées.
# Les paramètres de requête (ex. sslmode=require chez Neon) sont transmis à psycopg.
DATABASE_URL = env("DATABASE_URL", "")
if DATABASE_URL:
    url = urlparse(DATABASE_URL)
    DATABASES["default"].update(
        {
            "NAME": unquote(url.path.lstrip("/")),
            "USER": unquote(url.username or ""),
            "PASSWORD": unquote(url.password or ""),
            "HOST": url.hostname or "",
            "PORT": str(url.port or 5432),
        }
    )
    DATABASES["default"]["OPTIONS"].update(dict(parse_qsl(url.query)))

REDIS_URL = env("REDIS_URL", "redis://localhost:6379/0")

# Origines autorisées à appeler l'API depuis un navigateur (app web Flutter, D50).
# Les apps natives et la page publique /l/ (même origine) ne sont pas concernées.
CORS_ALLOWED_ORIGINS = [o.strip() for o in env("CORS_ALLOWED_ORIGINS", "http://localhost:5000,http://127.0.0.1:5000").split(",") if o.strip()]
CORS_URLS_REGEX = r"^/api/.*$"
CORS_ALLOW_HEADERS = ["accept", "authorization", "content-type", "x-app-version", "x-request-id", "range"]
CORS_EXPOSE_HEADERS = ["x-request-id", "content-range", "content-length", "accept-ranges"]

CHANNEL_LAYERS = {
    "default": {
        "BACKEND": "channels_redis.core.RedisChannelLayer",
        "CONFIG": {"hosts": [REDIS_URL]},
    }
}

CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.redis.RedisCache",
        "LOCATION": REDIS_URL,
    }
}

# Stockage des fichiers (ADR-006)
FILES_USE_DIRECT_TELEGRAM = env_bool("FILES_USE_DIRECT_TELEGRAM", True)
LULUFILES_BASE_URL = env("LULUFILES_BASE_URL", "https://lulufiles-api.onrender.com")
LULUFILES_API_KEY = env("LULUFILES_API_KEY", "")
TELEGRAM_BOT_TOKEN = env("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHANNEL_ID = env("TELEGRAM_CHANNEL_ID", "")
# Tant que LuluFiles n'autorise pas l'origine LuluBoard en CORS, les fichiers passent par notre serveur (D23).
LULUFILES_CORS_OUVERT = env_bool("LULUFILES_CORS_OUVERT", False)
FICHIERS_DOSSIER_TEMPORAIRE = env("FICHIERS_DOSSIER_TEMPORAIRE", "")
FILE_UPLOAD_MAX_MEMORY_SIZE = 5 * 1024 * 1024  # au-delà, les envois passent par un fichier temporaire

# Celery : en local, exécution immédiate dans le processus web (pas de worker à lancer, D22).
CELERY_BROKER_URL = REDIS_URL
CELERY_TASK_ALWAYS_EAGER = env_bool("CELERY_TASK_ALWAYS_EAGER", False)
CELERY_TASK_EAGER_PROPAGATES = True
CELERY_TASK_ACKS_LATE = True
CELERY_WORKER_PREFETCH_MULTIPLIER = 1
CELERY_TIMEZONE = "UTC"
CELERY_BEAT_SCHEDULE = {
    "rappels": {"task": "apps.elements.taches.envoyer_rappels_dus", "schedule": 60.0},
    "retention": {"task": "apps.elements.taches.purger_retention", "schedule": 300.0},
    "suppressions": {"task": "apps.comptes.taches.supprimer_comptes_echus", "schedule": 3600.0},
    "inactivite": {"task": "apps.comptes.taches.gerer_inactivite", "schedule": 86400.0},
    "menage": {"task": "apps.comptes.taches.menage", "schedule": 3600.0},
}

# E-mails : console en local ; fournisseur gratuit à choisir à l'étape 8.
EMAIL_BACKEND = env("EMAIL_BACKEND", "django.core.mail.backends.console.EmailBackend")
DEFAULT_FROM_EMAIL = env("DEFAULT_FROM_EMAIL", "LuluBoard <no-reply@luluboard.local>")
EMAIL_HOST = env("EMAIL_HOST", "")
EMAIL_PORT = int(env("EMAIL_PORT", "587"))
EMAIL_HOST_USER = env("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = env("EMAIL_HOST_PASSWORD", "")
EMAIL_USE_TLS = env_bool("EMAIL_USE_TLS", True)
EMAIL_FILE_PATH = env("EMAIL_FILE_PATH", "")  # backend « filebased » (scénario de bout en bout)

# Connexion Google (A1b) : identifiants OAuth des apps web, Android et iOS, séparés par des virgules.
# Notifications push (FCM, HTTP v1) : identifiant du projet Firebase + fichier JSON du compte de service.
FCM_PROJECT_ID = env("FCM_PROJECT_ID", "")
FCM_FICHIER_COMPTE_SERVICE = env("FCM_FICHIER_COMPTE_SERVICE", "")
# Adresse qui reçoit les demandes de support (I22).
SUPPORT_EMAIL = env("SUPPORT_EMAIL", "")

GOOGLE_CLIENT_IDS = [c.strip() for c in env("GOOGLE_CLIENT_IDS", "").split(",") if c.strip()]

PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.Argon2PasswordHasher",
]

REST_FRAMEWORK = {
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "DEFAULT_PARSER_CLASSES": ["rest_framework.parsers.JSONParser"],
    "DEFAULT_AUTHENTICATION_CLASSES": ["apps.appareils.authentification.AuthentificationSession"],
    # Par défaut, tout est 🔐 (le plus strict) ; les routes publiques ou 🔑 le déclarent explicitement.
    "DEFAULT_PERMISSION_CLASSES": ["apps.appareils.permissions.AppareilDeverrouille"],
    "EXCEPTION_HANDLER": "commun.erreurs.gestionnaire_exceptions",
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "UNAUTHENTICATED_USER": None,
}

SPECTACULAR_SETTINGS = {
    "TITLE": "LuluBoard API",
    "VERSION": VERSION_API,
    "SERVE_INCLUDE_SCHEMA": False,
    "ENUM_NAME_OVERRIDES": {
        "TypeAppareil": "apps.appareils.models.TypeAppareil",
        "TypeCode": "apps.comptes.models.TypeCode",
        "DureeConservation": "apps.comptes.models.DureeConservation",
        "StatutCompte": "apps.comptes.models.StatutCompte",
        "StatutAppareil": "apps.appareils.models.StatutAppareil",
    },
}

LANGUAGE_CODE = "fr"
LANGUAGES = [("fr", "Français"), ("en", "English")]
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"  # rempli par collectstatic, servi par WhiteNoise
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "whitenoise.storage.CompressedStaticFilesStorage"},
}
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "filters": {"request_id": {"()": "commun.middleware.FiltreRequestId"}},
    "formatters": {
        "simple": {"format": "%(asctime)s %(levelname)s [%(request_id)s] %(name)s: %(message)s"},
    },
    "handlers": {
        "console": {"class": "logging.StreamHandler", "filters": ["request_id"], "formatter": "simple"},
    },
    "root": {"handlers": ["console"], "level": "INFO"},
}

# --- Production (DEBUG désactivé) : HTTPS obligatoire derrière le proxy du PaaS ---
if not DEBUG:
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
    SECURE_SSL_REDIRECT = env_bool("SECURE_SSL_REDIRECT", True)
    SECURE_REDIRECT_EXEMPT = [r"^api/v1/health$"]  # sonde de l'hébergeur en HTTP interne
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_HSTS_SECONDS = 31536000
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
    SECURE_CONTENT_TYPE_NOSNIFF = True
    CSRF_TRUSTED_ORIGINS = [o.strip() for o in env("CSRF_TRUSTED_ORIGINS", "").split(",") if o.strip()]
    if RENDER_EXTERNAL_HOSTNAME:
        CSRF_TRUSTED_ORIGINS.append(f"https://{RENDER_EXTERNAL_HOSTNAME}")

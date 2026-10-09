"""Vérifie que le fournisseur de stockage actif (ADR-006) répond.

Le résultat est mis en cache 60 s pour que /health n'appelle pas Telegram
ou LuluFiles à chaque sonde de l'hébergeur.
"""

import logging

import httpx
from django.conf import settings
from django.core.cache import cache

journal = logging.getLogger(__name__)

CLE_CACHE = "sante:stockage"
DUREE_CACHE_S = 60
DELAI_S = 5


def _telegram_disponible():
    if not settings.TELEGRAM_BOT_TOKEN or not settings.TELEGRAM_CHANNEL_ID:
        return False
    url = f"https://api.telegram.org/bot{settings.TELEGRAM_BOT_TOKEN}/getMe"
    reponse = httpx.get(url, timeout=DELAI_S)
    return reponse.status_code == 200 and reponse.json().get("ok") is True


def _lulufiles_disponible():
    if not settings.LULUFILES_API_KEY:
        return False
    reponse = httpx.get(f"{settings.LULUFILES_BASE_URL}/health", timeout=DELAI_S)
    return reponse.status_code == 200


def stockage_disponible():
    try:
        en_cache = cache.get(CLE_CACHE)
    except Exception:
        en_cache = None
    if en_cache is not None:
        return en_cache

    try:
        if settings.FILES_USE_DIRECT_TELEGRAM:
            disponible = _telegram_disponible()
        else:
            disponible = _lulufiles_disponible()
    except (httpx.HTTPError, ValueError):
        # Jamais l'URL dans le journal : elle contient le jeton du bot.
        journal.warning("Fournisseur de stockage injoignable")
        disponible = False

    try:
        cache.set(CLE_CACHE, disponible, DUREE_CACHE_S)
    except Exception:
        pass
    return disponible

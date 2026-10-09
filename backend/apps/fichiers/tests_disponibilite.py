import httpx
import pytest
import respx
from django.core.cache import cache

from apps.fichiers.disponibilite import stockage_disponible


@pytest.fixture(autouse=True)
def cache_local(settings):
    settings.CACHES = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}
    cache.clear()
    yield
    cache.clear()


@respx.mock
def test_telegram_disponible(settings):
    settings.FILES_USE_DIRECT_TELEGRAM = True
    settings.TELEGRAM_BOT_TOKEN = "123:abc"
    settings.TELEGRAM_CHANNEL_ID = "-100"
    respx.get("https://api.telegram.org/bot123:abc/getMe").mock(
        return_value=httpx.Response(200, json={"ok": True})
    )
    assert stockage_disponible() is True


def test_telegram_non_configure(settings):
    settings.FILES_USE_DIRECT_TELEGRAM = True
    settings.TELEGRAM_BOT_TOKEN = ""
    assert stockage_disponible() is False


@respx.mock
def test_lulufiles_injoignable(settings):
    settings.FILES_USE_DIRECT_TELEGRAM = False
    settings.LULUFILES_API_KEY = "lf_live_test"
    settings.LULUFILES_BASE_URL = "https://lulufiles.test"
    respx.get("https://lulufiles.test/health").mock(side_effect=httpx.ConnectError("hors ligne"))
    assert stockage_disponible() is False


@respx.mock
def test_resultat_mis_en_cache(settings):
    settings.FILES_USE_DIRECT_TELEGRAM = False
    settings.LULUFILES_API_KEY = "lf_live_test"
    settings.LULUFILES_BASE_URL = "https://lulufiles.test"
    route = respx.get("https://lulufiles.test/health").mock(return_value=httpx.Response(200, json={"status": "ok"}))
    assert stockage_disponible() is True
    assert stockage_disponible() is True
    assert route.call_count == 1

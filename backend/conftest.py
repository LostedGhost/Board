import pytest


@pytest.fixture(autouse=True)
def isolation(settings):
    """Cache en mémoire et e-mails capturés : les tests ne touchent ni Redis ni un vrai serveur SMTP."""
    from django.core.cache import cache

    settings.CACHES = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}
    settings.EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"
    settings.CHANNEL_LAYERS = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}
    cache.clear()
    yield
    cache.clear()

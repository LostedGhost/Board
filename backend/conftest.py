import pytest


@pytest.fixture(autouse=True)
def isolation(settings):
    """Cache en mémoire et e-mails capturés : les tests ne touchent ni Redis ni un vrai serveur SMTP."""
    from django.core.cache import cache

    settings.CACHES = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}
    settings.EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"
    settings.CHANNEL_LAYERS = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}
    settings.CELERY_TASK_ALWAYS_EAGER = True
    from config.celery import app

    app.conf.task_always_eager = True
    cache.clear()
    yield
    cache.clear()

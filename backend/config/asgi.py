import os

from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

application_http = get_asgi_application()

from channels.routing import ProtocolTypeRouter, URLRouter  # noqa: E402
from django.urls import path  # noqa: E402

from apps.synchro.consumers import SynchroConsumer  # noqa: E402

# Pas de contrôle d'origine : l'authentification passe par un jeton envoyé dans le
# premier message, jamais par un cookie (pas de détournement de WebSocket inter-sites possible).
application = ProtocolTypeRouter(
    {
        "http": application_http,
        "websocket": URLRouter([path("api/v1/ws", SynchroConsumer.as_asgi())]),
    }
)

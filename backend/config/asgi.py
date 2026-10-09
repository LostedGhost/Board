import os

from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

# Le routage WebSocket (Channels) sera ajouté avec le module synchro (contrat 2.6).
application = get_asgi_application()

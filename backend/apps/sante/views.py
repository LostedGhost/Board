"""GET /api/v1/health — contrat, section 2.0. Public, sans donnée sensible."""

import redis
from django.conf import settings
from django.db import connection
from drf_spectacular.utils import extend_schema, inline_serializer
from rest_framework import serializers
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.fichiers.disponibilite import stockage_disponible


def base_disponible():
    try:
        with connection.cursor() as curseur:
            curseur.execute("SELECT 1")
        return True
    except Exception:
        return False


def redis_disponible():
    try:
        client = redis.Redis.from_url(settings.REDIS_URL, socket_connect_timeout=2, socket_timeout=2)
        return client.ping() is True
    except Exception:
        return False


class SanteView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    @extend_schema(
        responses=inline_serializer(
            "Sante",
            {
                "statut": serializers.ChoiceField(choices=["ok", "degrade"]),
                "version": serializers.CharField(),
                "verifications": inline_serializer(
                    "Verifications",
                    {
                        "base": serializers.BooleanField(),
                        "redis": serializers.BooleanField(),
                        "stockage": serializers.BooleanField(),
                    },
                ),
            },
        )
    )
    def get(self, request):
        verifications = {
            "base": base_disponible(),
            "redis": redis_disponible(),
            "stockage": stockage_disponible(),
        }
        statut = "ok" if all(verifications.values()) else "degrade"
        # Sans base, l'API ne peut rien servir : 503 pour que l'hébergeur le détecte.
        code_http = 200 if verifications["base"] else 503
        return Response(
            {"statut": statut, "version": settings.VERSION_API, "verifications": verifications},
            status=code_http,
        )

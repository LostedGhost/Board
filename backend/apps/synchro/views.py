"""Contrat 2.5 — GET /synchro/changements, POST /synchro/envoyer."""

from drf_spectacular.utils import OpenApiParameter, extend_schema, inline_serializer
from rest_framework import serializers
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.synchro import services


class ChangementsView(APIView):
    @extend_schema(
        parameters=[
            OpenApiParameter("depuis", int, required=True),
            OpenApiParameter("limite", int, required=False),
        ],
        responses=inline_serializer(
            "Changements",
            {
                "versionCourante": serializers.IntegerField(),
                "changements": serializers.ListField(child=serializers.DictField()),
                "encore": serializers.BooleanField(),
            },
        ),
    )
    def get(self, request):
        depuis = serializers.IntegerField(min_value=0).run_validation(request.query_params.get("depuis", "0"))
        limite = serializers.IntegerField(min_value=1, max_value=services.LIMITE_LOT).run_validation(
            request.query_params.get("limite", str(services.LIMITE_LOT))
        )
        version, changements, encore = services.changements_depuis(request.user, depuis, limite)
        return Response({"versionCourante": version, "changements": changements, "encore": encore})


class LotChangementsSerializer(serializers.Serializer):
    changements = services.ChangementSerializer(many=True, max_length=services.LIMITE_LOT)


class EnvoyerView(APIView):
    @extend_schema(
        request=LotChangementsSerializer,
        responses=inline_serializer(
            "ResultatEnvoi",
            {"versionCourante": serializers.IntegerField(), "resultats": serializers.ListField(child=serializers.DictField())},
        ),
    )
    def post(self, request):
        s = LotChangementsSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        version, resultats = services.appliquer_changements(request.user, request.appareil, s.validated_data["changements"])
        return Response({"versionCourante": version, "resultats": resultats})

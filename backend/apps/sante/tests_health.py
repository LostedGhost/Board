from unittest import mock

import pytest
from rest_framework.test import APIClient

URL = "/api/v1/health"


@pytest.fixture
def client():
    return APIClient()


def _avec(base=True, redis=True, stockage=True):
    return [
        mock.patch("apps.sante.views.base_disponible", return_value=base),
        mock.patch("apps.sante.views.redis_disponible", return_value=redis),
        mock.patch("apps.sante.views.stockage_disponible", return_value=stockage),
    ]


def _get(client, **etats):
    patches = _avec(**etats)
    for p in patches:
        p.start()
    try:
        return client.get(URL)
    finally:
        for p in patches:
            p.stop()


def test_tout_va_bien(client):
    reponse = _get(client)
    assert reponse.status_code == 200
    assert reponse.json() == {
        "statut": "ok",
        "version": "0.1.0",
        "verifications": {"base": True, "redis": True, "stockage": True},
    }


@pytest.mark.parametrize("panne", ["redis", "stockage"])
def test_degrade_sans_bloquer(client, panne):
    reponse = _get(client, **{panne: False})
    assert reponse.status_code == 200
    assert reponse.json()["statut"] == "degrade"
    assert reponse.json()["verifications"][panne] is False


def test_base_indisponible_renvoie_503(client):
    reponse = _get(client, base=False)
    assert reponse.status_code == 503
    assert reponse.json()["statut"] == "degrade"


def test_public_et_request_id(client):
    reponse = _get(client)
    assert "X-Request-ID" in reponse.headers


def test_request_id_fourni_est_repris(client):
    patches = _avec()
    for p in patches:
        p.start()
    try:
        reponse = client.get(URL, HTTP_X_REQUEST_ID="test-1234abcd")
    finally:
        for p in patches:
            p.stop()
    assert reponse.headers["X-Request-ID"] == "test-1234abcd"


def test_request_id_malveillant_est_remplace(client):
    patches = _avec()
    for p in patches:
        p.start()
    try:
        reponse = client.get(URL, HTTP_X_REQUEST_ID="<script>alert(1)</script>")
    finally:
        for p in patches:
            p.stop()
    assert "<" not in reponse.headers["X-Request-ID"]


def test_methode_non_autorisee_au_format_commun(client):
    reponse = client.post(URL)
    assert reponse.status_code == 405
    assert reponse.json()["erreur"]["code"] == "requete_invalide"
    assert "requestId" in reponse.json()["erreur"]


@pytest.mark.django_db
def test_verification_reelle_de_la_base():
    from apps.sante.views import base_disponible

    assert base_disponible() is True

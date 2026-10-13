import json

import httpx
import pytest
import respx
from django.core import mail
from django.core.mail import EmailMultiAlternatives, get_connection

from apps.comptes.emails import envoyer_code
from apps.comptes.models import TypeCode
from commun.brevo import URL_API
from commun.courriels import envoyer_courriel


def test_code_envoye_en_texte_et_en_html():
    envoyer_code("alice@exemple.test", TypeCode.INSCRIPTION, "123456")
    m = mail.outbox[-1]
    assert "123456" in m.body
    html, type_ = m.alternatives[0]
    assert type_ == "text/html" and "123456" in html and "Bienvenue sur LuluBoard" in html


def test_contenu_utilisateur_echappe_dans_le_html():
    envoyer_courriel("support@exemple.test", "Support", "Demande", ["<script>alert(1)</script>"])
    html = mail.outbox[-1].alternatives[0][0]
    assert "<script>" not in html and "&lt;script&gt;" in html


@respx.mock
def test_backend_brevo(settings):
    settings.BREVO_API_KEY = "cle-test"
    settings.DEFAULT_FROM_EMAIL = "LuluBoard <expediteur@exemple.test>"
    route = respx.post(URL_API).mock(return_value=httpx.Response(201, json={"messageId": "x"}))
    with get_connection("commun.brevo.BrevoEmailBackend") as connexion:
        m = EmailMultiAlternatives("Sujet", "texte", settings.DEFAULT_FROM_EMAIL, ["alice@exemple.test"], connection=connexion)
        m.attach_alternative("<p>html</p>", "text/html")
        assert m.send() == 1
    requete = route.calls.last.request
    assert requete.headers["api-key"] == "cle-test"
    corps = json.loads(requete.content)
    assert corps["sender"] == {"email": "expediteur@exemple.test", "name": "LuluBoard"}
    assert corps["to"] == [{"email": "alice@exemple.test"}]
    assert corps["htmlContent"] == "<p>html</p>" and corps["textContent"] == "texte"


@respx.mock
def test_backend_brevo_erreur(settings):
    settings.BREVO_API_KEY = "mauvaise"
    respx.post(URL_API).mock(return_value=httpx.Response(401, json={"message": "Key not found"}))
    with get_connection("commun.brevo.BrevoEmailBackend") as connexion:
        m = mail.EmailMessage("Sujet", "texte", "a@exemple.test", ["b@exemple.test"], connection=connexion)
        with pytest.raises(RuntimeError, match="401"):
            m.send()
    with get_connection("commun.brevo.BrevoEmailBackend", fail_silently=True) as silencieuse:
        assert silencieuse.send_messages([m]) == 0

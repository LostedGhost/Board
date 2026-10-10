"""Contrat 2.7 — fichiers (mode Telegram direct simulé, et mode LuluFiles simulé)."""

import json
import os
import uuid
from datetime import timedelta

import httpx
import pytest
import respx
from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone

from apps.appareils.tests_appareils import alice, cle_signature, telephone  # noqa: F401
from apps.comptes.tests_inscription import conditions  # noqa: F401
from apps.elements.models import Element
from apps.fichiers import stockage
from apps.fichiers.models import Fichier, MorceauTelegram, StatutFichier
from commun.b64 import encoder

pytestmark = pytest.mark.django_db(transaction=True)

TG = "https://api.telegram.org"


@pytest.fixture
def telegram(settings, monkeypatch, tmp_path):
    """Canal Telegram simulé, en mémoire, avec des morceaux de 1 000 octets."""
    settings.FILES_USE_DIRECT_TELEGRAM = True
    settings.TELEGRAM_BOT_TOKEN = "123:secret"
    settings.TELEGRAM_CHANNEL_ID = "-1001"
    settings.FICHIERS_DOSSIER_TEMPORAIRE = str(tmp_path)
    monkeypatch.setattr(stockage, "TAILLE_MORCEAU", 1000)
    canal = {}

    def envoyer(requete):
        corps = requete.content
        # Extraction simple du contenu de la partie « document » du multipart.
        limite = requete.headers["content-type"].split("boundary=")[1].encode()
        partie = [p for p in corps.split(b"--" + limite) if b'name="document"' in p][0]
        octets = partie.split(b"\r\n\r\n", 1)[1].rsplit(b"\r\n", 1)[0]
        mid = len(canal) + 1
        canal[f"f{mid}"] = octets
        return httpx.Response(200, json={"ok": True, "result": {"message_id": mid, "document": {"file_id": f"f{mid}"}}})

    with respx.mock(assert_all_called=False) as routeur:
        routeur.post(f"{TG}/bot123:secret/sendDocument").mock(side_effect=envoyer)
        routeur.get(f"{TG}/bot123:secret/getFile").mock(
            side_effect=lambda r: httpx.Response(200, json={"ok": True, "result": {"file_path": r.url.params["file_id"]}})
        )
        routeur.get(url__regex=rf"{TG}/file/bot123:secret/.*").mock(
            side_effect=lambda r: httpx.Response(200, content=canal[r.url.path.rsplit("/", 1)[1]])
        )
        def supprimer(requete):
            canal.setdefault("supprimes", []).append(requete.content)
            return httpx.Response(200, json={"ok": True, "result": True})

        routeur.post(f"{TG}/bot123:secret/deleteMessage").mock(side_effect=supprimer)
        yield canal


def televerser(client, octets, id_=None):
    meta = {
        "id": str(id_ or uuid.uuid4()),
        "modifieLe": timezone.now().isoformat(),
        "tailleOctets": len(octets),
        "cleElementEnveloppee": encoder(os.urandom(72)),
        "contenuChiffre": encoder(os.urandom(48)),
    }
    return client.post(
        "/api/v1/fichiers",
        {"metadonnees": json.dumps(meta), "fichier": SimpleUploadedFile("x.bin", octets)},
        format="multipart",
    )


def test_televersement_decoupe_et_relecture(alice, telegram):
    octets = os.urandom(2500)
    r = televerser(alice, octets)
    assert r.status_code == 202
    fichier = Fichier.objects.get(element_id=r.json()["id"])
    assert fichier.statut == StatutFichier.PRET and fichier.chemin_temporaire is None
    assert MorceauTelegram.objects.filter(fichier=fichier).count() == 3
    assert alice.get(f"/api/v1/fichiers/{fichier.element_id}/acces").json()["mode"] == "flux"
    r = alice.get(f"/api/v1/fichiers/{fichier.element_id}/contenu")
    assert r.status_code == 200 and b"".join(r.streaming_content) == octets


def test_lecture_partielle_range(alice, telegram):
    octets = os.urandom(2500)
    fid = televerser(alice, octets).json()["id"]
    r = alice.get(f"/api/v1/fichiers/{fid}/contenu", HTTP_RANGE="bytes=900-2099")
    assert r.status_code == 206 and r["Content-Range"] == "bytes 900-2099/2500"
    assert b"".join(r.streaming_content) == octets[900:2100]
    r = alice.get(f"/api/v1/fichiers/{fid}/contenu", HTTP_RANGE="bytes=-100")
    assert b"".join(r.streaming_content) == octets[-100:]
    assert alice.get(f"/api/v1/fichiers/{fid}/contenu", HTTP_RANGE="bytes=5000-").status_code == 416


def test_morceau_corrompu_detecte(alice, telegram):
    octets = os.urandom(1500)
    fid = televerser(alice, octets).json()["id"]
    telegram["f1"] = b"x" * 1000  # le canal renvoie autre chose que ce qui a été envoyé
    r = alice.get(f"/api/v1/fichiers/{fid}/contenu")
    with pytest.raises(stockage.ErreurStockage):
        b"".join(r.streaming_content)


def test_element_fichier_visible_dans_la_synchro(alice, telegram):
    fid = televerser(alice, os.urandom(10)).json()["id"]
    changements = alice.get("/api/v1/synchro/changements?depuis=0").json()["changements"]
    assert [c["donnees"]["type"] for c in changements if c["id"] == fid] == ["FICHIER"]


def test_suppression_par_la_synchro_efface_chez_telegram(alice, telegram):
    fid = televerser(alice, os.urandom(1500)).json()["id"]
    maintenant = (timezone.now() + timedelta(minutes=1)).isoformat()
    alice.post("/api/v1/synchro/envoyer", {"changements": [{"entite": "element", "id": fid, "modifieLe": maintenant, "supprimeLe": maintenant}]}, format="json")
    assert len(telegram["supprimes"]) == 2  # les 2 morceaux sont effacés du canal
    assert alice.get(f"/api/v1/fichiers/{fid}").status_code == 404


def test_taille_annoncee_incoherente(alice, telegram):
    meta = {"id": str(uuid.uuid4()), "modifieLe": timezone.now().isoformat(), "tailleOctets": 999, "cleElementEnveloppee": encoder(os.urandom(72)), "contenuChiffre": encoder(os.urandom(48))}
    r = alice.post("/api/v1/fichiers", {"metadonnees": json.dumps(meta), "fichier": SimpleUploadedFile("x", b"abc")}, format="multipart")
    assert r.status_code == 422


def test_identifiant_deja_pris(alice, telegram):
    id_ = uuid.uuid4()
    televerser(alice, b"abc", id_)
    assert televerser(alice, b"abc", id_).status_code == 409


def test_echec_puis_reessai(alice, settings, tmp_path, monkeypatch):
    settings.FILES_USE_DIRECT_TELEGRAM = True
    settings.TELEGRAM_BOT_TOKEN = "123:secret"
    settings.TELEGRAM_CHANNEL_ID = "-1001"
    settings.FICHIERS_DOSSIER_TEMPORAIRE = str(tmp_path)
    with respx.mock() as routeur:
        routeur.post(f"{TG}/bot123:secret/sendDocument").mock(return_value=httpx.Response(502, json={"ok": False}))
        fid = televerser(alice, b"abcdef").json()["id"]
    fichier = Fichier.objects.get(element_id=fid)
    assert fichier.statut == StatutFichier.ECHEC and "secret" not in (fichier.message_erreur or "")
    with respx.mock() as routeur:
        routeur.post(f"{TG}/bot123:secret/sendDocument").mock(
            return_value=httpx.Response(200, json={"ok": True, "result": {"message_id": 1, "document": {"file_id": "a"}}})
        )
        assert alice.post(f"/api/v1/fichiers/{fid}/reessayer").status_code == 202
    assert Fichier.objects.get(element_id=fid).statut == StatutFichier.PRET


def test_fichier_d_un_autre_compte_introuvable(alice, telegram):
    fid = televerser(alice, b"abc").json()["id"]
    from apps.comptes.models import Compte

    autre = Compte.objects.create_user("eve@exemple.test", "Eve", "Mdp12345A")
    Element.objects.filter(id=fid).update(compte=autre)
    assert alice.get(f"/api/v1/fichiers/{fid}").status_code == 404
    assert alice.get(f"/api/v1/fichiers/{fid}/contenu").status_code == 404


def test_appareil_non_deverrouille_refuse(telephone, telegram):
    assert televerser(telephone, b"abc").status_code == 403


def test_mode_lulufiles(alice, settings, tmp_path):
    settings.FILES_USE_DIRECT_TELEGRAM = False
    settings.LULUFILES_API_KEY = "lf_live_test"
    settings.LULUFILES_BASE_URL = "https://lulu.test"
    settings.FICHIERS_DOSSIER_TEMPORAIRE = str(tmp_path)
    settings.LULUFILES_CORS_OUVERT = True
    lid = str(uuid.uuid4())
    with respx.mock() as routeur:
        routeur.post("https://lulu.test/files/upload").mock(return_value=httpx.Response(201, json={"id": lid, "status": "ready"}))
        routeur.post(f"https://lulu.test/files/{lid}/link").mock(
            return_value=httpx.Response(200, json={"url": f"/files/{lid}/content?sig=x", "expires_at": "2026-10-10T13:00:00Z"})
        )
        fid = televerser(alice, b"abcdef").json()["id"]
        fichier = Fichier.objects.get(element_id=fid)
        assert fichier.statut == StatutFichier.PRET and str(fichier.id_lulufiles) == lid
        acces = alice.get(f"/api/v1/fichiers/{fid}/acces").json()
        assert acces["mode"] == "lien_signe" and acces["url"].startswith("https://lulu.test/files/")

"""Contrat 2.5 / 2.6 — synchronisation et WebSocket."""

import os
import uuid
from datetime import datetime, timedelta, timezone as tz

import pytest
from asgiref.sync import async_to_sync
from channels.testing import WebsocketCommunicator

from apps.appareils.tests_appareils import alice, cle_signature, telephone  # noqa: F401
from apps.comptes.tests_inscription import conditions  # noqa: F401
from apps.elements.models import Element, VersionPostIt
from commun.b64 import decoder, encoder

pytestmark = pytest.mark.django_db(transaction=True)

T0 = datetime(2026, 10, 10, 12, 0, tzinfo=tz.utc)


def iso(dt):
    return dt.isoformat().replace("+00:00", "Z")


def contenu(n=64):
    return encoder(os.urandom(n))


def element(id_=None, type_="POST_IT", quand=T0, **donnees):
    d = {"type": type_, "contenuChiffre": contenu(), "cleElementEnveloppee": contenu(72)}
    if type_ == "PRESSE_PAPIER":
        d["typeContenu"] = "TEXTE"
    d.update(donnees)
    return {"entite": "element", "id": str(id_ or uuid.uuid4()), "modifieLe": iso(quand), "donnees": d}


def envoyer(client, *changements):
    r = client.post("/api/v1/synchro/envoyer", {"changements": list(changements)}, format="json")
    assert r.status_code == 200, r.content
    return r.json()


def tirer(client, depuis=0, limite=500):
    r = client.get(f"/api/v1/synchro/changements?depuis={depuis}&limite={limite}")
    assert r.status_code == 200, r.content
    return r.json()


def test_creation_puis_lecture(alice):
    ch = element()
    r = envoyer(alice, ch)
    assert r["resultats"][0]["statut"] == "accepte" and r["versionCourante"] == 1
    t = tirer(alice)
    assert t["versionCourante"] == 1 and t["encore"] is False
    recu = t["changements"][0]
    assert recu["id"] == ch["id"] and recu["donnees"]["contenuChiffre"] == ch["donnees"]["contenuChiffre"]
    assert recu["donnees"]["appareilAuteurId"] == alice.appareil_id


def test_pull_incremental_et_pagination(alice):
    envoyer(alice, *[element() for _ in range(5)])
    page = tirer(alice, depuis=0, limite=2)
    assert len(page["changements"]) == 2 and page["encore"] is True and page["versionCourante"] == 2
    page = tirer(alice, depuis=2, limite=10)
    assert [c["version"] for c in page["changements"]] == [3, 4, 5] and page["encore"] is False


def test_derniere_modification_gagne(alice):
    id_ = uuid.uuid4()
    envoyer(alice, element(id_, quand=T0 + timedelta(minutes=5)))
    r = envoyer(alice, element(id_, quand=T0))  # plus ancien
    assert r["resultats"][0]["statut"] == "ecrase_par_plus_recent"
    r = envoyer(alice, element(id_, quand=T0 + timedelta(minutes=10)))
    assert r["resultats"][0]["statut"] == "accepte"


def test_post_it_historique_des_versions(alice):
    id_ = uuid.uuid4()
    v1 = element(id_, quand=T0)
    envoyer(alice, v1)
    envoyer(alice, element(id_, quand=T0 + timedelta(minutes=1)))
    versions = VersionPostIt.objects.filter(post_it_id=id_)
    assert versions.count() == 1 and encoder(bytes(versions.get().contenu_chiffre)) == v1["donnees"]["contenuChiffre"]
    assert any(c["entite"] == "version_post_it" for c in tirer(alice)["changements"])


def test_conflit_post_it_conserve_le_perdant(alice):
    id_ = uuid.uuid4()
    envoyer(alice, element(id_, quand=T0 + timedelta(minutes=5)))
    perdant = element(id_, quand=T0)
    envoyer(alice, perdant)
    contenus = [encoder(bytes(v.contenu_chiffre)) for v in VersionPostIt.objects.filter(post_it_id=id_)]
    assert perdant["donnees"]["contenuChiffre"] in contenus


def test_suppression_definitive_et_contenu_efface(alice):
    id_ = uuid.uuid4()
    envoyer(alice, element(id_, quand=T0))
    supp = {"entite": "element", "id": str(id_), "modifieLe": iso(T0 + timedelta(minutes=1)), "supprimeLe": iso(T0 + timedelta(minutes=1))}
    assert envoyer(alice, supp)["resultats"][0]["statut"] == "accepte"
    e = Element.objects.get(id=id_)
    assert e.supprime_le is not None and e.contenu_chiffre is None and e.cle_element_enveloppee is None
    # Une modification plus récente ne ressuscite pas l'élément.
    r = envoyer(alice, element(id_, quand=T0 + timedelta(hours=1)))
    assert r["resultats"][0]["statut"] == "ecrase_par_plus_recent"


def test_type_immuable(alice):
    id_ = uuid.uuid4()
    envoyer(alice, element(id_))
    r = envoyer(alice, element(id_, type_="SNIPPET", quand=T0 + timedelta(minutes=1)))
    assert r["resultats"][0] == {"entite": "element", "id": str(id_), "statut": "rejete", "code": "type_immuable"}


def test_fichier_jamais_cree_par_la_synchro(alice):
    r = envoyer(alice, element(type_="FICHIER"))
    assert r["resultats"][0]["code"] == "reserve_aux_fichiers"


def test_presse_papier_taille_maximale(alice):
    gros = element(type_="PRESSE_PAPIER", contenuChiffre=encoder(os.urandom(102 * 1024)))
    assert envoyer(alice, gros)["resultats"][0]["code"] == "validation"
    image = element(type_="PRESSE_PAPIER", typeContenu="IMAGE", contenuChiffre=encoder(os.urandom(102 * 1024)))
    assert envoyer(alice, image)["resultats"][0]["statut"] == "accepte"


def test_entites_simples_et_rappel(alice):
    tableau = {"entite": "tableau", "id": str(uuid.uuid4()), "modifieLe": iso(T0), "donnees": {"contenuChiffre": contenu()}}
    post_it = element(parentId=tableau["id"])
    etiquette = {"entite": "etiquette", "id": str(uuid.uuid4()), "modifieLe": iso(T0), "donnees": {"contenuChiffre": contenu()}}
    liaison = {"entite": "element_etiquette", "id": str(uuid.uuid4()), "modifieLe": iso(T0), "donnees": {"elementId": post_it["id"], "etiquetteId": etiquette["id"]}}
    rappel = {
        "entite": "rappel",
        "id": str(uuid.uuid4()),
        "modifieLe": iso(T0),
        "donnees": {"elementId": post_it["id"], "prochaineEcheance": iso(T0 + timedelta(days=1)), "recurrence": "HEBDOMADAIRE", "joursSemaine": ["LUNDI"], "fuseauHoraire": "Africa/Porto-Novo"},
    }
    r = envoyer(alice, tableau, post_it, etiquette, liaison, rappel)
    assert [x["statut"] for x in r["resultats"]] == ["accepte"] * 5
    entites = {c["entite"] for c in tirer(alice)["changements"]}
    assert entites == {"tableau", "element", "etiquette", "element_etiquette", "rappel"}


def test_rappel_fuseau_invalide(alice):
    rappel = {"entite": "rappel", "id": str(uuid.uuid4()), "modifieLe": iso(T0), "donnees": {"elementId": str(uuid.uuid4()), "prochaineEcheance": iso(T0), "fuseauHoraire": "Mars/Olympus"}}
    assert envoyer(alice, rappel)["resultats"][0]["code"] == "validation"


def test_version_post_it_en_lecture_seule(alice):
    ch = {"entite": "version_post_it", "id": str(uuid.uuid4()), "modifieLe": iso(T0), "donnees": {}}
    assert envoyer(alice, ch)["resultats"][0]["code"] == "lecture_seule"


def test_isolation_entre_comptes(alice, conditions):
    from apps.appareils.tests_appareils import client_avec, enveloppe
    from apps.comptes.tests_inscription import appareil, dernier_code, inscrire
    from rest_framework.test import APIClient

    id_ = uuid.uuid4()
    envoyer(alice, element(id_))
    c = APIClient()
    inscrire(c, conditions, email="bob@exemple.test")
    r = c.post(
        "/api/v1/auth/inscription/verifier",
        {"email": "bob@exemple.test", "code": dernier_code(), "appareil": appareil(), "cles": {"enveloppeRecuperation": enveloppe(), "enveloppeAppareil": enveloppe(), "clePubliqueVerification": encoder(os.urandom(32))}},
        format="json",
    )
    bob = client_avec(r.json()["session"]["jeton"])
    bob.post("/api/v1/compte/cle-recuperation/confirmer")
    assert tirer(bob)["changements"] == []
    # Bob ne peut ni écraser ni supprimer l'élément d'Alice, même en connaissant son id.
    r = envoyer(bob, element(id_, quand=T0 + timedelta(days=1)))
    assert r["resultats"][0]["code"] == "introuvable"
    assert Element.objects.get(id=id_).compte.email == "alice@exemple.test"


def test_appareil_non_deverrouille_ne_synchronise_pas(telephone):
    assert telephone.get("/api/v1/synchro/changements?depuis=0").status_code == 403


def test_corps_trop_gros_refuse(alice):
    r = alice.generic("POST", "/api/v1/synchro/envoyer", b"{}", content_type="application/json", CONTENT_LENGTH=str(13 * 1024 * 1024))
    assert r.status_code == 413


def test_lot_trop_grand(alice):
    r = alice.post("/api/v1/synchro/envoyer", {"changements": [element() for _ in range(501)]}, format="json")
    assert r.status_code == 422


# --- WebSocket ----------------------------------------------------------------------------


def _ws():
    from config.asgi import application

    return WebsocketCommunicator(application, "/api/v1/ws")


def test_websocket_auth_et_evenement(alice):
    jeton = alice._credentials["HTTP_AUTHORIZATION"].split()[1]

    async def scenario():
        ws = _ws()
        connecte, _ = await ws.connect()
        assert connecte
        await ws.send_json_to({"type": "auth", "jeton": jeton})
        assert (await ws.receive_json_from())["type"] == "pret"
        from channels.db import database_sync_to_async

        await database_sync_to_async(envoyer)(alice, element())
        evenement = await ws.receive_json_from(timeout=5)
        assert evenement["type"] == "changements" and evenement["versionCourante"] == 1
        await ws.disconnect()

    async_to_sync(scenario)()


def test_websocket_jeton_invalide_ferme(alice):
    async def scenario():
        ws = _ws()
        await ws.connect()
        await ws.send_json_to({"type": "auth", "jeton": "faux"})
        sortie = await ws.receive_output(timeout=5)
        assert sortie["type"] == "websocket.close" and sortie["code"] == 4401

    async_to_sync(scenario)()

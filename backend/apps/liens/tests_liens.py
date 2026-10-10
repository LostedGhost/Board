"""Contrats 2.8 à 2.11 et tâches planifiées."""

import os
import uuid
from datetime import datetime, timedelta, timezone as tz

import pytest
from django.core import mail
from django.utils import timezone
from rest_framework.test import APIClient

from apps.appareils.tests_appareils import alice, cle_signature, telephone  # noqa: F401
from apps.comptes.models import Compte, StatutCompte
from apps.comptes.tests_inscription import conditions  # noqa: F401
from apps.elements.models import Element, Rappel, VersionPostIt
from apps.liens.models import LienPublic
from apps.moderation.models import Signalement
from apps.synchro.tests_synchro import element, envoyer
from commun.b64 import encoder

pytestmark = pytest.mark.django_db(transaction=True)


def deverrouiller(alice, telephone):
    d = telephone.post("/api/v1/appareils/courant/deverrouillage").json()
    alice.post(f"/api/v1/deverrouillages/{d['id']}/approuver", {"codeAffiche": d["codeAffiche"], "cleMaitreEnveloppee": encoder(os.urandom(72))}, format="json")


# --- 2.8 Envois ---------------------------------------------------------------------------


def test_envoi_cible_puis_recuperation(alice, telephone):
    deverrouiller(alice, telephone)
    r = alice.post("/api/v1/envois", {"appareilCibleId": telephone.appareil_id, "contenuChiffre": encoder(b"x" * 40)}, format="json")
    assert r.status_code == 201
    recus = telephone.get("/api/v1/envois/recus").json()
    assert len(recus) == 1 and recus[0]["contenuChiffre"] == encoder(b"x" * 40)
    assert alice.get("/api/v1/envois/recus").json() == []  # l'expéditeur ne le reçoit pas
    assert telephone.post(f"/api/v1/envois/{recus[0]['id']}/recupere").status_code == 204
    assert telephone.get("/api/v1/envois/recus").json() == []


def test_envoi_a_tous(alice, telephone):
    deverrouiller(alice, telephone)
    alice.post("/api/v1/envois", {"appareilCibleId": None, "contenuChiffre": encoder(b"y" * 40)}, format="json")
    assert len(telephone.get("/api/v1/envois/recus").json()) == 1


def test_envoi_vers_soi_meme_ou_inconnu(alice):
    assert alice.post("/api/v1/envois", {"appareilCibleId": alice.appareil_id, "contenuChiffre": encoder(b"z")}, format="json").status_code == 404
    assert alice.post("/api/v1/envois", {"appareilCibleId": str(uuid.uuid4()), "contenuChiffre": encoder(b"z")}, format="json").status_code == 404


def test_envoi_vide_refuse(alice):
    assert alice.post("/api/v1/envois", {}, format="json").status_code == 422


# --- 2.9 / 2.10 Liens publics -------------------------------------------------------------


def creer_lien(alice, element_id, **extra):
    corps = {"elementId": element_id, "duree": "J7", "protegeParMotDePasse": False, **extra}
    return alice.post("/api/v1/liens", corps, format="json")


def test_lien_public_en_direct(alice):
    ch = element()
    envoyer(alice, ch)
    r = creer_lien(alice, ch["id"])
    assert r.status_code == 201 and r["Cache-Control"] == "no-store"
    jeton = r.json()["jeton"]
    public = APIClient().get(f"/api/v1/public/liens/{jeton}").json()
    assert public["element"]["contenuChiffre"] == ch["donnees"]["contenuChiffre"]
    # Modification du post-it → le lien montre la nouvelle version (en direct).
    maj = element(ch["id"], quand=datetime(2026, 10, 11, tzinfo=tz.utc))
    envoyer(alice, maj)
    assert APIClient().get(f"/api/v1/public/liens/{jeton}").json()["element"]["contenuChiffre"] == maj["donnees"]["contenuChiffre"]


def test_liste_de_taches_avec_sous_taches(alice):
    liste = element(type_="LISTE_TACHES")
    t1 = element(type_="TACHE", parentId=liste["id"], cleElementEnveloppee=None)
    t2 = element(type_="TACHE", parentId=t1["id"], cleElementEnveloppee=None)
    envoyer(alice, liste, t1, t2)
    jeton = creer_lien(alice, liste["id"]).json()["jeton"]
    taches = APIClient().get(f"/api/v1/public/liens/{jeton}").json()["element"]["taches"]
    assert {t["id"] for t in taches} == {t1["id"], t2["id"]}


def test_presse_papier_non_partageable(alice):
    ch = element(type_="PRESSE_PAPIER")
    envoyer(alice, ch)
    assert creer_lien(alice, ch["id"]).status_code == 422


def test_lien_protege_par_mot_de_passe(alice):
    ch = element()
    envoyer(alice, ch)
    verif = os.urandom(32)
    r = creer_lien(
        alice,
        ch["id"],
        protegeParMotDePasse=True,
        selDerivation=encoder(os.urandom(16)),
        cleElementEnveloppee=encoder(os.urandom(73)),
        verificateurMotDePasse=encoder(verif),
    )
    jeton = r.json()["jeton"]
    anonyme = APIClient()
    public = anonyme.get(f"/api/v1/public/liens/{jeton}").json()
    assert public["protegeParMotDePasse"] is True and "element" not in public and public["selDerivation"]
    faux = encoder(os.urandom(32))
    for _ in range(5):
        assert anonyme.post(f"/api/v1/public/liens/{jeton}/deverrouiller", {"verificateurMotDePasse": faux}, format="json").status_code == 422
    r = anonyme.post(f"/api/v1/public/liens/{jeton}/deverrouiller", {"verificateurMotDePasse": encoder(verif)}, format="json")
    assert r.status_code == 423  # bloqué même avec le bon mot de passe
    LienPublic.objects.all()  # le vérificateur n'est jamais stocké en clair
    assert encoder(verif) not in str(LienPublic.objects.values_list("verificateur_mot_de_passe_hash", flat=True)[0])


def test_lien_protege_bon_mot_de_passe(alice):
    ch = element()
    envoyer(alice, ch)
    verif = os.urandom(32)
    jeton = creer_lien(alice, ch["id"], protegeParMotDePasse=True, selDerivation=encoder(os.urandom(16)), cleElementEnveloppee=encoder(os.urandom(73)), verificateurMotDePasse=encoder(verif)).json()["jeton"]
    r = APIClient().post(f"/api/v1/public/liens/{jeton}/deverrouiller", {"verificateurMotDePasse": encoder(verif)}, format="json")
    assert r.status_code == 200 and r.json()["element"]["contenuChiffre"] == ch["donnees"]["contenuChiffre"]


def test_revocation_expiration_suppression(alice):
    ch = element()
    envoyer(alice, ch)
    r = creer_lien(alice, ch["id"])
    jeton, lien_id = r.json()["jeton"], r.json()["lien"]["id"]
    assert alice.delete(f"/api/v1/liens/{lien_id}").status_code == 204
    assert APIClient().get(f"/api/v1/public/liens/{jeton}").status_code == 410
    # Expiration
    jeton2 = creer_lien(alice, ch["id"]).json()["jeton"]
    LienPublic.objects.filter(revoque_le__isnull=True).update(expire_le=timezone.now() - timedelta(seconds=1))
    assert APIClient().get(f"/api/v1/public/liens/{jeton2}").status_code == 410
    # Suppression de l'élément
    jeton3 = creer_lien(alice, ch["id"], duree="INFINIE").json()["jeton"]
    maintenant = datetime(2026, 10, 12, tzinfo=tz.utc).isoformat()  # postérieur à la création (T0)
    alice.post("/api/v1/synchro/envoyer", {"changements": [{"entite": "element", "id": ch["id"], "modifieLe": maintenant, "supprimeLe": maintenant}]}, format="json")
    assert APIClient().get(f"/api/v1/public/liens/{jeton3}").status_code == 410
    assert APIClient().get("/api/v1/public/liens/inexistant").status_code == 410


def test_liste_et_prolongation(alice):
    ch = element()
    envoyer(alice, ch)
    lien_id = creer_lien(alice, ch["id"]).json()["lien"]["id"]
    r = alice.patch(f"/api/v1/liens/{lien_id}", {"duree": "INFINIE"}, format="json")
    assert r.status_code == 200 and r.json()["expireLe"] is None
    liens = alice.get("/api/v1/liens").json()
    assert len(liens) == 1 and liens[0]["statut"] == "ACTIF"


def test_signalement(alice):
    ch = element()
    envoyer(alice, ch)
    jeton = creer_lien(alice, ch["id"]).json()["jeton"]
    r = APIClient().post(f"/api/v1/public/liens/{jeton}/signalements", {"motif": "HAMECONNAGE", "commentaire": "suspect"}, format="json")
    assert r.status_code == 201 and Signalement.objects.count() == 1
    assert APIClient().post(f"/api/v1/public/liens/{jeton}/signalements", {"motif": "INCONNU"}, format="json").status_code == 422


# --- 2.11 ---------------------------------------------------------------------------------


def test_annonces_support_export(alice, settings):
    from apps.conformite.models import Annonce

    Annonce.objects.create(message_fr="Maintenance ce soir", message_en="Maintenance tonight")
    assert len(APIClient().get("/api/v1/annonces/actives").json()) == 1
    settings.SUPPORT_EMAIL = "support@exemple.test"
    mail.outbox.clear()
    assert APIClient().post("/api/v1/support", {"emailContact": "a@b.test", "message": "Bonjour, souci de synchro"}, format="json").status_code == 201
    assert mail.outbox and mail.outbox[0].to == ["support@exemple.test"]
    envoyer(alice, element(), element(type_="SNIPPET"))
    export = alice.get("/api/v1/export").json()
    assert len(export["entites"]) == 2 and export["compte"]["email"] == "alice@exemple.test"


# --- Tâches planifiées --------------------------------------------------------------------


def test_rappel_recurrent_avance(alice):
    from apps.elements.taches import envoyer_rappels_dus

    passe = timezone.now() - timedelta(minutes=1)
    rappel = {"entite": "rappel", "id": str(uuid.uuid4()), "modifieLe": passe.isoformat(), "donnees": {"elementId": str(uuid.uuid4()), "prochaineEcheance": passe.isoformat(), "recurrence": "QUOTIDIENNE", "fuseauHoraire": "Africa/Porto-Novo"}}
    unique = {"entite": "rappel", "id": str(uuid.uuid4()), "modifieLe": passe.isoformat(), "donnees": {"elementId": str(uuid.uuid4()), "prochaineEcheance": passe.isoformat()}}
    envoyer(alice, rappel, unique)
    envoyer_rappels_dus()
    r = Rappel.objects.get(id=rappel["id"])
    assert r.actif and r.prochaine_echeance > timezone.now()
    assert Rappel.objects.get(id=unique["id"]).actif is False


def test_recurrence_hebdomadaire_et_mensuelle():
    from zoneinfo import ZoneInfo

    from apps.elements.recurrence import suivante

    lundi = datetime(2026, 10, 12, 9, 0, tzinfo=ZoneInfo("Africa/Porto-Novo"))
    assert suivante(lundi, "HEBDOMADAIRE", ["LUNDI", "JEUDI"], "Africa/Porto-Novo").day == 15
    fin_janvier = datetime(2027, 1, 31, 9, 0, tzinfo=tz.utc)
    assert suivante(fin_janvier, "MENSUELLE", [], "UTC").day == 28


def test_purge_presse_papier(alice):
    from apps.comptes.models import PreferencesCompte
    from apps.elements.taches import purger_retention

    PreferencesCompte.objects.update(retention_presse_papier="H24")
    vieux, epingle, recent = element(type_="PRESSE_PAPIER"), element(type_="PRESSE_PAPIER", epingle=True), element(type_="PRESSE_PAPIER")
    envoyer(alice, vieux, epingle, recent)
    Element.objects.filter(id__in=[vieux["id"], epingle["id"]]).update(cree_le=timezone.now() - timedelta(days=2))
    purger_retention()
    assert Element.objects.get(id=vieux["id"]).supprime_le is not None
    assert Element.objects.get(id=epingle["id"]).supprime_le is None
    assert Element.objects.get(id=recent["id"]).supprime_le is None


def test_suppression_de_compte_echue(alice):
    from apps.comptes.taches import supprimer_comptes_echus

    envoyer(alice, element())
    Compte.objects.update(statut=StatutCompte.SUPPRESSION_PROGRAMMEE, suppression_prevue_le=timezone.now() - timedelta(seconds=1))
    supprimer_comptes_echus()
    assert not Compte.objects.filter(email="alice@exemple.test").exists() and Element.objects.count() == 0


def test_inactivite(alice):
    from apps.comptes.taches import gerer_inactivite

    Compte.objects.update(derniere_connexion_le=timezone.now() - timedelta(days=400))
    mail.outbox.clear()
    gerer_inactivite()
    assert Compte.objects.get().averti_inactivite_le is not None and len(mail.outbox) == 1
    Compte.objects.update(averti_inactivite_le=timezone.now() - timedelta(days=31))
    gerer_inactivite()
    assert not Compte.objects.exists()

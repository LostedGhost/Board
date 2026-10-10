"""Contrat 2.4 — compte, préférences, conditions."""

from unittest import mock

import pytest
from django.core import mail
from rest_framework.test import APIClient

from apps.appareils.models import Appareil, Session
from apps.appareils.tests_appareils import EMAIL, alice, cle_signature, telephone  # noqa: F401
from apps.comptes.models import Compte, IdentiteGoogle, StatutCompte
from apps.comptes.tests_inscription import MDP, conditions, dernier_code  # noqa: F401
from apps.conformite.models import TypeConditions, VersionConditions

pytestmark = pytest.mark.django_db


def test_get_compte(alice):
    r = alice.get("/api/v1/compte")
    assert r.status_code == 200
    assert r.json()["email"] == EMAIL and r.json()["conditionsAAccepter"] == []


def test_get_compte_accessible_a_un_appareil_non_deverrouille(telephone):
    assert telephone.get("/api/v1/compte").status_code == 200


def test_renommer_compte(alice):
    r = alice.patch("/api/v1/compte", {"nomAffichage": "Alice D."}, format="json")
    assert r.status_code == 200 and r.json()["nomAffichage"] == "Alice D."


def test_renommer_vide_refuse(alice):
    assert alice.patch("/api/v1/compte", {"nomAffichage": ""}, format="json").status_code == 422


# --- Mot de passe -------------------------------------------------------------------------


def test_changer_mot_de_passe_et_deconnecter_les_autres(alice, telephone):
    r = alice.post("/api/v1/compte/mot-de-passe", {"ancienMotDePasse": MDP, "nouveauMotDePasse": "Nouveau123", "deconnecterAutresAppareils": True}, format="json")
    assert r.status_code == 204
    assert Compte.objects.get(email=EMAIL).check_password("Nouveau123")
    assert Session.objects.count() == 1  # seule la session courante reste
    assert alice.get("/api/v1/compte").status_code == 200


def test_ancien_mot_de_passe_faux(alice):
    r = alice.post("/api/v1/compte/mot-de-passe", {"ancienMotDePasse": "Faux1234", "nouveauMotDePasse": "Nouveau123"}, format="json")
    assert r.status_code == 401


def test_nouveau_mot_de_passe_faible(alice):
    r = alice.post("/api/v1/compte/mot-de-passe", {"ancienMotDePasse": MDP, "nouveauMotDePasse": "faible"}, format="json")
    assert r.status_code == 422


# --- E-mail -------------------------------------------------------------------------------


def test_changer_email(alice):
    mail.outbox.clear()
    r = alice.post("/api/v1/compte/email", {"nouvelEmail": "alice2@exemple.test", "motDePasse": MDP}, format="json")
    assert r.status_code == 204
    destinataires = sorted(m.to[0] for m in mail.outbox)
    assert destinataires == ["alice2@exemple.test", EMAIL]  # code au nouveau, alerte à l'ancien
    code = next(m for m in mail.outbox if m.to == ["alice2@exemple.test"])
    import re

    valeur = re.search(r"\b(\d{6})\b", code.body).group(1)
    r = alice.post("/api/v1/compte/email/verifier", {"code": valeur}, format="json")
    assert r.status_code == 200 and r.json()["email"] == "alice2@exemple.test"


def test_changer_email_mot_de_passe_faux(alice):
    assert alice.post("/api/v1/compte/email", {"nouvelEmail": "x@exemple.test", "motDePasse": "Faux1234"}, format="json").status_code == 401


def test_changer_email_vers_une_adresse_prise(alice, conditions):
    Compte.objects.create_user("pris@exemple.test", "Pris", "Mdp12345A")
    r = alice.post("/api/v1/compte/email", {"nouvelEmail": "pris@exemple.test", "motDePasse": MDP}, format="json")
    assert r.status_code == 409


# --- Google -------------------------------------------------------------------------------


def test_lier_puis_delier_google(alice):
    with mock.patch("apps.comptes.gestion.verifier_id_token", return_value={"sujet": "g-9", "email": "a@gmail.test", "nom": "A"}):
        assert alice.post("/api/v1/compte/google", {"idTokenGoogle": "x"}, format="json").status_code == 204
        assert alice.post("/api/v1/compte/google", {"idTokenGoogle": "x"}, format="json").status_code == 409
    assert alice.get("/api/v1/compte").json()["googleLie"] is True
    assert alice.delete("/api/v1/compte/google").status_code == 204
    assert not IdentiteGoogle.objects.exists()


def test_impossible_de_delier_sans_mot_de_passe(alice):
    IdentiteGoogle.objects.create(compte=Compte.objects.get(email=EMAIL), sujet_google="g-1", email_google="a@gmail.test")
    compte = Compte.objects.get(email=EMAIL)
    compte.set_unusable_password()
    compte.save()
    assert alice.delete("/api/v1/compte/google").status_code == 409


# --- Suppression --------------------------------------------------------------------------


def test_programmer_la_suppression(alice):
    r = alice.delete("/api/v1/compte", {"motDePasse": MDP}, format="json")
    assert r.status_code == 200 and r.json()["suppressionPrevueLe"]
    assert Compte.objects.get(email=EMAIL).statut == StatutCompte.SUPPRESSION_PROGRAMMEE


def test_suppression_mot_de_passe_faux(alice):
    assert alice.delete("/api/v1/compte", {"motDePasse": "Faux1234"}, format="json").status_code == 401


# --- Préférences --------------------------------------------------------------------------


def test_preferences_compte(alice):
    r = alice.get("/api/v1/compte/preferences")
    assert r.json() == {"theme": "SYSTEME", "langue": "fr", "fuseauHoraire": "UTC", "retentionPressePapier": "J30", "retentionVersions": "INFINIE"}
    nouvelles = {"theme": "SOMBRE", "langue": "en", "fuseauHoraire": "Africa/Porto-Novo", "retentionPressePapier": "H24", "retentionVersions": "J7"}
    r = alice.put("/api/v1/compte/preferences", nouvelles, format="json")
    assert r.status_code == 200 and r.json() == nouvelles


def test_preferences_invalides(alice):
    base = {"theme": "SOMBRE", "langue": "fr", "fuseauHoraire": "Lune/Mer", "retentionPressePapier": "J7", "retentionVersions": "J7"}
    assert alice.put("/api/v1/compte/preferences", base, format="json").status_code == 422
    base.update(fuseauHoraire="UTC", retentionPressePapier="H1")  # 1 h : réservé aux versions
    assert alice.put("/api/v1/compte/preferences", base, format="json").status_code == 422


def test_preferences_appareil_et_jeton_push(alice):
    r = alice.get("/api/v1/appareils/courant/preferences")
    assert r.status_code == 200 and "SECURITE" in r.json()["notificationsActives"]
    corps = {
        "raccourciHistorique": "Ctrl+Alt+H",
        "raccourciCaptureRapide": "Ctrl+Alt+N",
        "demarrageAuto": False,
        "capturePressePapierEnPause": True,
        "notificationsActives": ["RAPPELS"],
        "verrouLocal": "CODE_PIN",
        "jetonPush": "jeton-fcm",
        "typePush": "FCM",
    }
    r = alice.put("/api/v1/appareils/courant/preferences", corps, format="json")
    assert r.status_code == 200
    assert sorted(r.json()["notificationsActives"]) == ["RAPPELS", "SECURITE"]  # sécurité toujours active
    assert "jetonPush" not in r.json()  # jamais renvoyé
    appareil = Appareil.objects.get(id=alice.appareil_id)
    assert appareil.jeton_push == "jeton-fcm" and appareil.type_push == "FCM"


# --- Conditions ---------------------------------------------------------------------------


def test_conditions_publiques(conditions):
    r = APIClient().get("/api/v1/conditions/actuelles")
    assert r.status_code == 200 and len(r.json()) == 2


def test_nouvelles_conditions_a_accepter(alice):
    v2 = VersionConditions.objects.create(type=TypeConditions.CONDITIONS_UTILISATION, numero="2.0", url_texte="https://exemple.test/v2")
    assert alice.get("/api/v1/appareils/courant/preferences").json()["erreur"]["code"] == "conditions_a_accepter"
    assert [c["numero"] for c in alice.get("/api/v1/compte").json()["conditionsAAccepter"]] == ["2.0"]
    assert alice.post("/api/v1/conditions/accepter", {"versionIds": [str(v2.id)]}, format="json").status_code == 204
    assert alice.get("/api/v1/appareils/courant/preferences").status_code == 200


def test_accepter_une_version_inconnue(alice):
    import uuid

    assert alice.post("/api/v1/conditions/accepter", {"versionIds": [str(uuid.uuid4())]}, format="json").status_code == 422


def test_suppression_possible_meme_avec_conditions_a_accepter(alice):
    VersionConditions.objects.create(type=TypeConditions.CONDITIONS_UTILISATION, numero="3.0", url_texte="https://exemple.test/v3")
    assert alice.delete("/api/v1/compte", {"motDePasse": MDP}, format="json").status_code == 200

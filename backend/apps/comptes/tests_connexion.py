"""Contrat 2.2 — connexion, déconnexion, mot de passe oublié (A2, A3, I26)."""

import pytest
from django.core import mail
from django.utils import timezone
from rest_framework.test import APIClient

from apps.appareils.models import Appareil, Session, StatutAppareil
from apps.comptes.models import Compte, StatutCompte
from apps.comptes.tests_inscription import (
    MDP,
    appareil,
    conditions,  # noqa: F401 (fixture)
    dernier_code,
    inscrire,
    verifier,
)

pytestmark = pytest.mark.django_db

EMAIL = "alice@exemple.test"


@pytest.fixture
def client():
    return APIClient()


@pytest.fixture
def alice(client, conditions):
    """Compte vérifié avec un premier appareil (ACTIF)."""
    inscrire(client, conditions)
    corps = verifier(client, dernier_code()).json()
    mail.outbox.clear()
    return corps


def connexion(client, mdp=MDP, email=EMAIL, app=None):
    return client.post(
        "/api/v1/auth/connexion",
        {"email": email, "motDePasse": mdp, "appareil": app or appareil("Téléphone")},
        format="json",
    )


# --- POST /auth/connexion -----------------------------------------------------------------


def test_connexion_nouvel_appareil_en_attente_de_deverrouillage(client, alice):
    r = connexion(client)
    assert r.status_code == 200 and r["Cache-Control"] == "no-store"
    assert r.json()["appareil"]["statut"] == StatutAppareil.EN_ATTENTE_DEVERROUILLAGE
    assert r.json()["session"]["jeton"]


def test_connexion_appareil_connu_garde_son_statut(client, alice):
    r = connexion(client, app={"appareilId": alice["appareil"]["id"]})
    assert r.status_code == 200
    assert r.json()["appareil"]["statut"] == StatutAppareil.ACTIF
    # La nouvelle session remplace l'ancienne : l'ancien jeton ne fonctionne plus.
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {alice['session']['jeton']}")
    assert client.post("/api/v1/auth/deconnexion").status_code == 401


def test_appareil_d_un_autre_compte_introuvable(client, alice, conditions):
    inscrire(client, conditions, email="bob@exemple.test")
    verifier(client, dernier_code(), email="bob@exemple.test")
    r = connexion(client, email="bob@exemple.test", app={"appareilId": alice["appareil"]["id"]})
    assert r.status_code == 404


def test_email_insensible_a_la_casse(client, alice):
    assert connexion(client, email="ALICE@Exemple.test").status_code == 200


def test_mauvais_mot_de_passe_et_email_inconnu_meme_reponse(client, alice):
    r1 = connexion(client, mdp="Mauvais123")
    r2 = connexion(client, email="inconnu@exemple.test")
    assert r1.status_code == r2.status_code == 401
    assert r1.json()["erreur"]["code"] == r2.json()["erreur"]["code"] == "identifiants_incorrects"
    assert r1.json()["erreur"]["message"] == r2.json()["erreur"]["message"]


def test_blocage_apres_cinq_echecs(client, alice):
    for _ in range(5):
        assert connexion(client, mdp="Mauvais123").status_code == 401
    r = connexion(client)  # même le bon mot de passe est refusé pendant le blocage
    assert r.status_code == 423 and r.json()["erreur"]["code"] == "connexion_bloquee"


def test_succes_remet_le_compteur_a_zero(client, alice):
    for _ in range(4):
        connexion(client, mdp="Mauvais123")
    assert connexion(client, app={"appareilId": alice["appareil"]["id"]}).status_code == 200
    for _ in range(4):
        assert connexion(client, mdp="Mauvais123").status_code == 401


def test_compte_google_seul_pas_de_connexion_par_mot_de_passe(client, conditions):
    from apps.comptes.tests_inscription import google

    google(client, conditions, email="bob@gmail.test")
    r = connexion(client, email="bob@gmail.test", mdp="")
    assert r.status_code == 422  # mot de passe vide refusé avant tout
    r = connexion(client, email="bob@gmail.test", mdp="NImporteQuoi1")
    assert r.status_code == 401


def test_compte_non_verifie_renvoie_un_code(client, conditions):
    inscrire(client, conditions)
    mail.outbox.clear()
    r = connexion(client)
    assert r.status_code == 403 and r.json()["erreur"]["code"] == "email_non_verifie"
    assert len(mail.outbox) == 1


def test_compte_non_verifie_mauvais_mot_de_passe_ne_revele_rien(client, conditions):
    inscrire(client, conditions)
    mail.outbox.clear()
    r = connexion(client, mdp="Mauvais123")
    assert r.status_code == 401 and len(mail.outbox) == 0


def test_compte_suspendu(client, alice):
    Compte.objects.update(statut=StatutCompte.SUSPENDU)
    r = connexion(client)
    assert r.status_code == 403 and r.json()["erreur"]["code"] == "compte_suspendu"


def test_limite_de_trois_appareils(client, alice):
    connexion(client, app=appareil("2"))
    connexion(client, app=appareil("3"))
    r = connexion(client, app=appareil("4"))
    assert r.status_code == 409 and r.json()["erreur"]["code"] == "limite_appareils"
    assert Appareil.objects.count() == 3


def test_appareil_revoque_libere_une_place_mais_ne_peut_plus_se_connecter(client, alice):
    connexion(client, app=appareil("2"))
    connexion(client, app=appareil("3"))
    Appareil.objects.filter(nom="2").update(statut=StatutAppareil.REVOQUE)
    assert connexion(client, app=appareil("4")).status_code == 200
    revoque = Appareil.objects.get(nom="2")
    r = connexion(client, app={"appareilId": str(revoque.id)})
    assert r.status_code == 403 and r.json()["erreur"]["code"] == "appareil_revoque"


def test_reconnexion_annule_la_suppression_programmee(client, alice):
    Compte.objects.update(statut=StatutCompte.SUPPRESSION_PROGRAMMEE, suppression_prevue_le=timezone.now())
    r = connexion(client, app={"appareilId": alice["appareil"]["id"]})
    assert r.status_code == 200
    compte = Compte.objects.get(email=EMAIL)
    assert compte.statut == StatutCompte.ACTIF and compte.suppression_prevue_le is None
    assert r.json()["compte"]["suppressionPrevueLe"] is None


# --- POST /auth/deconnexion ---------------------------------------------------------------


def test_deconnexion_supprime_la_session(client, alice):
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {alice['session']['jeton']}")
    assert client.post("/api/v1/auth/deconnexion").status_code == 204
    assert Session.objects.count() == 0
    assert client.post("/api/v1/auth/deconnexion").status_code == 401


def test_deconnexion_possible_appareil_non_deverrouille(client, alice):
    jeton = connexion(client).json()["session"]["jeton"]  # appareil EN_ATTENTE
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {jeton}")
    assert client.post("/api/v1/auth/deconnexion").status_code == 204


def test_deconnexion_sans_session(client):
    assert client.post("/api/v1/auth/deconnexion").status_code == 401


# --- Mot de passe oublié ------------------------------------------------------------------


def oubli(client, email=EMAIL):
    return client.post("/api/v1/auth/mot-de-passe/oubli", {"email": email}, format="json")


def reinitialiser(client, code, nouveau="NouveauMdp9", email=EMAIL):
    return client.post(
        "/api/v1/auth/mot-de-passe/reinitialiser",
        {"email": email, "code": code, "nouveauMotDePasse": nouveau},
        format="json",
    )


def test_oubli_toujours_204(client, alice):
    assert oubli(client, "inconnu@exemple.test").status_code == 204
    assert len(mail.outbox) == 0
    assert oubli(client).status_code == 204
    assert len(mail.outbox) == 1


def test_oubli_compte_non_verifie_aucun_mail(client, conditions):
    inscrire(client, conditions)
    mail.outbox.clear()
    assert oubli(client).status_code == 204 and len(mail.outbox) == 0


def test_reinitialisation_change_le_mot_de_passe_et_ferme_les_sessions(client, alice):
    connexion(client)  # deuxième appareil, deuxième session
    assert Session.objects.count() == 2
    oubli(client)
    assert reinitialiser(client, dernier_code()).status_code == 204
    assert Session.objects.count() == 0
    assert connexion(client, app={"appareilId": alice["appareil"]["id"]}, mdp="NouveauMdp9").status_code == 200
    assert connexion(client, app={"appareilId": alice["appareil"]["id"]}).status_code == 401


def test_reinitialisation_conserve_les_appareils_actifs(client, alice):
    oubli(client)
    reinitialiser(client, dernier_code())
    # A3 : l'appareil déjà déverrouillé garde sa clé locale ; il reste ACTIF.
    assert Appareil.objects.get(id=alice["appareil"]["id"]).statut == StatutAppareil.ACTIF


def test_reinitialisation_mot_de_passe_faible(client, alice):
    oubli(client)
    r = reinitialiser(client, dernier_code(), nouveau="faible")
    assert r.status_code == 422 and r.json()["erreur"]["champs"][0]["champ"] == "nouveauMotDePasse"


def test_reinitialisation_code_faux_puis_epuise(client, alice):
    oubli(client)
    bon = dernier_code()
    faux = "000000" if bon != "000000" else "111111"
    for _ in range(5):
        reinitialiser(client, faux)
    assert reinitialiser(client, bon).status_code == 410


def test_code_d_inscription_refuse_pour_la_reinitialisation(client, conditions):
    inscrire(client, conditions)
    code_inscription = dernier_code()
    verifier(client, code_inscription)
    assert reinitialiser(client, code_inscription).status_code == 422


def test_reinitialisation_leve_le_blocage(client, alice):
    for _ in range(5):
        connexion(client, mdp="Mauvais123")
    oubli(client)
    reinitialiser(client, dernier_code())
    assert connexion(client, app={"appareilId": alice["appareil"]["id"]}, mdp="NouveauMdp9").status_code == 200


def test_reinitialisation_email_inconnu(client):
    assert reinitialiser(client, "123456", email="inconnu@exemple.test").status_code == 422


def test_oubli_limite_par_email(client, alice):
    for _ in range(5):
        assert oubli(client).status_code == 204
    assert oubli(client).status_code == 429

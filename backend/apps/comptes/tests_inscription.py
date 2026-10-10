"""Contrat 2.1 — inscription, vérification, Google, confirmation de la clé de récupération."""

import os
import re
from datetime import timedelta
from unittest import mock

import pytest
from django.core import mail
from django.utils import timezone
from rest_framework.test import APIClient

from apps.appareils.models import Appareil, EnveloppeCle, Session, StatutAppareil
from apps.comptes.models import CodeVerification, Compte, StatutCompte
from apps.conformite.models import AcceptationConditions, TypeConditions, VersionConditions
from commun.b64 import encoder

pytestmark = pytest.mark.django_db

MDP = "MotDePasse1"


def cle32():
    return encoder(os.urandom(32))


def appareil(nom="PC de test"):
    return {"nom": nom, "type": "DESKTOP", "plateforme": "Windows 11", "versionApp": "0.1.0", "clePublique": cle32()}


def cles():
    return {
        "enveloppeRecuperation": encoder(os.urandom(72)),
        "enveloppeAppareil": encoder(os.urandom(80)),
        "clePubliqueVerification": cle32(),
    }


@pytest.fixture
def client():
    return APIClient()


@pytest.fixture
def conditions():
    return [
        VersionConditions.objects.create(type=TypeConditions.CONDITIONS_UTILISATION, numero="1.0", url_texte="https://exemple.test/cgu"),
        VersionConditions.objects.create(type=TypeConditions.POLITIQUE_CONFIDENTIALITE, numero="1.0", url_texte="https://exemple.test/pc"),
    ]


def ids(conditions):
    return [str(c.id) for c in conditions]


def inscrire(client, conditions, email="alice@exemple.test", mdp=MDP):
    return client.post(
        "/api/v1/auth/inscription",
        {"email": email, "nomAffichage": "Alice", "motDePasse": mdp, "conditionsAcceptees": ids(conditions)},
        format="json",
    )


def dernier_code():
    return re.search(r"\b(\d{6})\b", mail.outbox[-1].body).group(1)


def verifier(client, code, email="alice@exemple.test"):
    return client.post(
        "/api/v1/auth/inscription/verifier",
        {"email": email, "code": code, "appareil": appareil(), "cles": cles()},
        format="json",
    )


# --- POST /auth/inscription ---------------------------------------------------------------


def test_inscription_cree_un_compte_en_attente_et_envoie_un_code(client, conditions):
    r = inscrire(client, conditions)
    assert r.status_code == 201
    compte = Compte.objects.get(id=r.json()["compteId"])
    assert compte.statut == StatutCompte.EN_ATTENTE_VERIFICATION
    assert compte.check_password(MDP)
    assert compte.password.startswith("argon2")
    assert len(mail.outbox) == 1 and mail.outbox[0].to == ["alice@exemple.test"]
    assert AcceptationConditions.objects.filter(compte=compte).count() == 2
    # Le code n'est jamais stocké en clair.
    assert dernier_code() not in CodeVerification.objects.get(compte=compte).code_hash


@pytest.mark.parametrize("mdp", ["court1A", "sansmajuscule1", "SansChiffre"])
def test_mot_de_passe_faible_refuse(client, conditions, mdp):
    r = inscrire(client, conditions, mdp=mdp)
    assert r.status_code == 422
    assert r.json()["erreur"]["champs"] == [{"champ": "motDePasse", "raison": "trop_faible"}]


def test_email_invalide_refuse(client, conditions):
    r = inscrire(client, conditions, email="pas-un-email")
    assert r.status_code == 422
    assert r.json()["erreur"]["champs"][0]["champ"] == "email"


def test_conditions_obligatoires(client, conditions):
    r = client.post(
        "/api/v1/auth/inscription",
        {"email": "a@exemple.test", "nomAffichage": "A", "motDePasse": MDP, "conditionsAcceptees": [str(conditions[0].id)]},
        format="json",
    )
    assert r.status_code == 422
    assert r.json()["erreur"]["details"]["versionsManquantes"] == [str(conditions[1].id)]


def test_email_deja_utilise_insensible_a_la_casse(client, conditions):
    inscrire(client, conditions)
    verifier(client, dernier_code())
    r = inscrire(client, conditions, email="ALICE@exemple.test")
    assert r.status_code == 409
    assert r.json()["erreur"]["code"] == "email_deja_utilise"


def test_reinscription_d_un_compte_jamais_verifie(client, conditions):
    premier = inscrire(client, conditions).json()["compteId"]
    r = inscrire(client, conditions, mdp="AutreMotDePasse2")
    assert r.status_code == 201
    assert r.json()["compteId"] == premier
    assert Compte.objects.get(id=premier).check_password("AutreMotDePasse2")


def test_champ_inattendu_ignore_pas_d_affectation_massive(client, conditions):
    r = client.post(
        "/api/v1/auth/inscription",
        {"email": "m@exemple.test", "nomAffichage": "M", "motDePasse": MDP, "conditionsAcceptees": ids(conditions), "role": "ADMINISTRATEUR", "statut": "ACTIF"},
        format="json",
    )
    compte = Compte.objects.get(id=r.json()["compteId"])
    assert compte.role == "UTILISATEUR" and compte.statut == StatutCompte.EN_ATTENTE_VERIFICATION


# --- POST /auth/inscription/verifier ------------------------------------------------------


def test_verification_active_le_compte_et_ouvre_une_session(client, conditions):
    inscrire(client, conditions)
    r = verifier(client, dernier_code())
    assert r.status_code == 201
    assert r["Cache-Control"] == "no-store"
    corps = r.json()
    compte = Compte.objects.get(email="alice@exemple.test")
    assert compte.statut == StatutCompte.ACTIF and compte.email_verifie_le is not None
    assert compte.cle_publique_verification
    assert corps["appareil"]["statut"] == StatutAppareil.ACTIF and corps["appareil"]["courant"] is True
    assert corps["compte"]["cleRecuperationConfirmee"] is False
    assert EnveloppeCle.objects.filter(compte=compte).count() == 2
    # Le jeton n'est stocké que haché.
    assert not Session.objects.filter(jeton_hash=corps["session"]["jeton"]).exists()


def test_code_faux_compte_les_essais_puis_expire(client, conditions):
    inscrire(client, conditions)
    bon = dernier_code()
    faux = "000000" if bon != "000000" else "111111"
    r = verifier(client, faux)
    assert r.status_code == 422 and r.json()["erreur"]["details"]["essaisRestants"] == 4
    for _ in range(4):
        verifier(client, faux)
    r = verifier(client, bon)
    assert r.status_code == 410 and r.json()["erreur"]["code"] == "code_expire"


def test_code_expire(client, conditions):
    inscrire(client, conditions)
    CodeVerification.objects.update(expire_le=timezone.now() - timedelta(seconds=1))
    assert verifier(client, dernier_code()).status_code == 410


def test_email_inconnu_meme_reponse_qu_un_code_faux(client, conditions):
    r = verifier(client, "123456", email="inconnu@exemple.test")
    assert r.status_code == 422 and r.json()["erreur"]["code"] == "validation"


def test_compte_deja_verifie(client, conditions):
    inscrire(client, conditions)
    code = dernier_code()
    verifier(client, code)
    r = verifier(client, code)
    assert r.status_code == 409 and r.json()["erreur"]["code"] == "deja_traite"


def test_cle_publique_mal_formee(client, conditions):
    inscrire(client, conditions)
    a = appareil()
    a["clePublique"] = "pas-du-base64-valide!!"
    r = client.post(
        "/api/v1/auth/inscription/verifier",
        {"email": "alice@exemple.test", "code": dernier_code(), "appareil": a, "cles": cles()},
        format="json",
    )
    assert r.status_code == 422


# --- POST /auth/renvoyer-code -------------------------------------------------------------


def test_renvoyer_code_ne_revele_pas_l_existence_du_compte(client, conditions):
    r = client.post("/api/v1/auth/renvoyer-code", {"email": "inconnu@exemple.test", "type": "INSCRIPTION"}, format="json")
    assert r.status_code == 204 and len(mail.outbox) == 0


def test_renvoyer_code_invalide_l_ancien(client, conditions):
    inscrire(client, conditions)
    ancien = dernier_code()
    client.post("/api/v1/auth/renvoyer-code", {"email": "alice@exemple.test", "type": "INSCRIPTION"}, format="json")
    nouveau = dernier_code()
    if ancien != nouveau:
        assert verifier(client, ancien).status_code == 422
    assert verifier(client, nouveau).status_code == 201


def test_renvoyer_code_limite(client, conditions):
    corps = {"email": "x@exemple.test", "type": "INSCRIPTION"}
    for _ in range(5):
        assert client.post("/api/v1/auth/renvoyer-code", corps, format="json").status_code == 204
    r = client.post("/api/v1/auth/renvoyer-code", corps, format="json")
    assert r.status_code == 429 and r.json()["erreur"]["code"] == "trop_de_requetes"


# --- Session et confirmation de la clé de récupération ------------------------------------


def session_alice(client, conditions):
    inscrire(client, conditions)
    return verifier(client, dernier_code()).json()["session"]["jeton"]


def test_confirmer_cle_recuperation(client, conditions):
    jeton = session_alice(client, conditions)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {jeton}")
    assert client.post("/api/v1/compte/cle-recuperation/confirmer").status_code == 204
    assert Compte.objects.get(email="alice@exemple.test").cle_recuperation_confirmee_le is not None


def test_sans_jeton_401(client):
    r = client.post("/api/v1/compte/cle-recuperation/confirmer")
    assert r.status_code == 401 and r.json()["erreur"]["code"] == "non_authentifie"


def test_jeton_inconnu_401(client):
    client.credentials(HTTP_AUTHORIZATION="Bearer faux")
    assert client.post("/api/v1/compte/cle-recuperation/confirmer").status_code == 401


def test_session_expiree(client, conditions):
    jeton = session_alice(client, conditions)
    Session.objects.update(expire_le=timezone.now() - timedelta(seconds=1))
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {jeton}")
    r = client.post("/api/v1/compte/cle-recuperation/confirmer")
    assert r.status_code == 401 and r.json()["erreur"]["code"] == "session_expiree"


def test_appareil_revoque(client, conditions):
    jeton = session_alice(client, conditions)
    Appareil.objects.update(statut=StatutAppareil.REVOQUE)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {jeton}")
    r = client.post("/api/v1/compte/cle-recuperation/confirmer")
    assert r.status_code == 403 and r.json()["erreur"]["code"] == "appareil_revoque"


def test_compte_suspendu(client, conditions):
    jeton = session_alice(client, conditions)
    Compte.objects.update(statut=StatutCompte.SUSPENDU)
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {jeton}")
    assert client.post("/api/v1/compte/cle-recuperation/confirmer").json()["erreur"]["code"] == "compte_suspendu"


def test_version_app_trop_ancienne(client, conditions, settings):
    settings.MIN_APP_VERSION = "1.2.0"
    r = client.post("/api/v1/auth/renvoyer-code", {"email": "a@b.test", "type": "INSCRIPTION"}, format="json", HTTP_X_APP_VERSION="1.1.9")
    assert r.status_code == 426 and r.json()["erreur"]["code"] == "mise_a_jour_requise"


# --- Règles 🔐 (permission AppareilDeverrouille) -----------------------------------------


def test_regles_appareil_deverrouille(conditions):
    from rest_framework.test import APIRequestFactory, force_authenticate
    from rest_framework.views import APIView
    from rest_framework.response import Response

    from apps.appareils.permissions import AppareilDeverrouille

    class Protegee(APIView):
        permission_classes = [AppareilDeverrouille]

        def get(self, request):
            return Response({"ok": True})

    client = APIClient()
    jeton = session_alice(client, conditions)
    session = Session.objects.select_related("appareil__compte").get()
    fabrique = APIRequestFactory()

    def appel():
        requete = fabrique.get("/x", HTTP_AUTHORIZATION=f"Bearer {jeton}")
        return Protegee.as_view()(requete)

    # 1. Clé de récupération non confirmée (compte e-mail) → 403
    assert appel().data["erreur"]["code"] == "cle_recuperation_non_confirmee"
    Compte.objects.update(cle_recuperation_confirmee_le=timezone.now())
    assert appel().status_code == 200
    # 2. Nouvelles conditions publiées → 403
    VersionConditions.objects.create(type=TypeConditions.CONDITIONS_UTILISATION, numero="2.0", url_texte="https://exemple.test/cgu2")
    assert appel().data["erreur"]["code"] == "conditions_a_accepter"
    VersionConditions.objects.filter(numero="2.0").delete()
    # 3. Appareil non déverrouillé → 403
    Appareil.objects.update(statut=StatutAppareil.EN_ATTENTE_DEVERROUILLAGE)
    assert appel().data["erreur"]["code"] == "appareil_non_deverrouille"


# --- POST /auth/google --------------------------------------------------------------------


def google(client, conditions, sujet="g-1", email="bob@gmail.test", avec_cles=True, app=None):
    corps = {"idTokenGoogle": "jeton-de-test", "appareil": app or appareil(), "conditionsAcceptees": ids(conditions)}
    if avec_cles:
        corps["cles"] = cles()
    identite = {"sujet": sujet, "email": email, "nom": "Bob"}
    with mock.patch("apps.comptes.views.verifier_id_token", return_value=identite):
        return client.post("/api/v1/auth/google", corps, format="json")


def test_google_cree_un_compte(client, conditions):
    r = google(client, conditions)
    assert r.status_code == 200 and r.json()["nouveauCompte"] is True
    compte = Compte.objects.get(email="bob@gmail.test")
    assert compte.statut == StatutCompte.ACTIF and not compte.has_usable_password()
    assert r.json()["compte"]["googleLie"] is True
    # Compte Google : la confirmation de la clé peut être reportée (I4, option a).
    assert compte.cle_recuperation_obligatoire is False


def test_google_nouveau_compte_sans_cles_refuse(client, conditions):
    assert google(client, conditions, avec_cles=False).status_code == 422


def test_google_reconnexion_sur_nouvel_appareil_en_attente(client, conditions):
    google(client, conditions)
    r = google(client, conditions, avec_cles=False, app=appareil("Téléphone"))
    assert r.status_code == 200 and r.json()["nouveauCompte"] is False
    assert r.json()["appareil"]["statut"] == StatutAppareil.EN_ATTENTE_DEVERROUILLAGE


def test_google_limite_de_trois_appareils(client, conditions):
    google(client, conditions)
    google(client, conditions, avec_cles=False, app=appareil("2"))
    google(client, conditions, avec_cles=False, app=appareil("3"))
    r = google(client, conditions, avec_cles=False, app=appareil("4"))
    assert r.status_code == 409 and r.json()["erreur"]["code"] == "limite_appareils"
    assert len(r.json()["erreur"]["details"]["appareils"]) == 3


def test_google_ne_fusionne_pas_avec_un_compte_email(client, conditions):
    inscrire(client, conditions, email="bob@gmail.test")
    verifier(client, dernier_code(), email="bob@gmail.test")
    r = google(client, conditions)
    assert r.status_code == 409 and r.json()["erreur"]["code"] == "email_deja_utilise"


def test_google_suspendu(client, conditions):
    google(client, conditions)
    Compte.objects.update(statut=StatutCompte.SUSPENDU)
    r = google(client, conditions, avec_cles=False)
    assert r.status_code == 403 and r.json()["erreur"]["code"] == "compte_suspendu"


def test_google_jeton_invalide(client, conditions, settings):
    settings.GOOGLE_CLIENT_IDS = ["client-test"]
    with mock.patch("google.oauth2.id_token.verify_oauth2_token", side_effect=ValueError("mauvais")):
        r = client.post(
            "/api/v1/auth/google",
            {"idTokenGoogle": "x", "appareil": appareil(), "cles": cles(), "conditionsAcceptees": ids(conditions)},
            format="json",
        )
    assert r.status_code == 401


def test_google_mauvaise_audience(client, conditions, settings):
    settings.GOOGLE_CLIENT_IDS = ["client-test"]
    faux = {"aud": "autre-app", "iss": "accounts.google.com", "email_verified": True, "sub": "1", "email": "z@gmail.test"}
    with mock.patch("google.oauth2.id_token.verify_oauth2_token", return_value=faux):
        r = client.post(
            "/api/v1/auth/google",
            {"idTokenGoogle": "x", "appareil": appareil(), "cles": cles(), "conditionsAcceptees": ids(conditions)},
            format="json",
        )
    assert r.status_code == 401

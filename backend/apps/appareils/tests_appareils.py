"""Contrat 2.3 — appareils, déverrouillage, clé de récupération."""

import os

import pytest
from nacl.signing import SigningKey
from rest_framework.test import APIClient

from apps.appareils.models import Appareil, EnveloppeCle, MethodeEnveloppe, Session, StatutAppareil
from apps.comptes.models import Compte
from apps.comptes.tests_inscription import MDP, appareil, conditions, dernier_code, inscrire  # noqa: F401
from commun.b64 import decoder, encoder

pytestmark = pytest.mark.django_db

EMAIL = "alice@exemple.test"


def enveloppe():
    return encoder(os.urandom(72))


@pytest.fixture
def cle_signature():
    """Clé Ed25519 « dérivée de la clé maître » côté client."""
    return SigningKey.generate()


def client_avec(jeton):
    c = APIClient()
    c.credentials(HTTP_AUTHORIZATION=f"Bearer {jeton}")
    return c


@pytest.fixture
def alice(conditions, cle_signature):
    """Premier appareil ACTIF, clé de récupération confirmée. Renvoie le client authentifié."""
    c = APIClient()
    inscrire(c, conditions)
    r = c.post(
        "/api/v1/auth/inscription/verifier",
        {
            "email": EMAIL,
            "code": dernier_code(),
            "appareil": appareil("PC"),
            "cles": {
                "enveloppeRecuperation": enveloppe(),
                "enveloppeAppareil": enveloppe(),
                "clePubliqueVerification": encoder(bytes(cle_signature.verify_key)),
            },
        },
        format="json",
    )
    corps = r.json()
    pc = client_avec(corps["session"]["jeton"])
    pc.post("/api/v1/compte/cle-recuperation/confirmer")
    pc.appareil_id = corps["appareil"]["id"]
    return pc


@pytest.fixture
def telephone(alice):
    """Deuxième appareil, connecté mais EN_ATTENTE_DEVERROUILLAGE."""
    r = APIClient().post(
        "/api/v1/auth/connexion",
        {"email": EMAIL, "motDePasse": MDP, "appareil": appareil("Téléphone")},
        format="json",
    )
    tel = client_avec(r.json()["session"]["jeton"])
    tel.appareil_id = r.json()["appareil"]["id"]
    return tel


# --- Liste, renommage, révocation ---------------------------------------------------------


def test_liste_des_appareils(alice, telephone):
    r = alice.get("/api/v1/appareils")
    assert r.status_code == 200
    noms = {a["nom"]: a for a in r.json()}
    assert noms["PC"]["courant"] is True and noms["Téléphone"]["courant"] is False


def test_liste_accessible_a_un_appareil_non_deverrouille(telephone):
    assert telephone.get("/api/v1/appareils").status_code == 200


def test_renommer(alice):
    r = alice.patch(f"/api/v1/appareils/{alice.appareil_id}", {"nom": "Bureau"}, format="json")
    assert r.status_code == 200 and r.json()["nom"] == "Bureau"


def test_appareil_non_deverrouille_ne_peut_pas_renommer(telephone):
    r = telephone.patch(f"/api/v1/appareils/{telephone.appareil_id}", {"nom": "X"}, format="json")
    assert r.status_code == 403 and r.json()["erreur"]["code"] == "appareil_non_deverrouille"


def test_revocation(alice, telephone):
    assert alice.delete(f"/api/v1/appareils/{telephone.appareil_id}").status_code == 204
    tel = Appareil.objects.get(id=telephone.appareil_id)
    assert tel.statut == StatutAppareil.REVOQUE and tel.revoque_le is not None
    assert not Session.objects.filter(appareil=tel).exists()
    assert telephone.get("/api/v1/appareils").status_code == 401  # session supprimée
    assert len(alice.get("/api/v1/appareils").json()) == 1


def test_revocation_vide_l_enveloppe(alice, telephone, cle_signature):
    # Le téléphone est d'abord déverrouillé, puis révoqué.
    demande = telephone.post("/api/v1/appareils/courant/deverrouillage").json()
    alice.post(f"/api/v1/deverrouillages/{demande['id']}/approuver", {"codeAffiche": demande["codeAffiche"], "cleMaitreEnveloppee": enveloppe()}, format="json")
    alice.delete(f"/api/v1/appareils/{telephone.appareil_id}")
    env = EnveloppeCle.objects.get(appareil_id=telephone.appareil_id)
    assert env.invalidee_le is not None and bytes(env.cle_maitre_enveloppee) == b""


def test_revoquer_l_appareil_d_un_autre_compte(alice, conditions):
    c = APIClient()
    inscrire(c, conditions, email="bob@exemple.test")
    r = c.post(
        "/api/v1/auth/inscription/verifier",
        {"email": "bob@exemple.test", "code": dernier_code(), "appareil": appareil(), "cles": {"enveloppeRecuperation": enveloppe(), "enveloppeAppareil": enveloppe(), "clePubliqueVerification": encoder(os.urandom(32))}},
        format="json",
    )
    bob_appareil = r.json()["appareil"]["id"]
    assert alice.delete(f"/api/v1/appareils/{bob_appareil}").status_code == 404
    assert Appareil.objects.get(id=bob_appareil).statut == StatutAppareil.ACTIF


def test_enveloppe_de_l_appareil_courant(alice):
    r = alice.get("/api/v1/appareils/courant/enveloppe")
    assert r.status_code == 200 and len(decoder(r.json()["cleMaitreEnveloppee"])) == 72


def test_enveloppe_refusee_tant_que_non_deverrouille(telephone):
    assert telephone.get("/api/v1/appareils/courant/enveloppe").status_code == 403


# --- Déverrouillage par un autre appareil (I11) -------------------------------------------


def test_parcours_complet_de_deverrouillage(alice, telephone):
    demande = telephone.post("/api/v1/appareils/courant/deverrouillage")
    assert demande.status_code == 201
    code = demande.json()["codeAffiche"]
    assert len(code) == 6

    attente = alice.get("/api/v1/deverrouillages/en-attente").json()
    assert len(attente) == 1
    assert "codeAffiche" not in attente[0]  # le code n'est visible que sur le nouvel appareil
    assert attente[0]["clePubliqueDemandeur"]

    env = enveloppe()
    r = alice.post(f"/api/v1/deverrouillages/{attente[0]['id']}/approuver", {"codeAffiche": code, "cleMaitreEnveloppee": env}, format="json")
    assert r.status_code == 204
    assert Appareil.objects.get(id=telephone.appareil_id).statut == StatutAppareil.ACTIF
    assert telephone.get("/api/v1/appareils/courant/enveloppe").json()["cleMaitreEnveloppee"] == env


def test_mauvais_code_cinq_fois_refuse_la_demande(alice, telephone):
    demande = telephone.post("/api/v1/appareils/courant/deverrouillage").json()
    faux = "000000" if demande["codeAffiche"] != "000000" else "111111"
    url = f"/api/v1/deverrouillages/{demande['id']}/approuver"
    r = alice.post(url, {"codeAffiche": faux, "cleMaitreEnveloppee": enveloppe()}, format="json")
    assert r.status_code == 422 and r.json()["erreur"]["details"]["essaisRestants"] == 4
    for _ in range(4):
        alice.post(url, {"codeAffiche": faux, "cleMaitreEnveloppee": enveloppe()}, format="json")
    r = alice.post(url, {"codeAffiche": demande["codeAffiche"], "cleMaitreEnveloppee": enveloppe()}, format="json")
    assert r.status_code == 409


def test_un_appareil_ne_s_approuve_pas_lui_meme(alice, telephone):
    demande = telephone.post("/api/v1/appareils/courant/deverrouillage").json()
    # Le téléphone n'est pas ACTIF : il ne peut pas approuver (🔐).
    r = telephone.post(f"/api/v1/deverrouillages/{demande['id']}/approuver", {"codeAffiche": demande["codeAffiche"], "cleMaitreEnveloppee": enveloppe()}, format="json")
    assert r.status_code == 403


def test_refuser_revoque_l_appareil_demandeur(alice, telephone):
    demande = telephone.post("/api/v1/appareils/courant/deverrouillage").json()
    assert alice.post(f"/api/v1/deverrouillages/{demande['id']}/refuser").status_code == 204
    assert Appareil.objects.get(id=telephone.appareil_id).statut == StatutAppareil.REVOQUE


def test_nouvelle_demande_expire_l_ancienne(alice, telephone):
    premiere = telephone.post("/api/v1/appareils/courant/deverrouillage").json()
    telephone.post("/api/v1/appareils/courant/deverrouillage")
    r = alice.post(f"/api/v1/deverrouillages/{premiere['id']}/approuver", {"codeAffiche": premiere["codeAffiche"], "cleMaitreEnveloppee": enveloppe()}, format="json")
    assert r.status_code == 409


def test_demande_expiree(alice, telephone):
    from datetime import timedelta

    from django.utils import timezone

    from apps.appareils.models import DemandeDeverrouillage

    demande = telephone.post("/api/v1/appareils/courant/deverrouillage").json()
    DemandeDeverrouillage.objects.update(expire_le=timezone.now() - timedelta(seconds=1))
    assert alice.get("/api/v1/deverrouillages/en-attente").json() == []
    r = alice.post(f"/api/v1/deverrouillages/{demande['id']}/approuver", {"codeAffiche": demande["codeAffiche"], "cleMaitreEnveloppee": enveloppe()}, format="json")
    assert r.status_code == 410


def test_appareil_deja_actif_ne_cree_pas_de_demande(alice):
    assert alice.post("/api/v1/appareils/courant/deverrouillage").status_code == 409


# --- Déverrouillage par la clé de récupération --------------------------------------------


def test_deverrouillage_par_recuperation(telephone, cle_signature):
    r = telephone.get("/api/v1/compte/enveloppe-recuperation")
    assert r.status_code == 200 and r["Cache-Control"] == "no-store"
    defi = decoder(r.json()["defi"])
    signature = cle_signature.sign(defi).signature
    env = enveloppe()
    r = telephone.post(
        "/api/v1/appareils/courant/deverrouiller-par-recuperation",
        {"cleMaitreEnveloppee": env, "signatureDefi": encoder(signature)},
        format="json",
    )
    assert r.status_code == 204
    assert Appareil.objects.get(id=telephone.appareil_id).statut == StatutAppareil.ACTIF


def test_signature_fausse_refusee(telephone):
    defi = decoder(telephone.get("/api/v1/compte/enveloppe-recuperation").json()["defi"])
    autre = SigningKey.generate().sign(defi).signature
    r = telephone.post("/api/v1/appareils/courant/deverrouiller-par-recuperation", {"cleMaitreEnveloppee": enveloppe(), "signatureDefi": encoder(autre)}, format="json")
    assert r.status_code == 422
    assert Appareil.objects.get(id=telephone.appareil_id).statut == StatutAppareil.EN_ATTENTE_DEVERROUILLAGE


def test_defi_a_usage_unique(telephone, cle_signature):
    defi = decoder(telephone.get("/api/v1/compte/enveloppe-recuperation").json()["defi"])
    autre = SigningKey.generate().sign(defi).signature
    telephone.post("/api/v1/appareils/courant/deverrouiller-par-recuperation", {"cleMaitreEnveloppee": enveloppe(), "signatureDefi": encoder(autre)}, format="json")
    bonne = cle_signature.sign(defi).signature
    r = telephone.post("/api/v1/appareils/courant/deverrouiller-par-recuperation", {"cleMaitreEnveloppee": enveloppe(), "signatureDefi": encoder(bonne)}, format="json")
    assert r.status_code == 410  # rejouer un défi déjà utilisé est impossible


def test_sans_defi_prealable(telephone, cle_signature):
    sig = cle_signature.sign(b"x" * 32).signature
    r = telephone.post("/api/v1/appareils/courant/deverrouiller-par-recuperation", {"cleMaitreEnveloppee": enveloppe(), "signatureDefi": encoder(sig)}, format="json")
    assert r.status_code == 410


# --- Régénération de la clé de récupération (I15) -----------------------------------------


def test_regeneration(alice):
    ancienne = EnveloppeCle.objects.get(methode=MethodeEnveloppe.CLE_RECUPERATION)
    nouvelle = enveloppe()
    r = alice.put("/api/v1/compte/enveloppe-recuperation", {"motDePasse": MDP, "cleMaitreEnveloppee": nouvelle}, format="json")
    assert r.status_code == 204
    ancienne.refresh_from_db()
    assert ancienne.invalidee_le is not None and bytes(ancienne.cle_maitre_enveloppee) == b""
    actives = EnveloppeCle.objects.filter(methode=MethodeEnveloppe.CLE_RECUPERATION, invalidee_le__isnull=True)
    assert actives.count() == 1 and encoder(bytes(actives.get().cle_maitre_enveloppee)) == nouvelle
    # La nouvelle clé doit à son tour être confirmée comme sauvegardée.
    assert Compte.objects.get(email=EMAIL).cle_recuperation_confirmee_le is None


def test_regeneration_mauvais_mot_de_passe(alice):
    r = alice.put("/api/v1/compte/enveloppe-recuperation", {"motDePasse": "Mauvais123", "cleMaitreEnveloppee": enveloppe()}, format="json")
    assert r.status_code == 401


def test_regeneration_interdite_a_un_appareil_non_deverrouille(telephone):
    r = telephone.put("/api/v1/compte/enveloppe-recuperation", {"motDePasse": MDP, "cleMaitreEnveloppee": enveloppe()}, format="json")
    assert r.status_code == 403

"""Contrat 2.2 — connexion et mot de passe oublié (A2, A3, I26)."""

from django.contrib.auth.hashers import check_password, make_password
from django.db import transaction
from rest_framework import status

from apps.appareils.models import Session
from apps.appareils.services import connecter_appareil
from apps.comptes import codes
from apps.comptes.emails import envoyer_code
from apps.comptes.models import Compte, StatutCompte, TypeCode, normaliser_email
from commun import limitation
from commun.erreurs import ErreurApi

ECHECS_MAX = 5  # A2 : 5 échecs en 15 min → blocage 15 min
FENETRE_BLOCAGE_S = 15 * 60

# Hash factice : un e-mail inconnu coûte le même temps de calcul qu'un vrai compte
# (pas de déduction de l'existence d'un compte par la durée de réponse).
_HASH_FACTICE = None


def _hash_factice():
    global _HASH_FACTICE
    if _HASH_FACTICE is None:
        _HASH_FACTICE = make_password("mot-de-passe-factice")
    return _HASH_FACTICE


def _identifiants_incorrects():
    return ErreurApi("identifiants_incorrects", "E-mail ou mot de passe incorrect.", status.HTTP_401_UNAUTHORIZED)


def _verifier_blocage(email):
    if limitation.valeur("echecs_connexion", email) >= ECHECS_MAX:
        raise ErreurApi(
            "connexion_bloquee",
            "Trop de tentatives. Réessayez dans 15 minutes.",
            status.HTTP_423_LOCKED,
        )


def connecter(email, mot_de_passe, donnees_appareil, langue="fr"):
    """Renvoie (compte, appareil, jeton, expire_le) ou lève l'erreur du contrat."""
    email = normaliser_email(email)
    _verifier_blocage(email)

    compte = Compte.objects.filter(email=email).first()
    if compte is None:
        check_password(mot_de_passe, _hash_factice())
        limitation.compter("echecs_connexion", email, FENETRE_BLOCAGE_S)
        raise _identifiants_incorrects()

    if not compte.has_usable_password():  # compte Google seul : même coût de calcul
        check_password(mot_de_passe, _hash_factice())
        limitation.compter("echecs_connexion", email, FENETRE_BLOCAGE_S)
        raise _identifiants_incorrects()
    if not compte.check_password(mot_de_passe):
        limitation.compter("echecs_connexion", email, FENETRE_BLOCAGE_S)
        raise _identifiants_incorrects()

    if compte.statut == StatutCompte.EN_ATTENTE_VERIFICATION:
        # Mot de passe juste mais adresse jamais vérifiée : on renvoie un code.
        envoyer_code(compte.email, TypeCode.INSCRIPTION, codes.emettre_code(compte, TypeCode.INSCRIPTION), langue)
        raise ErreurApi(
            "email_non_verifie",
            "Adresse e-mail non vérifiée. Un nouveau code vous a été envoyé.",
            status.HTTP_403_FORBIDDEN,
            details={"codeEnvoye": True},
        )

    limitation.reinitialiser("echecs_connexion", email)
    appareil, jeton, expire_le = connecter_appareil(compte, donnees_appareil)
    return compte, appareil, jeton, expire_le


def deconnecter(session):
    Session.objects.filter(pk=session.pk).delete()


def demander_reinitialisation(email):
    """Renvoie (compte, code) si un code doit partir, sinon None. L'appelant répond toujours 204."""
    compte = Compte.objects.filter(email=normaliser_email(email)).exclude(
        statut=StatutCompte.EN_ATTENTE_VERIFICATION
    ).first()
    if compte is None:
        return None
    return compte, codes.emettre_code(compte, TypeCode.REINITIALISATION_MOT_DE_PASSE)


def reinitialiser_mot_de_passe(email, code, nouveau):
    """A3 : nouveau mot de passe, toutes les sessions fermées. Les données restent chiffrées."""
    compte = Compte.objects.filter(email=normaliser_email(email)).exclude(
        statut=StatutCompte.EN_ATTENTE_VERIFICATION
    ).first()
    if compte is None:
        raise codes.erreur_code_invalide()
    codes.consommer_code(compte, TypeCode.REINITIALISATION_MOT_DE_PASSE, code)
    with transaction.atomic():
        compte.set_password(nouveau)
        compte.save(update_fields=["password"])
        Session.objects.filter(appareil__compte=compte).delete()
    limitation.reinitialiser("echecs_connexion", compte.email)
    return compte

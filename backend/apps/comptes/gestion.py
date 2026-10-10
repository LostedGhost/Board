"""Contrat 2.4 — gestion du compte (A5, I13, I14, I16)."""

from datetime import timedelta

from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework import status

from apps.appareils.models import Session
from apps.comptes import codes
from apps.comptes.google import verifier_id_token
from apps.comptes.models import Compte, IdentiteGoogle, StatutCompte, TypeCode, normaliser_email
from commun.erreurs import ErreurApi

DELAI_GRACE_SUPPRESSION = timedelta(days=30)  # A5


def exiger_identite(compte, mot_de_passe=None, id_token_google=None):
    """Confirmation d'identité avant une action sensible : mot de passe, ou jeton Google si le compte n'en a pas."""
    if compte.has_usable_password():
        if not compte.check_password(mot_de_passe or ""):
            raise ErreurApi("identifiants_incorrects", "Mot de passe incorrect.", status.HTTP_401_UNAUTHORIZED)
        return
    identite = verifier_id_token(id_token_google or "")
    if not compte.google_lie or identite["sujet"] != compte.identite_google.sujet_google:
        raise ErreurApi("identifiants_incorrects", "Identité Google incorrecte.", status.HTTP_401_UNAUTHORIZED)


@transaction.atomic
def changer_mot_de_passe(compte, session_courante, ancien, nouveau, deconnecter_autres):
    if compte.has_usable_password() and not compte.check_password(ancien or ""):
        raise ErreurApi("identifiants_incorrects", "Mot de passe actuel incorrect.", status.HTTP_401_UNAUTHORIZED)
    compte.set_password(nouveau)
    compte.save(update_fields=["password"])
    if deconnecter_autres:
        Session.objects.filter(appareil__compte=compte).exclude(pk=session_courante.pk).delete()


def demander_changement_email(compte, nouvel_email, mot_de_passe, id_token_google=None):
    exiger_identite(compte, mot_de_passe, id_token_google)
    nouvel_email = normaliser_email(nouvel_email)
    if nouvel_email == compte.email:
        raise ErreurApi("validation", "C'est déjà votre adresse.", status.HTTP_422_UNPROCESSABLE_ENTITY,
                        champs=[{"champ": "nouvelEmail", "raison": "identique"}])
    if Compte.objects.filter(email=nouvel_email).exists():
        raise ErreurApi("email_deja_utilise", "Cette adresse est déjà utilisée.", status.HTTP_409_CONFLICT)
    return codes.emettre_code(compte, TypeCode.CHANGEMENT_EMAIL, nouvel_email=nouvel_email)


def confirmer_changement_email(compte, code):
    utilise = codes.consommer_code(compte, TypeCode.CHANGEMENT_EMAIL, code)
    ancien = compte.email
    compte.email = utilise.nouvel_email
    try:
        with transaction.atomic():
            compte.save(update_fields=["email"])
    except IntegrityError:
        raise ErreurApi("email_deja_utilise", "Cette adresse est déjà utilisée.", status.HTTP_409_CONFLICT)
    return ancien


def lier_google(compte, id_token):
    identite = verifier_id_token(id_token)
    if compte.google_lie:
        raise ErreurApi("deja_traite", "Un compte Google est déjà lié.", status.HTTP_409_CONFLICT)
    if IdentiteGoogle.objects.filter(sujet_google=identite["sujet"]).exists():
        raise ErreurApi("deja_traite", "Ce compte Google est déjà lié à un autre compte LuluBoard.", status.HTTP_409_CONFLICT)
    IdentiteGoogle.objects.create(compte=compte, sujet_google=identite["sujet"], email_google=identite["email"])


def delier_google(compte):
    if not compte.google_lie:
        raise ErreurApi("introuvable", "Aucun compte Google lié.", status.HTTP_404_NOT_FOUND)
    if not compte.has_usable_password():
        raise ErreurApi(
            "deja_traite",
            "Définissez d'abord un mot de passe, sinon vous ne pourrez plus vous connecter.",
            status.HTTP_409_CONFLICT,
        )
    compte.identite_google.delete()


def programmer_suppression(compte, mot_de_passe=None, id_token_google=None):
    exiger_identite(compte, mot_de_passe, id_token_google)
    compte.statut = StatutCompte.SUPPRESSION_PROGRAMMEE
    compte.suppression_prevue_le = timezone.now() + DELAI_GRACE_SUPPRESSION
    compte.save(update_fields=["statut", "suppression_prevue_le"])
    return compte.suppression_prevue_le

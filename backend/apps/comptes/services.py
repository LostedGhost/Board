"""Inscription par e-mail et par Google (contrat 2.1)."""

from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework import status

from apps.appareils.models import StatutAppareil
from apps.appareils.services import (
    connecter_appareil,
    creer_appareil,
    enregistrer_cles_initiales,
    ouvrir_session,
)
from apps.comptes import codes
from apps.comptes.models import (
    Compte,
    IdentiteGoogle,
    PreferencesCompte,
    StatutCompte,
    TypeCode,
    normaliser_email,
)
from apps.conformite.services import enregistrer_acceptations, ids_manquants
from commun.erreurs import ErreurApi


def exiger_conditions(version_ids):
    manquants = ids_manquants(version_ids or [])
    if manquants:
        raise ErreurApi(
            "validation",
            "Vous devez accepter les conditions d'utilisation en vigueur.",
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            champs=[{"champ": "conditionsAcceptees", "raison": "incompletes"}],
            details={"versionsManquantes": manquants},
        )


@transaction.atomic
def inscrire(email, nom_affichage, mot_de_passe, conditions):
    """Crée le compte EN_ATTENTE_VERIFICATION et renvoie (compte, code).

    Un compte jamais vérifié peut être réinscrit : ses informations sont remplacées.
    """
    exiger_conditions(conditions)
    email = normaliser_email(email)
    compte = Compte.objects.select_for_update().filter(email=email).first()
    if compte is not None and compte.statut != StatutCompte.EN_ATTENTE_VERIFICATION:
        raise ErreurApi("email_deja_utilise", "Cette adresse est déjà utilisée.", status.HTTP_409_CONFLICT)
    if compte is None:
        try:
            with transaction.atomic():
                compte = Compte.objects.create_user(email, nom_affichage, mot_de_passe)
        except IntegrityError:
            raise ErreurApi("email_deja_utilise", "Cette adresse est déjà utilisée.", status.HTTP_409_CONFLICT)
    else:
        compte.nom_affichage = nom_affichage
        compte.set_password(mot_de_passe)
        compte.save(update_fields=["nom_affichage", "password"])

    enregistrer_acceptations(compte, conditions)
    return compte, codes.emettre_code(compte, TypeCode.INSCRIPTION)


def compte_en_attente(email):
    return Compte.objects.filter(
        email=normaliser_email(email), statut=StatutCompte.EN_ATTENTE_VERIFICATION
    ).first()


def verifier_inscription(email, code, donnees_appareil, cles):
    """Valide le code, active le compte et son premier appareil, ouvre la session (A1)."""
    compte = Compte.objects.filter(email=normaliser_email(email)).first()
    if compte is None:
        raise codes.erreur_code_invalide()
    if compte.statut != StatutCompte.EN_ATTENTE_VERIFICATION:
        raise ErreurApi("deja_traite", "Ce compte est déjà vérifié. Connectez-vous.", status.HTTP_409_CONFLICT)

    codes.consommer_code(compte, TypeCode.INSCRIPTION, code)  # transaction propre (essais comptés)
    return _activer_compte(compte.id, donnees_appareil, cles)


@transaction.atomic
def _activer_compte(compte_id, donnees_appareil, cles):
    compte = Compte.objects.select_for_update().get(id=compte_id)
    if compte.statut != StatutCompte.EN_ATTENTE_VERIFICATION:
        raise ErreurApi("deja_traite", "Ce compte est déjà vérifié. Connectez-vous.", status.HTTP_409_CONFLICT)

    maintenant = timezone.now()
    compte.statut = StatutCompte.ACTIF
    compte.email_verifie_le = maintenant
    compte.derniere_connexion_le = maintenant
    compte.save(update_fields=["statut", "email_verifie_le", "derniere_connexion_le"])
    PreferencesCompte.objects.get_or_create(compte=compte)

    appareil = creer_appareil(compte, donnees_appareil, StatutAppareil.ACTIF)
    enregistrer_cles_initiales(compte, appareil, cles)
    jeton, expire_le = ouvrir_session(appareil)
    return compte, appareil, jeton, expire_le


@transaction.atomic
def connexion_google(identite, donnees_appareil, conditions, cles):
    """Connexion ou création de compte avec Google (A1b). Renvoie (compte, appareil, jeton, expire_le, nouveau)."""
    lien = IdentiteGoogle.objects.select_related("compte").filter(sujet_google=identite["sujet"]).first()
    if lien is not None:
        if "appareilId" not in donnees_appareil and "nom" not in donnees_appareil:
            raise ErreurApi("validation", "Appareil manquant.", status.HTTP_422_UNPROCESSABLE_ENTITY)
        appareil, jeton, expire_le = connecter_appareil(lien.compte, donnees_appareil)
        return lien.compte, appareil, jeton, expire_le, False

    email = normaliser_email(identite["email"])
    if Compte.objects.filter(email=email).exclude(statut=StatutCompte.EN_ATTENTE_VERIFICATION).exists():
        # Pas de fusion automatique : se connecter par mot de passe puis lier Google (I16).
        raise ErreurApi(
            "email_deja_utilise",
            "Un compte existe déjà avec cette adresse. Connectez-vous avec votre mot de passe, puis liez Google dans les réglages.",
            status.HTTP_409_CONFLICT,
        )
    if cles is None or "nom" not in donnees_appareil:
        raise ErreurApi(
            "validation",
            "Création de compte : appareil et clés initiales requis.",
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            champs=[{"champ": "cles", "raison": "requis"}],
        )
    exiger_conditions(conditions)

    # Un compte e-mail jamais vérifié avec la même adresse est remplacé.
    Compte.objects.filter(email=email, statut=StatutCompte.EN_ATTENTE_VERIFICATION).delete()
    maintenant = timezone.now()
    compte = Compte.objects.create_user(
        email, identite["nom"], None, statut=StatutCompte.ACTIF, email_verifie_le=maintenant
    )
    IdentiteGoogle.objects.create(compte=compte, sujet_google=identite["sujet"], email_google=identite["email"])
    PreferencesCompte.objects.create(compte=compte)
    enregistrer_acceptations(compte, conditions)

    appareil = creer_appareil(compte, donnees_appareil, StatutAppareil.ACTIF)
    enregistrer_cles_initiales(compte, appareil, cles)
    jeton, expire_le = ouvrir_session(appareil)
    return compte, appareil, jeton, expire_le, True


def confirmer_cle_recuperation(compte):
    if compte.cle_recuperation_confirmee_le is None:
        compte.cle_recuperation_confirmee_le = timezone.now()
        compte.save(update_fields=["cle_recuperation_confirmee_le"])

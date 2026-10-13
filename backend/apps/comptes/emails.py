"""E-mails transactionnels. Ne contiennent jamais de contenu utilisateur, seulement des codes et des alertes."""

from commun.courriels import envoyer_courriel

from apps.comptes.models import TypeCode

_SUJETS = {
    TypeCode.INSCRIPTION: {"fr": "Votre code LuluBoard", "en": "Your LuluBoard code"},
    TypeCode.REINITIALISATION_MOT_DE_PASSE: {
        "fr": "Réinitialisation de votre mot de passe LuluBoard",
        "en": "Reset your LuluBoard password",
    },
    TypeCode.CHANGEMENT_EMAIL: {"fr": "Confirmez votre nouvelle adresse", "en": "Confirm your new address"},
}

_TITRES = {
    TypeCode.INSCRIPTION: {"fr": "Bienvenue sur LuluBoard !", "en": "Welcome to LuluBoard!"},
    TypeCode.REINITIALISATION_MOT_DE_PASSE: {"fr": "Réinitialiser votre mot de passe", "en": "Reset your password"},
    TypeCode.CHANGEMENT_EMAIL: {"fr": "Confirmez votre nouvelle adresse", "en": "Confirm your new address"},
}

_TEXTES = {
    "fr": {
        "libelle": "Voici votre code :",
        "corps": "Saisissez-le dans l'application pour continuer. Il est valable 15 minutes.",
        "note": "Vous n'êtes pas à l'origine de cette demande ? Ignorez simplement ce message : rien ne sera modifié.",
    },
    "en": {
        "libelle": "Here is your code:",
        "corps": "Enter it in the app to continue. It is valid for 15 minutes.",
        "note": "Didn't request this? Just ignore this message: nothing will change.",
    },
}


def langue_de(request):
    entete = (request.headers.get("Accept-Language") or "").lower() if request else ""
    return "en" if entete.startswith("en") else "fr"


def envoyer_code(destinataire, type_code, code, langue="fr"):
    t = _TEXTES[langue]
    envoyer_courriel(
        destinataire,
        _SUJETS[type_code][langue],
        _TITRES[type_code][langue],
        [t["corps"]],
        code=code,
        libelle_code=t["libelle"],
        note=t["note"],
    )

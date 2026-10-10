"""E-mails transactionnels. Ne contiennent jamais de contenu utilisateur, seulement des codes et des alertes."""

from django.conf import settings
from django.core.mail import send_mail

from apps.comptes.models import TypeCode

_SUJETS = {
    TypeCode.INSCRIPTION: {"fr": "Votre code LuluBoard", "en": "Your LuluBoard code"},
    TypeCode.REINITIALISATION_MOT_DE_PASSE: {
        "fr": "Réinitialisation de votre mot de passe LuluBoard",
        "en": "Reset your LuluBoard password",
    },
    TypeCode.CHANGEMENT_EMAIL: {"fr": "Confirmez votre nouvelle adresse", "en": "Confirm your new address"},
}

_CORPS = {
    "fr": "Votre code : {code}\n\nIl est valable 15 minutes. Si vous n'êtes pas à l'origine de cette demande, ignorez ce message.",
    "en": "Your code: {code}\n\nIt is valid for 15 minutes. If you did not request it, ignore this message.",
}


def langue_de(request):
    entete = (request.headers.get("Accept-Language") or "").lower() if request else ""
    return "en" if entete.startswith("en") else "fr"


def envoyer_code(destinataire, type_code, code, langue="fr"):
    send_mail(
        subject=_SUJETS[type_code][langue],
        message=_CORPS[langue].format(code=code),
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[destinataire],
        fail_silently=False,
    )

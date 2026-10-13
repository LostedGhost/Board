"""Mise en forme commune des e-mails : version texte (toujours) et version HTML aux couleurs de LuluBoard."""

from django.conf import settings
from django.core.mail import EmailMultiAlternatives
from django.template.loader import render_to_string
from rest_framework import status

from commun.erreurs import ErreurApi


def envoyer_courriel(
    destinataire, sujet, titre, paragraphes, *, code=None, libelle_code="Voici votre code :", note=None, reponse_a=None, fail_silently=False
):
    """`paragraphes` : liste de textes (échappés dans le HTML). `code` : code à 6 chiffres mis en avant."""
    texte = "\n\n".join([titre, *([f"Code : {code}"] if code else []), *paragraphes, *([note] if note else [])])
    html = render_to_string(
        "courriels/base.html",
        {
            "titre": titre,
            "paragraphes": paragraphes,
            "code": code,
            "libelle_code": libelle_code,
            "note": note,
            "logo": settings.EMAIL_LOGO_URL,
            "site": settings.SITE_PUBLIC_URL,
        },
    )
    message = EmailMultiAlternatives(
        sujet, texte, settings.DEFAULT_FROM_EMAIL, [destinataire], reply_to=[reponse_a] if reponse_a else None
    )
    message.attach_alternative(html, "text/html")
    if fail_silently:
        return message.send(fail_silently=True)
    try:
        return message.send()
    except Exception as exc:  # fournisseur injoignable ou refus : détail dans les logs (commun.brevo)
        raise ErreurApi(
            "envoi_email_impossible",
            "Impossible d'envoyer l'e-mail pour le moment. Réessayez dans quelques minutes.",
            status.HTTP_503_SERVICE_UNAVAILABLE,
        ) from exc

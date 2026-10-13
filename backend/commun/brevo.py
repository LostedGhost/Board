"""Envoi des e-mails par l'API HTTP de Brevo.

Render (offre gratuite) bloque les ports SMTP sortants : on passe par HTTPS à la place.
Activé avec EMAIL_BACKEND=commun.brevo.BrevoEmailBackend et BREVO_API_KEY.
"""

import logging
from email.utils import parseaddr

import httpx
from django.conf import settings
from django.core.mail.backends.base import BaseEmailBackend

logger = logging.getLogger(__name__)

URL_API = "https://api.brevo.com/v3/smtp/email"


def _adresse(valeur):
    nom, email = parseaddr(valeur)
    return {"email": email, "name": nom} if nom else {"email": email}


class BrevoEmailBackend(BaseEmailBackend):
    def send_messages(self, email_messages):
        envoyes = 0
        for message in email_messages:
            try:
                self._envoyer(message)
                envoyes += 1
            except Exception:
                logger.exception("Échec de l'envoi Brevo à %s", message.to)
                if not self.fail_silently:
                    raise
        return envoyes

    def _envoyer(self, message):
        html = next((contenu for contenu, type_ in getattr(message, "alternatives", []) if type_ == "text/html"), None)
        donnees = {
            "sender": _adresse(message.from_email),
            "to": [_adresse(a) for a in message.to],
            "subject": message.subject,
            "textContent": message.body,
        }
        if html:
            donnees["htmlContent"] = html
        if message.reply_to:
            donnees["replyTo"] = _adresse(message.reply_to[0])
        reponse = httpx.post(
            URL_API,
            json=donnees,
            headers={"api-key": settings.BREVO_API_KEY, "accept": "application/json"},
            timeout=settings.EMAIL_TIMEOUT,
        )
        if reponse.status_code >= 300:
            raise RuntimeError(f"Brevo a refusé l'e-mail ({reponse.status_code}) : {reponse.text[:300]}")

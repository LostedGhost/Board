"""Interface de stockage et ses deux adaptateurs (ADR-006).

Le fournisseur est choisi à l'envoi par FILES_USE_DIRECT_TELEGRAM et mémorisé sur chaque fichier :
un fichier reste lisible même si la variable change ensuite.
"""

import hashlib
import logging

import httpx
from django.conf import settings

from apps.fichiers.models import FournisseurStockage

journal = logging.getLogger(__name__)

TAILLE_MORCEAU = 18 * 1024 * 1024  # < 20 Mo : limite de téléchargement de l'API Bot publique


class ErreurStockage(Exception):
    def __init__(self, message, reessayable=True):
        super().__init__(message)
        self.reessayable = reessayable


def fournisseur_actif():
    return FournisseurStockage.TELEGRAM_DIRECT if settings.FILES_USE_DIRECT_TELEGRAM else FournisseurStockage.LULUFILES


def _client(lecture_s=600):
    return httpx.Client(timeout=httpx.Timeout(connect=15, read=lecture_s, write=lecture_s, pool=30))


# --- Telegram direct ----------------------------------------------------------------------


class Telegram:
    def __init__(self):
        if not settings.TELEGRAM_BOT_TOKEN or not settings.TELEGRAM_CHANNEL_ID:
            raise ErreurStockage("Telegram non configuré.", reessayable=False)
        self.base = f"https://api.telegram.org/bot{settings.TELEGRAM_BOT_TOKEN}"
        self.base_fichiers = f"https://api.telegram.org/file/bot{settings.TELEGRAM_BOT_TOKEN}"
        self.canal = settings.TELEGRAM_CHANNEL_ID

    def _verifier(self, reponse):
        try:
            corps = reponse.json()
        except ValueError:
            corps = {}
        if reponse.status_code != 200 or not corps.get("ok"):
            # Jamais l'URL dans le message : elle contient le jeton du bot.
            raise ErreurStockage(f"Telegram a refusé l'opération ({reponse.status_code}).", reponse.status_code >= 429)
        return corps["result"]

    def envoyer_morceau(self, nom, octets):
        with _client() as c:
            r = c.post(
                f"{self.base}/sendDocument",
                data={"chat_id": self.canal, "disable_notification": "true"},
                files={"document": (nom, octets, "application/octet-stream")},
            )
        resultat = self._verifier(r)
        return resultat["message_id"], resultat["document"]["file_id"]

    def lire_morceau(self, file_id):
        with _client() as c:
            chemin = self._verifier(c.get(f"{self.base}/getFile", params={"file_id": file_id}))["file_path"]
            r = c.get(f"{self.base_fichiers}/{chemin}")
        if r.status_code != 200:
            raise ErreurStockage(f"Téléchargement Telegram impossible ({r.status_code}).")
        return r.content

    def supprimer_message(self, message_id):
        try:
            with _client(30) as c:
                c.post(f"{self.base}/deleteMessage", data={"chat_id": self.canal, "message_id": message_id})
        except httpx.HTTPError:
            journal.warning("Suppression d'un message Telegram impossible")


def sha256(octets):
    return hashlib.sha256(octets).hexdigest()


# --- LuluFiles (voir docs/integrations/lulufiles-brief.md) --------------------------------


class LuluFiles:
    def __init__(self):
        if not settings.LULUFILES_API_KEY:
            raise ErreurStockage("LuluFiles non configuré.", reessayable=False)
        self.base = settings.LULUFILES_BASE_URL.rstrip("/")
        self.entetes = {"X-API-Key": settings.LULUFILES_API_KEY}

    def _verifier(self, r):
        if r.status_code in (200, 201, 202):
            return r.json()
        try:
            erreur = r.json().get("error", {})
        except ValueError:
            erreur = {}
        reessayable = r.status_code == 503 or (r.status_code == 429 and not erreur.get("limite")) or r.status_code == 502
        journal.warning("LuluFiles %s %s (request_id=%s)", r.status_code, erreur.get("code"), erreur.get("request_id"))
        raise ErreurStockage(f"LuluFiles a refusé l'opération ({r.status_code} {erreur.get('code')}).", reessayable)

    def envoyer(self, chemin, nom):
        with open(chemin, "rb") as flux, _client() as c:
            r = c.post(f"{self.base}/files/upload", headers=self.entetes, files={"upload": (nom, flux, "application/octet-stream")})
        return self._verifier(r)

    def etat(self, id_lulufiles):
        with _client(30) as c:
            return self._verifier(c.get(f"{self.base}/files/{id_lulufiles}", headers=self.entetes))

    def lien_signe(self, id_lulufiles):
        with _client(30) as c:
            corps = self._verifier(
                c.post(f"{self.base}/files/{id_lulufiles}/link", headers=self.entetes, json={"disposition": "attachment"})
            )
        return self.base + corps["url"], corps["expires_at"]

    def flux(self, id_lulufiles, plage=None):
        """Lecture côté serveur (proxy), avec prise en charge de Range."""
        entetes = dict(self.entetes)
        if plage:
            entetes["Range"] = plage
        client = _client()
        requete = client.build_request("GET", f"{self.base}/files/{id_lulufiles}/download", headers=entetes)
        reponse = client.send(requete, stream=True)
        if reponse.status_code not in (200, 206):
            reponse.close()
            client.close()
            raise ErreurStockage(f"LuluFiles : lecture impossible ({reponse.status_code}).")
        return client, reponse

    def supprimer(self, id_lulufiles):
        with _client(30) as c:
            r = c.delete(f"{self.base}/files/{id_lulufiles}", headers=self.entetes, params={"permanent": "true"})
        if r.status_code not in (200, 404):
            self._verifier(r)

"""Contrat 2.6 — WebSocket temps réel.

Le jeton arrive dans le premier message (jamais dans l'URL, qui finit dans les journaux).
Le serveur ne pousse que des signaux sans contenu ; les données passent par HTTP.
"""

import asyncio

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer
from django.utils import timezone

from commun.evenements import groupe_compte

DELAI_AUTH_S = 10


@database_sync_to_async
def _session_valide(jeton):
    from apps.appareils.models import Session, StatutAppareil
    from apps.appareils.services import hacher_jeton
    from apps.comptes.models import StatutCompte

    session = (
        Session.objects.select_related("appareil", "appareil__compte")
        .filter(jeton_hash=hacher_jeton(jeton), expire_le__gt=timezone.now())
        .first()
    )
    if session is None:
        return None
    appareil = session.appareil
    if appareil.statut != StatutAppareil.ACTIF or appareil.compte.statut == StatutCompte.SUSPENDU:
        return None
    return str(appareil.compte_id), str(appareil.id)


class SynchroConsumer(AsyncJsonWebsocketConsumer):
    groupe = None
    appareil_id = None

    async def connect(self):
        await self.accept()
        self._minuteur = asyncio.get_event_loop().call_later(DELAI_AUTH_S, lambda: asyncio.ensure_future(self._expirer()))

    async def _expirer(self):
        if self.groupe is None:
            await self.close(code=4401)

    async def receive_json(self, contenu, **kwargs):
        if self.groupe is not None:
            if contenu.get("type") == "ping":
                await self.send_json({"type": "pong"})
            return
        if contenu.get("type") != "auth" or not isinstance(contenu.get("jeton"), str):
            await self.close(code=4401)
            return
        identite = await _session_valide(contenu["jeton"])
        if identite is None:
            await self.close(code=4401)
            return
        compte_id, self.appareil_id = identite
        self.groupe = groupe_compte(compte_id)
        await self.channel_layer.group_add(self.groupe, self.channel_name)
        self._minuteur.cancel()
        await self.send_json({"type": "pret"})

    async def evenement(self, message):
        evenement = message["evenement"]
        await self.send_json(evenement)
        if evenement.get("type") == "appareil_revoque" and evenement.get("appareilId") == self.appareil_id:
            await self.close(code=4403)

    async def disconnect(self, code):
        if self.groupe is not None:
            await self.channel_layer.group_discard(self.groupe, self.channel_name)
        minuteur = getattr(self, "_minuteur", None)
        if minuteur is not None:
            minuteur.cancel()

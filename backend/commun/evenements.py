"""Événements temps réel (contrat 2.6) : publiés vers le groupe WebSocket du compte.

Ils ne portent jamais de contenu, seulement des identifiants. Une panne de Redis
ne doit jamais faire échouer la requête qui publie : le client se resynchronise de toute façon.
"""

import logging

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.db import transaction

journal = logging.getLogger(__name__)


def groupe_compte(compte_id):
    return f"compte_{compte_id}"


def _envoyer(compte_id, type_evenement, donnees):
    try:
        couche = get_channel_layer()
        if couche is None:
            return
        async_to_sync(couche.group_send)(
            groupe_compte(compte_id),
            {"type": "evenement", "evenement": {"type": type_evenement, **donnees}},
        )
    except Exception:
        journal.warning("Publication d'événement impossible (%s)", type_evenement)


def publier(compte_id, type_evenement, **donnees):
    """Publie après validation de la transaction en cours (jamais un événement pour une écriture annulée)."""
    donnees = {k: (str(v) if v is not None and not isinstance(v, (int, bool, str)) else v) for k, v in donnees.items()}
    transaction.on_commit(lambda: _envoyer(compte_id, type_evenement, donnees))

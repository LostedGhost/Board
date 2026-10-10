"""Envois entre appareils (D1, H3) — diagramme de classes, diagramme 3."""

import uuid

from django.db import models

from apps.appareils.models import Appareil
from apps.comptes.models import Compte


class StatutEnvoi(models.TextChoices):
    EN_ATTENTE = "EN_ATTENTE"
    REMIS = "REMIS"
    EXPIRE = "EXPIRE"


class EnvoiAppareil(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    compte = models.ForeignKey(Compte, on_delete=models.CASCADE, related_name="envois")
    appareil_source = models.ForeignKey(Appareil, on_delete=models.CASCADE, related_name="envois_expedies")
    appareil_cible = models.ForeignKey(
        Appareil, on_delete=models.CASCADE, null=True, blank=True, related_name="envois_recus"
    )  # vide = tous mes autres appareils
    element_id = models.UUIDField(null=True, blank=True)
    contenu_chiffre = models.BinaryField(null=True, blank=True)
    statut = models.CharField(max_length=12, choices=StatutEnvoi.choices, default=StatutEnvoi.EN_ATTENTE)
    recupere_par = models.JSONField(default=list, blank=True)  # appareils ayant récupéré un envoi « à tous » (D28)
    envoye_le = models.DateTimeField(auto_now_add=True)
    recupere_le = models.DateTimeField(null=True, blank=True)
    expire_le = models.DateTimeField()

    class Meta:
        db_table = "envoi_appareil"
        indexes = [models.Index(fields=["compte", "statut"])]

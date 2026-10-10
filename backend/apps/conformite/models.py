"""Conditions d'utilisation et consentement — diagramme de classes, diagramme 4 (G4, I23)."""

import uuid

from django.db import models
from django.utils import timezone

from apps.comptes.models import Compte


class TypeConditions(models.TextChoices):
    CONDITIONS_UTILISATION = "CONDITIONS_UTILISATION"
    POLITIQUE_CONFIDENTIALITE = "POLITIQUE_CONFIDENTIALITE"


class VersionConditions(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    type = models.CharField(max_length=30, choices=TypeConditions.choices)
    numero = models.CharField(max_length=20)
    publiee_le = models.DateTimeField(default=timezone.now)
    url_texte = models.URLField()

    class Meta:
        db_table = "version_conditions"
        constraints = [models.UniqueConstraint(fields=["type", "numero"], name="version_conditions_unique")]

    def __str__(self):
        return f"{self.type} {self.numero}"


class AcceptationConditions(models.Model):
    compte = models.ForeignKey(Compte, on_delete=models.CASCADE, related_name="acceptations")
    version = models.ForeignKey(VersionConditions, on_delete=models.PROTECT, related_name="acceptations")
    acceptee_le = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "acceptation_conditions"
        constraints = [models.UniqueConstraint(fields=["compte", "version"], name="acceptation_unique")]

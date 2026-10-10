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


class Annonce(models.Model):
    """I30 : message court affiché dans toutes les apps."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    message_fr = models.CharField(max_length=500)
    message_en = models.CharField(max_length=500)
    debut_le = models.DateTimeField(default=timezone.now)
    fin_le = models.DateTimeField(null=True, blank=True)
    publiee_par = models.ForeignKey(Compte, on_delete=models.SET_NULL, null=True, blank=True, related_name="+")

    class Meta:
        db_table = "annonce"

    def __str__(self):
        return self.message_fr[:60]


class DemandeSupport(models.Model):
    """I22 : enregistrée en base ET envoyée par e-mail (décision validée)."""

    compte = models.ForeignKey(Compte, on_delete=models.SET_NULL, null=True, blank=True, related_name="demandes_support")
    email_contact = models.EmailField()
    message = models.TextField(max_length=5000)
    infos_techniques = models.TextField(max_length=5000, null=True, blank=True)
    cree_le = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "demande_support"

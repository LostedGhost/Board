"""Modération (I20, I24, I28) — diagramme de classes, diagramme 4. L'administrateur ne voit jamais de contenu."""

import uuid

from django.db import models

from apps.comptes.models import Compte
from apps.liens.models import LienPublic


class MotifSignalement(models.TextChoices):
    CONTENU_ILLICITE = "CONTENU_ILLICITE"
    ATTEINTE_DROIT_AUTEUR = "ATTEINTE_DROIT_AUTEUR"
    LOGICIEL_MALVEILLANT = "LOGICIEL_MALVEILLANT"
    HAMECONNAGE = "HAMECONNAGE"
    AUTRE = "AUTRE"


class StatutSignalement(models.TextChoices):
    OUVERT = "OUVERT"
    CLASSE_SANS_SUITE = "CLASSE_SANS_SUITE"
    LIEN_DESACTIVE = "LIEN_DESACTIVE"
    COMPTE_SUSPENDU = "COMPTE_SUSPENDU"


class Signalement(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    lien = models.ForeignKey(LienPublic, on_delete=models.CASCADE, related_name="signalements")
    motif = models.CharField(max_length=30, choices=MotifSignalement.choices)
    commentaire = models.TextField(null=True, blank=True)
    cree_le = models.DateTimeField(auto_now_add=True)
    statut = models.CharField(max_length=20, choices=StatutSignalement.choices, default=StatutSignalement.OUVERT)
    traite_le = models.DateTimeField(null=True, blank=True)
    traite_par = models.ForeignKey(Compte, on_delete=models.SET_NULL, null=True, blank=True, related_name="+")

    class Meta:
        db_table = "signalement"


class Suspension(models.Model):
    compte = models.ForeignKey(Compte, on_delete=models.CASCADE, related_name="suspensions")
    motif = models.TextField()
    debut_le = models.DateTimeField(auto_now_add=True)
    levee_le = models.DateTimeField(null=True, blank=True)
    decidee_par = models.ForeignKey(Compte, on_delete=models.SET_NULL, null=True, blank=True, related_name="+")
    signalement = models.ForeignKey(Signalement, on_delete=models.SET_NULL, null=True, blank=True, related_name="suspensions")

    class Meta:
        db_table = "suspension"

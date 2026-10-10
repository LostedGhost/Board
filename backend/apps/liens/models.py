"""Liens publics (E3, H4, I19, I21) — diagramme de classes, diagramme 3."""

import uuid

from django.db import models

from apps.comptes.models import Compte, DureeConservation
from apps.elements.models import Element


class LienPublic(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    compte = models.ForeignKey(Compte, on_delete=models.CASCADE, related_name="liens")
    element = models.ForeignKey(Element, on_delete=models.CASCADE, related_name="liens")
    jeton_hash = models.CharField(max_length=64, unique=True)
    protege_par_mot_de_passe = models.BooleanField(default=False)
    sel_derivation = models.BinaryField(null=True, blank=True)
    cle_element_enveloppee = models.BinaryField(null=True, blank=True)
    verificateur_mot_de_passe_hash = models.CharField(max_length=64, null=True, blank=True)
    duree = models.CharField(max_length=10, choices=DureeConservation.choices)
    expire_le = models.DateTimeField(null=True, blank=True)  # vide = durée infinie
    nb_telechargements = models.PositiveIntegerField(default=0)
    cree_le = models.DateTimeField(auto_now_add=True)
    revoque_le = models.DateTimeField(null=True, blank=True)
    desactive_par_admin_le = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "lien_public"

    def __str__(self):
        return f"Lien {self.id} ({self.element.type})"

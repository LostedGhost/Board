"""Fichiers — diagramme de classes, diagramme 3 (E1, E2)."""

from django.db import models

from apps.elements.models import Element


class FournisseurStockage(models.TextChoices):
    LULUFILES = "LULUFILES"
    TELEGRAM_DIRECT = "TELEGRAM_DIRECT"


class StatutFichier(models.TextChoices):
    EN_FILE = "EN_FILE"
    ENVOI_EN_COURS = "ENVOI_EN_COURS"
    PRET = "PRET"
    ECHEC = "ECHEC"


class Fichier(models.Model):
    """Complète l'élément de type FICHIER (même identifiant). Les octets sont déjà chiffrés par le client."""

    element = models.OneToOneField(Element, on_delete=models.CASCADE, primary_key=True, related_name="fichier")
    taille_octets = models.BigIntegerField()
    fournisseur = models.CharField(max_length=20, choices=FournisseurStockage.choices)  # figé à l'envoi (ADR-006)
    statut = models.CharField(max_length=20, choices=StatutFichier.choices, default=StatutFichier.EN_FILE)
    id_lulufiles = models.UUIDField(null=True, blank=True)
    message_erreur = models.TextField(null=True, blank=True)
    chemin_temporaire = models.TextField(null=True, blank=True)  # copie locale le temps du transfert
    cree_le = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "fichier"


class MorceauTelegram(models.Model):
    fichier = models.ForeignKey(Fichier, on_delete=models.CASCADE, related_name="morceaux")
    index = models.PositiveIntegerField()
    message_id = models.BigIntegerField()
    file_id_telegram = models.TextField()
    taille_octets = models.BigIntegerField()
    sha256 = models.CharField(max_length=64)

    class Meta:
        db_table = "morceau_telegram"
        ordering = ["index"]
        constraints = [models.UniqueConstraint(fields=["fichier", "index"], name="morceau_unique")]

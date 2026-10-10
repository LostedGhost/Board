"""Appareils, sessions et clés — diagramme de classes, diagramme 1."""

import uuid

from django.db import models
from django.utils import timezone

from apps.comptes.models import Compte

LIMITE_APPAREILS_ACTIFS = 3  # A4 / I11


class TypeAppareil(models.TextChoices):
    WEB = "WEB"
    MOBILE = "MOBILE"
    DESKTOP = "DESKTOP"


class StatutAppareil(models.TextChoices):
    EN_ATTENTE_DEVERROUILLAGE = "EN_ATTENTE_DEVERROUILLAGE"
    ACTIF = "ACTIF"
    REVOQUE = "REVOQUE"


class TypePush(models.TextChoices):
    FCM = "FCM"
    WEB_PUSH = "WEB_PUSH"


class MethodeEnveloppe(models.TextChoices):
    CLE_RECUPERATION = "CLE_RECUPERATION"
    APPAREIL = "APPAREIL"


class StatutDemande(models.TextChoices):
    EN_ATTENTE = "EN_ATTENTE"
    APPROUVEE = "APPROUVEE"
    REFUSEE = "REFUSEE"
    EXPIREE = "EXPIREE"


class CategorieNotification(models.TextChoices):
    RAPPELS = "RAPPELS"
    ENVOIS_APPAREILS = "ENVOIS_APPAREILS"
    NOUVEL_APPAREIL = "NOUVEL_APPAREIL"
    SECURITE = "SECURITE"


def notifications_par_defaut():
    return [c.value for c in CategorieNotification]


class VerrouLocal(models.TextChoices):
    AUCUN = "AUCUN"
    CODE_PIN = "CODE_PIN"
    BIOMETRIE = "BIOMETRIE"


class Appareil(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    compte = models.ForeignKey(Compte, on_delete=models.CASCADE, related_name="appareils")
    nom = models.CharField(max_length=100)
    type = models.CharField(max_length=10, choices=TypeAppareil.choices)
    plateforme = models.CharField(max_length=50)
    version_app = models.CharField(max_length=20)
    cle_publique = models.TextField()
    jeton_push = models.TextField(null=True, blank=True)
    type_push = models.CharField(max_length=10, choices=TypePush.choices, null=True, blank=True)
    statut = models.CharField(max_length=30, choices=StatutAppareil.choices)
    ajoute_le = models.DateTimeField(default=timezone.now)
    derniere_activite_le = models.DateTimeField(default=timezone.now)
    revoque_le = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "appareil"
        indexes = [models.Index(fields=["compte", "statut"])]

    def __str__(self):
        return f"{self.nom} ({self.type})"


class Session(models.Model):
    appareil = models.OneToOneField(Appareil, on_delete=models.CASCADE, related_name="session")
    jeton_hash = models.CharField(max_length=64, unique=True)
    derniere_activite_le = models.DateTimeField(default=timezone.now)
    expire_le = models.DateTimeField()

    class Meta:
        db_table = "session"


class EnveloppeCle(models.Model):
    compte = models.ForeignKey(Compte, on_delete=models.CASCADE, related_name="enveloppes")
    appareil = models.OneToOneField(
        Appareil, on_delete=models.CASCADE, null=True, blank=True, related_name="enveloppe"
    )
    methode = models.CharField(max_length=20, choices=MethodeEnveloppe.choices)
    cle_maitre_enveloppee = models.BinaryField()
    cree_le = models.DateTimeField(default=timezone.now)
    invalidee_le = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "enveloppe_cle"


class DemandeDeverrouillage(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    appareil = models.ForeignKey(Appareil, on_delete=models.CASCADE, related_name="demandes")
    approuvee_par = models.ForeignKey(
        Appareil, on_delete=models.SET_NULL, null=True, blank=True, related_name="approbations"
    )
    code_affiche = models.CharField(max_length=12)
    statut = models.CharField(max_length=12, choices=StatutDemande.choices, default=StatutDemande.EN_ATTENTE)
    expire_le = models.DateTimeField()

    class Meta:
        db_table = "demande_deverrouillage"


class PreferencesAppareil(models.Model):
    appareil = models.OneToOneField(Appareil, on_delete=models.CASCADE, related_name="preferences")
    raccourci_historique = models.CharField(max_length=40, default="Ctrl+Alt+B")
    raccourci_capture_rapide = models.CharField(max_length=40, default="Ctrl+Alt+N")
    demarrage_auto = models.BooleanField(default=True)
    capture_presse_papier_en_pause = models.BooleanField(default=False)
    notifications_actives = models.JSONField(default=notifications_par_defaut)
    verrou_local = models.CharField(max_length=10, choices=VerrouLocal.choices, default=VerrouLocal.AUCUN)

    class Meta:
        db_table = "preferences_appareil"

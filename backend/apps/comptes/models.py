"""Compte et données associées — diagramme de classes, diagramme 1."""

import uuid

from django.contrib.auth.base_user import AbstractBaseUser, BaseUserManager
from django.db import models
from django.utils import timezone


class RoleCompte(models.TextChoices):
    UTILISATEUR = "UTILISATEUR"
    ADMINISTRATEUR = "ADMINISTRATEUR"


class StatutCompte(models.TextChoices):
    EN_ATTENTE_VERIFICATION = "EN_ATTENTE_VERIFICATION"
    ACTIF = "ACTIF"
    SUSPENDU = "SUSPENDU"
    SUPPRESSION_PROGRAMMEE = "SUPPRESSION_PROGRAMMEE"


class Theme(models.TextChoices):
    CLAIR = "CLAIR"
    SOMBRE = "SOMBRE"
    SYSTEME = "SYSTEME"


class Langue(models.TextChoices):
    FR = "fr"
    EN = "en"


class DureeConservation(models.TextChoices):
    INFINIE = "INFINIE"
    J90 = "J90"
    J30 = "J30"
    J7 = "J7"
    H24 = "H24"
    H1 = "H1"
    MIN30 = "MIN30"


def normaliser_email(email):
    return (email or "").strip().lower()


class GestionnaireComptes(BaseUserManager):
    def create_user(self, email, nom_affichage, password=None, **extra):
        compte = self.model(email=normaliser_email(email), nom_affichage=nom_affichage, **extra)
        if password:
            compte.set_password(password)
        else:
            compte.set_unusable_password()
        compte.save(using=self._db)
        return compte

    def create_superuser(self, email, nom_affichage, password=None, **extra):
        """Administrateur de la plateforme (interface d'administration Django uniquement)."""
        extra.setdefault("role", RoleCompte.ADMINISTRATEUR)
        extra.setdefault("statut", StatutCompte.ACTIF)
        extra.setdefault("email_verifie_le", timezone.now())
        return self.create_user(email, nom_affichage, password, **extra)


class Compte(AbstractBaseUser):
    # Le mot de passe (motDePasseHash) est le champ `password` hérité, haché en Argon2.
    last_login = None  # remplacé par derniere_connexion_le

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(unique=True)
    nom_affichage = models.CharField(max_length=100)
    cle_publique_verification = models.TextField(blank=True, default="")
    role = models.CharField(max_length=20, choices=RoleCompte.choices, default=RoleCompte.UTILISATEUR)
    statut = models.CharField(max_length=30, choices=StatutCompte.choices, default=StatutCompte.EN_ATTENTE_VERIFICATION)
    email_verifie_le = models.DateTimeField(null=True, blank=True)
    cle_recuperation_confirmee_le = models.DateTimeField(null=True, blank=True)
    dernier_rappel_cle_le = models.DateTimeField(null=True, blank=True)
    derniere_connexion_le = models.DateTimeField(default=timezone.now)
    averti_inactivite_le = models.DateTimeField(null=True, blank=True)
    suppression_prevue_le = models.DateTimeField(null=True, blank=True)
    cree_le = models.DateTimeField(default=timezone.now)

    objects = GestionnaireComptes()

    USERNAME_FIELD = "email"
    EMAIL_FIELD = "email"
    REQUIRED_FIELDS = ["nom_affichage"]

    class Meta:
        db_table = "compte"

    def __str__(self):
        return self.email

    # --- Interface d'administration Django (ADR-003) ---
    @property
    def is_staff(self):
        return self.role == RoleCompte.ADMINISTRATEUR and self.statut == StatutCompte.ACTIF

    @property
    def is_active(self):
        return self.statut != StatutCompte.SUSPENDU

    def has_perm(self, perm, obj=None):
        return self.is_staff

    def has_module_perms(self, app_label):
        return self.is_staff

    # --- Règles métier ---
    @property
    def google_lie(self):
        return hasattr(self, "identite_google")

    @property
    def cle_recuperation_obligatoire(self):
        """A1 / I4 (option a) : obligatoire pour un compte e-mail, reportable pour un compte Google."""
        return self.cle_recuperation_confirmee_le is None and not self.google_lie


class IdentiteGoogle(models.Model):
    compte = models.OneToOneField(Compte, on_delete=models.CASCADE, related_name="identite_google")
    sujet_google = models.CharField(max_length=255, unique=True)
    email_google = models.EmailField()
    liee_le = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "identite_google"


class TypeCode(models.TextChoices):
    INSCRIPTION = "INSCRIPTION"
    REINITIALISATION_MOT_DE_PASSE = "REINITIALISATION_MOT_DE_PASSE"
    CHANGEMENT_EMAIL = "CHANGEMENT_EMAIL"


class CodeVerification(models.Model):
    compte = models.ForeignKey(Compte, on_delete=models.CASCADE, related_name="codes")
    type = models.CharField(max_length=40, choices=TypeCode.choices)
    code_hash = models.CharField(max_length=128)
    nouvel_email = models.EmailField(null=True, blank=True)
    tentatives = models.PositiveSmallIntegerField(default=0)
    expire_le = models.DateTimeField()
    utilise_le = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "code_verification"
        indexes = [models.Index(fields=["compte", "type"])]


class PreferencesCompte(models.Model):
    compte = models.OneToOneField(Compte, on_delete=models.CASCADE, related_name="preferences")
    theme = models.CharField(max_length=10, choices=Theme.choices, default=Theme.SYSTEME)
    langue = models.CharField(max_length=2, choices=Langue.choices, default=Langue.FR)
    fuseau_horaire = models.CharField(max_length=64, default="UTC")
    retention_presse_papier = models.CharField(
        max_length=10, choices=DureeConservation.choices, default=DureeConservation.J30
    )
    retention_versions = models.CharField(
        max_length=10, choices=DureeConservation.choices, default=DureeConservation.INFINIE
    )

    class Meta:
        db_table = "preferences_compte"

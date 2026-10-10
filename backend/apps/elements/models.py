"""Contenus du Board — diagramme de classes, diagramme 2.

Toutes ces entités sont synchronisées (contrat 2.5). Leurs identifiants sont générés par le
client (création hors ligne). Les rattachements (parent, source, étiquette) sont des UUID
simples, sans clé étrangère : un lot hors ligne peut arriver dans n'importe quel ordre.
"""

from django.db import models
from django.utils import timezone

from apps.appareils.models import Appareil
from apps.comptes.models import Compte


class CompteurSynchro(models.Model):
    """Compteur de version croissant, par compte (ADR-005)."""

    compte = models.OneToOneField(Compte, on_delete=models.CASCADE, primary_key=True, related_name="compteur_synchro")
    version = models.BigIntegerField(default=0)

    class Meta:
        db_table = "compteur_synchro"


class EntiteSynchronisee(models.Model):
    id = models.UUIDField(primary_key=True, editable=False)
    compte = models.ForeignKey(Compte, on_delete=models.CASCADE, related_name="+")
    version = models.BigIntegerField(db_index=True)
    modifie_le = models.DateTimeField()  # horodatage client : « la dernière modification gagne »
    supprime_le = models.DateTimeField(null=True, blank=True)

    class Meta:
        abstract = True


class TypeElement(models.TextChoices):
    PRESSE_PAPIER = "PRESSE_PAPIER"
    POST_IT = "POST_IT"
    SNIPPET = "SNIPPET"
    LISTE_TACHES = "LISTE_TACHES"
    TACHE = "TACHE"
    FICHIER = "FICHIER"


class TypeContenuPP(models.TextChoices):
    TEXTE = "TEXTE"
    LIEN = "LIEN"
    IMAGE = "IMAGE"


class Element(EntiteSynchronisee):
    type = models.CharField(max_length=20, choices=TypeElement.choices)
    parent_id = models.UUIDField(null=True, blank=True, db_index=True)  # tableau, liste ou tâche parente
    element_source_id = models.UUIDField(null=True, blank=True)  # H1 « créé depuis »
    epingle_acces_rapide = models.BooleanField(default=False)  # H8
    epingle = models.BooleanField(default=False)  # B4 (presse-papier)
    type_contenu = models.CharField(max_length=10, choices=TypeContenuPP.choices, null=True, blank=True)
    archive = models.BooleanField(default=False)  # C3 (post-it)
    appareil_auteur = models.ForeignKey(Appareil, on_delete=models.SET_NULL, null=True, blank=True, related_name="+")
    cle_element_enveloppee = models.BinaryField(null=True, blank=True)
    contenu_chiffre = models.BinaryField(null=True, blank=True)
    cree_le = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "element"
        indexes = [
            models.Index(fields=["compte", "version"]),
            models.Index(fields=["compte", "type", "supprime_le"]),
        ]


class Tableau(EntiteSynchronisee):
    contenu_chiffre = models.BinaryField(null=True, blank=True)

    class Meta:
        db_table = "tableau"
        indexes = [models.Index(fields=["compte", "version"])]


class Etiquette(EntiteSynchronisee):
    contenu_chiffre = models.BinaryField(null=True, blank=True)

    class Meta:
        db_table = "etiquette"
        indexes = [models.Index(fields=["compte", "version"])]


class ElementEtiquette(EntiteSynchronisee):
    element_id = models.UUIDField()
    etiquette_id = models.UUIDField()

    class Meta:
        db_table = "element_etiquette"
        indexes = [models.Index(fields=["compte", "version"])]


class Recurrence(models.TextChoices):
    QUOTIDIENNE = "QUOTIDIENNE"
    HEBDOMADAIRE = "HEBDOMADAIRE"
    MENSUELLE = "MENSUELLE"
    ANNUELLE = "ANNUELLE"


class JourSemaine(models.TextChoices):
    LUNDI = "LUNDI"
    MARDI = "MARDI"
    MERCREDI = "MERCREDI"
    JEUDI = "JEUDI"
    VENDREDI = "VENDREDI"
    SAMEDI = "SAMEDI"
    DIMANCHE = "DIMANCHE"


class Rappel(EntiteSynchronisee):
    """Lisible par le serveur (heure, récurrence) pour envoyer le push au bon moment ; le texte reste chiffré dans l'élément."""

    element_id = models.UUIDField(db_index=True)
    prochaine_echeance = models.DateTimeField()
    recurrence = models.CharField(max_length=15, choices=Recurrence.choices, null=True, blank=True)
    jours_semaine = models.JSONField(default=list, blank=True)
    fuseau_horaire = models.CharField(max_length=64, default="UTC")
    actif = models.BooleanField(default=True)

    class Meta:
        db_table = "rappel"
        indexes = [
            models.Index(fields=["compte", "version"]),
            models.Index(fields=["actif", "prochaine_echeance"]),
        ]


class VersionPostIt(EntiteSynchronisee):
    """Historique C3 : créé par le serveur à chaque modification acceptée (ou perdue) d'un post-it."""

    post_it_id = models.UUIDField(db_index=True)
    appareil_auteur = models.ForeignKey(Appareil, on_delete=models.SET_NULL, null=True, blank=True, related_name="+")
    contenu_chiffre = models.BinaryField(null=True, blank=True)
    cree_le = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "version_post_it"
        indexes = [models.Index(fields=["compte", "version"])]

"""Administration (ADR-003) : métadonnées uniquement, aucun contenu ni secret affiché."""

from django.contrib import admin

from apps.comptes.models import Compte


@admin.register(Compte)
class CompteAdmin(admin.ModelAdmin):
    list_display = ["email", "nom_affichage", "role", "statut", "derniere_connexion_le", "cree_le"]
    list_filter = ["role", "statut"]
    search_fields = ["email", "nom_affichage"]
    # Les secrets (hash du mot de passe, clé de vérification) ne sont jamais affichés.
    exclude = ["password", "cle_publique_verification"]
    readonly_fields = [
        "email",
        "email_verifie_le",
        "cle_recuperation_confirmee_le",
        "derniere_connexion_le",
        "suppression_prevue_le",
        "cree_le",
    ]

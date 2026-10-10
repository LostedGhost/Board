from django.contrib import admin

from apps.conformite.models import Annonce, DemandeSupport, VersionConditions


@admin.register(VersionConditions)
class VersionConditionsAdmin(admin.ModelAdmin):
    list_display = ["type", "numero", "publiee_le", "url_texte"]
    list_filter = ["type"]


@admin.register(Annonce)
class AnnonceAdmin(admin.ModelAdmin):
    list_display = ["message_fr", "debut_le", "fin_le"]
    exclude = ["publiee_par"]

    def save_model(self, request, obj, form, change):
        if not change:
            obj.publiee_par = request.user
        super().save_model(request, obj, form, change)


@admin.register(DemandeSupport)
class DemandeSupportAdmin(admin.ModelAdmin):
    list_display = ["cree_le", "email_contact"]
    readonly_fields = ["compte", "email_contact", "message", "infos_techniques", "cree_le"]

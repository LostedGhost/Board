from django.contrib import admin

from apps.conformite.models import VersionConditions


@admin.register(VersionConditions)
class VersionConditionsAdmin(admin.ModelAdmin):
    list_display = ["type", "numero", "publiee_le", "url_texte"]
    list_filter = ["type"]

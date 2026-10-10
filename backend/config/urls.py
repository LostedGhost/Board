from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/", include("apps.sante.urls")),
    path("api/v1/", include("apps.comptes.urls")),
    path("api/v1/", include("apps.appareils.urls")),
    path("api/v1/", include("apps.comptes.urls_compte")),
    path("api/v1/", include("apps.synchro.urls")),
    path("api/v1/", include("apps.fichiers.urls")),
]

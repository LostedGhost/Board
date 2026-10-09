from django.urls import path

from apps.sante.views import SanteView

urlpatterns = [
    path("health", SanteView.as_view(), name="health"),
]

from django.urls import path

from apps.conformite import views

urlpatterns = [
    path("annonces/actives", views.AnnoncesActivesView.as_view()),
    path("support", views.SupportView.as_view()),
    path("export", views.ExportView.as_view()),
]

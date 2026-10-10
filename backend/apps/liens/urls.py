from django.urls import path

from apps.liens import views

urlpatterns = [
    path("liens", views.LiensView.as_view()),
    path("liens/<uuid:lien_id>", views.LienView.as_view()),
    path("public/liens/<str:jeton>", views.PublicLienView.as_view()),
    path("public/liens/<str:jeton>/deverrouiller", views.PublicDeverrouillerView.as_view()),
    path("public/liens/<str:jeton>/fichier", views.PublicFichierView.as_view()),
    path("public/liens/<str:jeton>/signalements", views.PublicSignalementView.as_view()),
]

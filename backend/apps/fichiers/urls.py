from django.urls import path

from apps.fichiers import views

urlpatterns = [
    path("fichiers", views.FichiersView.as_view()),
    path("fichiers/<uuid:fichier_id>", views.FichierView.as_view()),
    path("fichiers/<uuid:fichier_id>/acces", views.AccesView.as_view()),
    path("fichiers/<uuid:fichier_id>/contenu", views.ContenuView.as_view()),
    path("fichiers/<uuid:fichier_id>/reessayer", views.ReessayerView.as_view()),
]

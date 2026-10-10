from django.urls import path

from apps.comptes import views

urlpatterns = [
    path("auth/inscription", views.InscriptionView.as_view()),
    path("auth/renvoyer-code", views.RenvoyerCodeView.as_view()),
    path("auth/inscription/verifier", views.VerificationView.as_view()),
    path("auth/google", views.GoogleView.as_view()),
    path("auth/connexion", views.ConnexionView.as_view()),
    path("auth/deconnexion", views.DeconnexionView.as_view()),
    path("auth/mot-de-passe/oubli", views.OubliMotDePasseView.as_view()),
    path("auth/mot-de-passe/reinitialiser", views.ReinitialisationView.as_view()),
    path("compte/cle-recuperation/confirmer", views.ConfirmerCleRecuperationView.as_view()),
]

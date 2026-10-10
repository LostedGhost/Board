from django.urls import path

from apps.appareils import views

urlpatterns = [
    path("appareils", views.ListeAppareilsView.as_view()),
    path("appareils/courant/enveloppe", views.EnveloppeCouranteView.as_view()),
    path("appareils/courant/deverrouillage", views.DemandeCouranteView.as_view()),
    path("appareils/courant/deverrouiller-par-recuperation", views.DeverrouillerParRecuperationView.as_view()),
    path("appareils/<uuid:appareil_id>", views.AppareilView.as_view()),
    path("deverrouillages/en-attente", views.DemandesEnAttenteView.as_view()),
    path("deverrouillages/<uuid:demande_id>/approuver", views.ApprouverView.as_view()),
    path("deverrouillages/<uuid:demande_id>/refuser", views.RefuserView.as_view()),
    path("compte/enveloppe-recuperation", views.EnveloppeRecuperationView.as_view()),
]

from django.urls import path

from apps.synchro import views

urlpatterns = [
    path("synchro/changements", views.ChangementsView.as_view()),
    path("synchro/envoyer", views.EnvoyerView.as_view()),
]

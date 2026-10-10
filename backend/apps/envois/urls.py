from django.urls import path

from apps.envois import views

urlpatterns = [
    path("envois", views.EnvoisView.as_view()),
    path("envois/recus", views.RecusView.as_view()),
    path("envois/<uuid:envoi_id>/recupere", views.RecupereView.as_view()),
]

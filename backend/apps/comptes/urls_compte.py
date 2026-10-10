from django.urls import path

from apps.comptes import views_compte as v

urlpatterns = [
    path("compte", v.CompteView.as_view()),
    path("compte/mot-de-passe", v.MotDePasseView.as_view()),
    path("compte/email", v.EmailView.as_view()),
    path("compte/email/verifier", v.EmailVerificationView.as_view()),
    path("compte/google", v.GoogleLiaisonView.as_view()),
    path("compte/preferences", v.PreferencesCompteView.as_view()),
    path("appareils/courant/preferences", v.PreferencesAppareilView.as_view()),
    path("conditions/actuelles", v.ConditionsActuellesView.as_view()),
    path("conditions/accepter", v.AccepterConditionsView.as_view()),
]

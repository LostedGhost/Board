"""Authentification par jeton de session opaque (contrat, section 1).

`Authorization: Bearer <jeton>` → request.user = Compte, request.auth = Session.
"""

from datetime import timedelta

from django.utils import timezone
from rest_framework import authentication, status

from apps.appareils.models import Session, StatutAppareil
from apps.appareils.services import DUREE_SESSION, hacher_jeton
from apps.comptes.models import StatutCompte
from commun.erreurs import ErreurApi

# Pour limiter les écritures, l'expiration glissante n'est prolongée qu'une fois par minute.
INTERVALLE_PROLONGATION = timedelta(minutes=1)


class AuthentificationSession(authentication.BaseAuthentication):
    keyword = "Bearer"

    def authenticate(self, request):
        entete = request.headers.get("Authorization", "")
        if not entete:
            return None
        morceaux = entete.split()
        if len(morceaux) != 2 or morceaux[0] != self.keyword:
            raise ErreurApi("non_authentifie", "Authentification requise.", status.HTTP_401_UNAUTHORIZED)

        session = (
            Session.objects.select_related("appareil", "appareil__compte")
            .filter(jeton_hash=hacher_jeton(morceaux[1]))
            .first()
        )
        if session is None:
            raise ErreurApi("non_authentifie", "Authentification requise.", status.HTTP_401_UNAUTHORIZED)

        maintenant = timezone.now()
        if session.expire_le <= maintenant:
            session.delete()
            raise ErreurApi("session_expiree", "Session expirée. Reconnectez-vous.", status.HTTP_401_UNAUTHORIZED)

        appareil = session.appareil
        compte = appareil.compte
        if appareil.statut == StatutAppareil.REVOQUE:
            raise ErreurApi("appareil_revoque", "Cet appareil a été révoqué.", status.HTTP_403_FORBIDDEN)
        if compte.statut == StatutCompte.SUSPENDU:
            raise ErreurApi("compte_suspendu", "Ce compte est suspendu.", status.HTTP_403_FORBIDDEN)

        if maintenant - session.derniere_activite_le >= INTERVALLE_PROLONGATION:
            session.derniere_activite_le = maintenant
            session.expire_le = maintenant + DUREE_SESSION
            session.save(update_fields=["derniere_activite_le", "expire_le"])
            appareil.derniere_activite_le = maintenant
            appareil.save(update_fields=["derniere_activite_le"])

        request.appareil = appareil
        return compte, session

    def authenticate_header(self, request):
        return self.keyword


try:  # Description de l'authentification dans le schéma OpenAPI
    from drf_spectacular.extensions import OpenApiAuthenticationExtension

    class SchemaAuthentificationSession(OpenApiAuthenticationExtension):
        target_class = "apps.appareils.authentification.AuthentificationSession"
        name = "session"

        def get_security_definition(self, auto_schema):
            return {"type": "http", "scheme": "bearer", "description": "Jeton de session opaque"}
except ImportError:  # pragma: no cover
    pass

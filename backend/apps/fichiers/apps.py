from django.apps import AppConfig


class FichiersConfig(AppConfig):
    name = "apps.fichiers"
    label = "fichiers"

    def ready(self):
        # Enregistre le crochet de suppression auprès du moteur de synchronisation.
        from apps.fichiers import services  # noqa: F401

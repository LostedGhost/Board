from django.apps import AppConfig


class LiensConfig(AppConfig):
    name = "apps.liens"
    label = "liens"

    def ready(self):
        from apps.liens import services  # noqa: F401  (crochet de suppression)

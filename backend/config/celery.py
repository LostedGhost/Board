"""Tâches de fond (ADR-003) : transferts de fichiers, rappels, purges, expirations."""

import os

from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

app = Celery("luluboard")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks(related_name="taches")

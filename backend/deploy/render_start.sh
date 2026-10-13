#!/usr/bin/env bash
# Démarrage du service web sur Render (voir ../../render.yaml).
# Les migrations passent au démarrage : l'offre gratuite n'a pas d'étape « pre-deploy ».
set -euo pipefail
uv run --no-sync python manage.py migrate --noinput

# Premier administrateur pour /admin/, créé une seule fois à partir de DJANGO_SUPERUSER_EMAIL/PASSWORD.
if [ -n "${DJANGO_SUPERUSER_EMAIL:-}" ] && [ -n "${DJANGO_SUPERUSER_PASSWORD:-}" ]; then
  uv run --no-sync python manage.py createsuperuser --noinput || echo "Administrateur non créé (déjà existant ?)"
fi

# Worker Celery + planificateur (rappels, rétention, suppressions) dans le même conteneur :
# pas de service séparé à payer. Les .delay() du web restent immédiats (CELERY_TASK_ALWAYS_EAGER).
uv run --no-sync celery -A config worker --beat --concurrency=1 --loglevel=INFO &

exec uv run --no-sync uvicorn config.asgi:application --host 0.0.0.0 --port "${PORT:-8000}" --proxy-headers --forwarded-allow-ips='*'

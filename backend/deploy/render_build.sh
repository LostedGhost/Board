#!/usr/bin/env bash
# Build du service web sur Render (voir ../../render.yaml).
set -euo pipefail
pip install --quiet uv
uv sync --frozen --no-dev
uv run --no-sync python manage.py collectstatic --noinput

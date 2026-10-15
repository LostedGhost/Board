#!/usr/bin/env bash
# Build de l'app Flutter Web sur Render (voir ../../render.yaml).
# Render n'a pas Flutter : le SDK est téléchargé dans le cache de build, puis réutilisé.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.7}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/flutter-${FLUTTER_VERSION}"

if [ ! -x "$CACHE/flutter/bin/flutter" ]; then
  rm -rf "$CACHE" && mkdir -p "$CACHE"
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C "$CACHE"
fi
export PATH="$CACHE/flutter/bin:$PATH"
git config --global --add safe.directory "$CACHE/flutter"

flutter config --no-analytics >/dev/null
flutter pub get
# --no-web-resources-cdn : CanvasKit est servi par notre site, pas par gstatic.com (même logique que D52).
flutter build web --release --no-web-resources-cdn --dart-define=API_URL="${API_URL:?API_URL manquante}" --dart-define=SITE_URL="${SITE_URL:?SITE_URL manquante}"

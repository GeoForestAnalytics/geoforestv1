#!/bin/bash
# Build de produção do APK GeoForest (equivalente Mac/Linux do build_prod.bat)
#
# Uso (uma vez só):
#   cp .env.example .env
#   # edite o .env e preencha as chaves
#   ./build_prod.sh
#
# Ou sem .env, passando na hora:
#   OPENWEATHER_API_KEY="sua_chave" MAPBOX_ACCESS_TOKEN="seu_token" ./build_prod.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Lendo chaves de .env..."
  set -a
  source "$SCRIPT_DIR/.env"
  set +a
fi

echo "Iniciando Build do APK GeoForest..."

if [ -z "$OPENWEATHER_API_KEY" ]; then
  echo "AVISO: variável de ambiente OPENWEATHER_API_KEY não definida (clima não vai funcionar nesse build)."
fi
if [ -z "$MAPBOX_ACCESS_TOKEN" ]; then
  echo "AVISO: variável de ambiente MAPBOX_ACCESS_TOKEN não definida (camada de satélite Mapbox vai cair no fallback)."
fi

flutter build apk --release \
  --dart-define=RECAPTCHA_SITE_KEY=6LdafxgsAAAAAInBOeFOrNJR3l-4gUCzdry_XELi \
  --dart-define=OPENWEATHER_API_KEY="$OPENWEATHER_API_KEY" \
  --dart-define=MAPBOX_ACCESS_TOKEN="$MAPBOX_ACCESS_TOKEN"

echo ""
echo "Processo concluído! Verifique a pasta build/app/outputs/flutter-apk/"

#!/bin/bash
# Build de produção do APK GeoForest (equivalente Mac/Linux do build_prod.bat)
#
# Uso:
#   export OPENWEATHER_API_KEY="sua_chave"
#   export MAPBOX_ACCESS_TOKEN="seu_token"
#   ./build_prod.sh
#
# Ou tudo numa linha só:
#   OPENWEATHER_API_KEY="sua_chave" MAPBOX_ACCESS_TOKEN="seu_token" ./build_prod.sh

set -e

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

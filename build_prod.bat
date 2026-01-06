@echo off
echo Iniciando Build do APK GeoForest...
flutter build apk --release --dart-define=RECAPTCHA_SITE_KEY=6LdafxgsAAAAAInBOeFOrNJR3l-4gUCzdry_XELi --dart-define=OPENWEATHER_API_KEY=44c419e21659fd02589ddc5f3be43f89 --dart-define=MAPBOX_ACCESS_TOKEN=pk.eyJ1IjoiZ2VvZm9yZXN0YXBwIiwiYSI6ImNtY2FyczBwdDAxZmYybHB1OWZlbG1pdW0ifQ.5HeYC0moMJ8dzZzVXKTPrg
echo.
echo Processo concluido! Verifique a pasta build\app\outputs\flutter-apk\
pause
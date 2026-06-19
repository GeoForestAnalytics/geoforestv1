@echo off
echo Iniciando Build do APK GeoForest...
if "%OPENWEATHER_API_KEY%"=="" echo AVISO: variavel de ambiente OPENWEATHER_API_KEY nao definida.
if "%MAPBOX_ACCESS_TOKEN%"=="" echo AVISO: variavel de ambiente MAPBOX_ACCESS_TOKEN nao definida.
flutter build apk --release --dart-define=RECAPTCHA_SITE_KEY=6LdafxgsAAAAAInBOeFOrNJR3l-4gUCzdry_XELi --dart-define=OPENWEATHER_API_KEY=%OPENWEATHER_API_KEY% --dart-define=MAPBOX_ACCESS_TOKEN=%MAPBOX_ACCESS_TOKEN%
echo.
echo Processo concluido! Verifique a pasta build\app\outputs\flutter-apk\
pause
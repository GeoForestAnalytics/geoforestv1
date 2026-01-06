// lib/utils/app_config.dart
// Configuração centralizada de chaves de API e constantes

class AppConfig {
  // Chaves de API - MOVER PARA VARIÁVEIS DE AMBIENTE EM PRODUÇÃO
  // IMPORTANTE: Em produção, estas chaves devem ser carregadas de variáveis de ambiente
  // ou Firebase Remote Config para maior segurança
  
  // ReCaptcha Site Key (usado no Firebase App Check para Web)
  // Esta é uma chave pública, mas ainda assim deve ser configurável
  static const String recaptchaSiteKey = String.fromEnvironment(
    'RECAPTCHA_SITE_KEY',
    defaultValue: '6LdafxgsAAAAAInBOeFOrNJR3l-4gUCzdry_XELi',
  );
  
  // OpenWeatherMap API Key
  static const String openWeatherApiKey = String.fromEnvironment(
    'OPENWEATHER_API_KEY',
    defaultValue: '44c419e21659fd02589ddc5f3be43f89',
  );
  
  // Mapbox Access Token
  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: 'pk.eyJ1IjoiZ2VvZm9yZXN0YXBwIiwiYSI6ImNtY2FyczBwdDAxZmYybHB1OWZlbG1pdW0ifQ.5HeYC0moMJ8dzZzVXKTPrg',
  );
  
  // Timeouts para operações de rede
  static const Duration networkTimeout = Duration(seconds: 15);
  static const Duration shortNetworkTimeout = Duration(seconds: 10);
  
  // Limites de sincronização
  static const int maxSyncAttempts = 100;
  static const int maxSyncRetries = 3;
}


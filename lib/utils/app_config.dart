// lib/utils/app_config.dart
// Configuração centralizada de chaves de API e constantes

class AppConfig {
  // Chaves de API - MOVER PARA VARIÁVEIS DE AMBIENTE EM PRODUÇÃO
  // IMPORTANTE: Em produção, estas chaves devem ser carregadas de variáveis de ambiente
  // ou Firebase Remote Config para maior segurança
  
  // ReCaptcha Site Key (usado no Firebase App Check para Web)
  // Esta é uma chave pública, então não tem tanto problema ficar aqui, 
  // mas manter no ambiente é uma boa prática.
  static const String recaptchaSiteKey = String.fromEnvironment(
    'RECAPTCHA_SITE_KEY',
    defaultValue: '6LdafxgsAAAAAInBOeFOrNJR3l-4gUCzdry_XELi',
  );
  
  // OpenWeatherMap API Key
  static const String openWeatherApiKey = String.fromEnvironment(
    'OPENWEATHER_API_KEY',
    defaultValue: '', // CORREÇÃO: Deixado vazio para segurança!
  );
  
  // Mapbox Access Token
  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '', // Perfeito!
  );
  
  // Timeouts para operações de rede
  static const Duration networkTimeout = Duration(seconds: 15);
  static const Duration shortNetworkTimeout = Duration(seconds: 10);
  
  // Limites de sincronização
  static const int maxSyncAttempts = 100;
  static const int maxSyncRetries = 3;
}
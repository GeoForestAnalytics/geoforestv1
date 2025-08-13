// lib/providers/theme_provider.dart (VERSÃO CORRIGIDA E SIMPLIFICADA)

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  late ThemeMode _themeMode;

  ThemeMode get themeMode => _themeMode;

  // O provider agora recebe o modo inicial, em vez de carregá-lo sozinho.
  ThemeProvider(ThemeMode initialThemeMode) {
    _themeMode = initialThemeMode;
  }

  /// Atualiza o tema e salva a preferência no dispositivo.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_option', mode.name);
  }
}

// Função auxiliar que ficará fora da classe para ser chamada na inicialização.
Future<ThemeMode> loadThemeFromPreferences() async {
  final prefs = await SharedPreferences.getInstance();
  final String themeString = prefs.getString('theme_option') ?? 'system';
  
  switch (themeString) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}
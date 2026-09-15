// lib/providers/team_provider.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TeamProvider with ChangeNotifier {
  String? _lider;
  String? _ajudantes;
  bool _isLoaded = false;

  String? get lider => _lider;
  String? get ajudantes => _ajudantes;
  bool get isLoaded => _isLoaded;

  TeamProvider() {
    loadTeam();
  }

  // Carrega os dados do SharedPreferences quando o provider é criado
  Future<void> loadTeam() async {
    final prefs = await SharedPreferences.getInstance();
    _lider = prefs.getString('nome_lider');
    _ajudantes = prefs.getString('nomes_ajudantes');

    // Se nome não foi configurado (gerente nunca passa pela tela de equipe),
    // usa o displayName ou email do Firebase Auth como fallback.
    if (_lider == null || _lider!.trim().isEmpty) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final nome = user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : user.email?.split('@').first ?? '';
        if (nome.isNotEmpty) {
          _lider = nome;
          await prefs.setString('nome_lider', nome);
        }
      }
    }

    _isLoaded = true;
    notifyListeners();
  }

  // Define a equipe e salva no SharedPreferences
  Future<void> setTeam(String novoLider, String novosAjudantes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nome_lider', novoLider);
    await prefs.setString('nomes_ajudantes', novosAjudantes);

    _lider = novoLider;
    _ajudantes = novosAjudantes;
    notifyListeners(); // Notifica os widgets que os dados mudaram
  }
}
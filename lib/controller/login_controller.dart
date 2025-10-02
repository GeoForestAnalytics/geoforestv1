// lib/controller/login_controller.dart (VERSÃO CORRIGIDA E SEGURA)

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geoforestv1/services/auth_service.dart';
// ✅ 1. IMPORT NECESSÁRIO: Precisamos do DatabaseHelper para poder apagar o banco.
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // <-- Adicione este import

class LoginController with ChangeNotifier {
  final AuthService _authService = AuthService();
  // ✅ 2. INSTÂNCIA NECESSÁRIA: Criamos uma instância para acessar o método de apagar.
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // Propriedades para saber o estado do login
  bool _isLoggedIn = false;
  User? _user;
  bool _isInitialized = false; 

  // Getters para acessar as propriedades de fora
  bool get isLoggedIn => _isLoggedIn;
  User? get user => _user;
  bool get isInitialized => _isInitialized;

  LoginController() {
    checkLoginStatus();
  }
  
  void checkLoginStatus() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user == null) {
        _isLoggedIn = false;
        _user = null;
        print('LoginController: Nenhum usuário logado.');
      } else {
        _isLoggedIn = true;
        _user = user;
        print('LoginController: Usuário ${user.email} está logado.');
      }
      
      _isInitialized = true;
      
      notifyListeners();
    });
  }

  /// ✅ 3. MÉTODO signOut COMPLETAMENTE SUBSTITUÍDO
  /// Agora ele garante que todos os dados locais sejam apagados ANTES do logout.
  Future<void> signOut() async {
  try {
    // ETAPA 1: Limpa o banco de dados local (SQLite)
    await _dbHelper.deleteDatabaseFile();
    
    // ETAPA 2: Limpa o cache offline do Firestore
    // Isso força o app a buscar dados frescos da nuvem no próximo login.
    await FirebaseFirestore.instance.clearPersistence();

    // ETAPA 3: Desloga o usuário do Firebase Auth
    await _authService.signOut();

    // Opcional, mas recomendado:
    // Termina a instância do Firestore para garantir que todas as conexões sejam fechadas.
    await FirebaseFirestore.instance.terminate();

  } catch (e) {
    debugPrint("!!!!!! Erro durante o processo de logout e limpeza: $e !!!!!");
    // Como medida de segurança, mesmo que a limpeza falhe,
    // ainda tentamos deslogar o usuário.
    await _authService.signOut();
  }
}
}
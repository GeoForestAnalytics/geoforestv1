// lib/controller/login_controller.dart (VERSÃO CORRIGIDA E SEGURA)

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geoforestv1/services/auth_service.dart';
// ✅ 1. IMPORT NECESSÁRIO: Precisamos do DatabaseHelper para poder apagar o banco.
import 'package:geoforestv1/data/datasources/local/database_helper.dart';

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
      // ETAPA 1: Apaga completamente o arquivo do banco de dados local.
      // Isso garante que, quando o próximo usuário fizer login, ele começará do zero.
      await _dbHelper.deleteDatabaseFile();
      
      // ETAPA 2: Apenas depois de apagar os dados, desloga o usuário do Firebase.
      await _authService.signOut();
      
      // O listener `authStateChanges` será acionado automaticamente pelo signOut
      // e o AppRouter redirecionará o usuário para a tela de login.
      
    } catch (e) {
      debugPrint("!!!!!! Erro durante o processo de logout e limpeza: $e !!!!!");
      // Como medida de segurança, mesmo que a limpeza do banco falhe,
      // ainda tentamos deslogar o usuário para que ele não fique preso.
      await _authService.signOut();
    }
  }
}
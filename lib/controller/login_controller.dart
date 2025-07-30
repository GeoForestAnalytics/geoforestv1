// lib/controller/login_controller.dart (VERSÃO FINAL LIMPA E SEGURA)

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geoforestv1/services/auth_service.dart';
// A importação do database_helper não é mais necessária aqui
// import 'package:geoforestv1/data/datasources/local/database_helper.dart';

class LoginController with ChangeNotifier {
  final AuthService _authService = AuthService();
  // A instância do _dbHelper não é mais necessária aqui
  // final DatabaseHelper _dbHelper = DatabaseHelper.instance;

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

  /// Método para realizar o logout usando o AuthService.
  Future<void> signOut() async {
    // Agora, apenas desloga do Firebase. Perfeito!
    await _authService.signOut();
    
    // O `authStateChanges` será acionado automaticamente e fará a notificação.
  }
}
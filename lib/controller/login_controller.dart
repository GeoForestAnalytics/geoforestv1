import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geoforestv1/services/auth_service.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginController with ChangeNotifier {
  final AuthService _authService = AuthService();
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

  Future<void> signOut() async {
    try {
      // ETAPA 1: Limpa o banco de dados local (SQLite)
      await _dbHelper.deleteDatabaseFile();
      
      // ETAPA 2: Limpa o cache offline do Firestore
      // Isso força o app a buscar dados frescos da nuvem no próximo login.
      await FirebaseFirestore.instance.clearPersistence();

      // ETAPA 3: Desloga o usuário do Firebase Auth
      await _authService.signOut();

      // NÃO USE terminate() AQUI. ISSO TRAVA O APP NO PRÓXIMO LOGIN.
      
      _isLoggedIn = false;
      _user = null;
      notifyListeners();

    } catch (e) {
      debugPrint("!!!!!! Erro durante o processo de logout e limpeza: $e !!!!!");
      // Como medida de segurança, mesmo que a limpeza falhe,
      // ainda tentamos deslogar o usuário.
      await _authService.signOut();
      _isLoggedIn = false;
      _user = null;
      notifyListeners();
    }
  }
}
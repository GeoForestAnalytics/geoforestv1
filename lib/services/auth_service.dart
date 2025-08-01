// lib/services/auth_service.dart (VERSÃO CORRETA E FINAL - GARANTIDO)

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoforestv1/services/licensing_service.dart';

class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LicensingService _licensingService = LicensingService();

  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;

      if (user == null) {
        throw FirebaseAuthException(code: 'user-not-found');
      }

      await user.getIdToken(true); 
      await _licensingService.checkAndRegisterDevice(user);
      
      return userCredential;
    } on LicenseException catch(e) {
      print('Erro de licença: ${e.message}. Deslogando usuário.');
      await signOut(); 
      rethrow;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  // --- ESTA É A FUNÇÃO CORRIGIDA QUE CRIA A ESTRUTURA CERTA ---
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;

      if (user != null) {
        await user.updateDisplayName(displayName);

        final trialEndDate = DateTime.now().add(const Duration(days: 7));
        
        // <<< ESTRUTURA DE DADOS CORRIGIDA >>>
        final licenseData = {
          'statusAssinatura': 'trial',
          'features': {'exportacao': false, 'analise': true},
          'limites': {'smartphone': 1, 'desktop': 0},
          'trial': {
            'ativo': true,
            'dataInicio': FieldValue.serverTimestamp(),
            'dataFim': Timestamp.fromDate(trialEndDate),
          },
          // MUDANÇA 1: CRIA O ARRAY para os UIDs, que é otimizado para buscas.
          'uidsPermitidos': [user.uid],
          
          // MUDANÇA 2: Os detalhes dos usuários ficam em um mapa separado.
          'usuariosPermitidos': {
            user.uid: {
              'cargo': 'gerente',
              'nome': displayName,
              'email': email,
              'adicionadoEm': FieldValue.serverTimestamp(),
            }
          }
        };

        await _firestore.collection('clientes').doc(user.uid).set(licenseData);
      }
      
      return credential;

    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw Exception('Este email já está em uso por outra conta.');
      }
      throw Exception('Ocorreu um erro durante o registro: ${e.message}');
    } catch (e) {
      throw Exception('Ocorreu um erro inesperado durante o registro.');
    }
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    await _firebaseAuth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  User? get currentUser => _firebaseAuth.currentUser;
}
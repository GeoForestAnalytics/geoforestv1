// ARQUIVO: lib/services/auth_service.dart (VERSÃO FINAL E COMPLETA)

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // <<< ADICIONADO
import 'package:geoforestv1/services/licensing_service.dart';

class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // <<< ADICIONADO
  final LicensingService _licensingService = LicensingService();

  // A função de login não precisa de alterações.
  Future<UserCredential> signInWithEmailAndPassword({
  required String email,
  required String password,
}) async {
  // O bloco 'if' foi removido. A execução agora sempre começa no 'try'.
  try {
    final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (userCredential.user == null) {
      throw FirebaseAuthException(code: 'user-not-found', message: 'Usuário não encontrado após o login.');
    }

    // Esta linha agora será executada para TODOS os usuários, incluindo o de teste.
    await _licensingService.checkAndRegisterDevice(userCredential.user!); 
    
    return userCredential;

  } on LicenseException catch (e) {
    print('Erro de licença: ${e.message}. Deslogando usuário.');
    await signOut(); 
    rethrow;
  } on FirebaseAuthException {
    rethrow;
  }
}

  // <<< ESTA É A FUNÇÃO QUE FOI COMPLETAMENTE ATUALIZADA >>>
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      // 1. Cria o usuário na autenticação (como antes)
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;

      if (user != null) {
        // Atualiza o nome de exibição do usuário
        await user.updateDisplayName(displayName);

        // 2. Define a data de fim do período de teste (7 dias a partir de agora)
        final trialEndDate = DateTime.now().add(const Duration(days: 7));
        
        // 3. Prepara os dados da licença de teste
        final licenseData = {
          'stripeCustomerId': null, 
          'statusAssinatura': 'trial',
          'features': {
            'exportacao': false,
            'analise': true,
          },
          'limites': {
            'smartphone': 1,
            'desktop': 0,
          },
          'trial': {
            'ativo': true,
            'dataInicio': FieldValue.serverTimestamp(),
            'dataFim': Timestamp.fromDate(trialEndDate),
          },
          // =================================================================
          // <<< MUDANÇA PRINCIPAL AQUI >>>
          // Cria o mapa 'usuariosPermitidos' e já insere o próprio usuário.
          'usuariosPermitidos': {
            user.uid: 'gerente' // Define o criador da conta como 'gerente' da sua própria licença
          }
          // =================================================================
        };

        // 4. Salva a licença de teste no Firestore usando o ID do usuário
        await _firestore.collection('clientes').doc(user.uid).set(licenseData);
      }
      
      return credential;

    } on FirebaseAuthException catch (e) {
      // Propaga erros comuns (como "email já em uso") para a tela de registro
      throw Exception(e.message);
    } catch (e) {
      throw Exception('Ocorreu um erro inesperado durante o registro.');
    }
  }

  // O resto do arquivo não precisa de mudanças.
  Future<void> sendPasswordResetEmail({required String email}) async {
    await _firebaseAuth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  User? get currentUser => _firebaseAuth.currentUser;
}
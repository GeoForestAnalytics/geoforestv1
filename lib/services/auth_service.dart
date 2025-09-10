import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoforestv1/services/licensing_service.dart';

class AuthService { // A classe começa aqui
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

      // A chamada agora é feita apenas UMA VEZ e com 'await'.
      // Isso garante que o app espera a verificação da licença terminar.
      await _licensingService.checkAndRegisterDevice(user);
      
      // Opcional, mas bom para garantir que os custom claims estão atualizados.
      await user.getIdToken(true); 
      
      return userCredential;
  
    } on LicenseException catch(e) {
      print('Erro de licença: ${e.message}. Deslogando usuário.');
      await signOut(); 
      rethrow;
    } on FirebaseAuthException {
      rethrow;
    }
  }

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
        
        // Dados para o documento da licença do cliente
        final licenseData = {
          'statusAssinatura': 'trial',
          'features': {'exportacao': false, 'analise': true},
          'limites': {'smartphone': 3, 'desktop': 0},
          'trial': {
            'ativo': true,
            'dataInicio': FieldValue.serverTimestamp(),
            'dataFim': Timestamp.fromDate(trialEndDate),
          },
          'uidsPermitidos': [user.uid],
          'usuariosPermitidos': {
            user.uid: {
              'cargo': 'gerente',
              'nome': displayName,
              'email': email,
              'adicionadoEm': FieldValue.serverTimestamp(),
            }
          }
        };

        // <<< INÍCIO DA CORREÇÃO >>>
        // 1. Crie um "lote" de escrita.
        final batch = _firestore.batch();

        // 2. Defina a operação para a coleção 'clientes'.
        final clienteDocRef = _firestore.collection('clientes').doc(user.uid);
        batch.set(clienteDocRef, licenseData);

        // 3. Defina a operação para a coleção 'users'.
        final userDocRef = _firestore.collection('users').doc(user.uid);
        batch.set(userDocRef, {
          'email': email,
          'licenseId': user.uid,
        });

        // 4. Envie as duas operações juntas.
        await batch.commit();
        // <<< FIM DA CORREÇÃO >>>
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
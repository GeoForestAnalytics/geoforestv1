// lib/services/licensing_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class LicenseException implements Exception {
  final String message;
  LicenseException(this.message);
  @override
  String toString() => message;
}

class LicensingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<DocumentSnapshot<Map<String, dynamic>>?> findLicenseDocumentForUser(User user) async {
  print('--- LICENSING SERVICE: Buscando licença para o usuário com UID: ${user.uid}');
  
  try {
    // ---- NOVA LÓGICA DE BUSCA DIRETA ----
    print('--- LICENSING SERVICE: Tentando busca direta em /users/${user.uid}');
    final userDocRef = _firestore.collection('users').doc(user.uid);
    final userDoc = await userDocRef.get();

    if (userDoc.exists && userDoc.data() != null) {
      print('--- LICENSING SERVICE: Documento encontrado em /users. Verificando licenseId.');
      final licenseId = userDoc.data()!['licenseId'] as String?;
      
      if (licenseId != null && licenseId.isNotEmpty) {
        print('--- LICENSING SERVICE: licenseId encontrado: "$licenseId". Buscando /clientes/$licenseId');
        final clienteDoc = await _firestore.collection('clientes').doc(licenseId).get();
        
        if (clienteDoc.exists) {
          print('--- LICENSING SERVICE: SUCESSO! Documento da licença encontrado em /clientes.');
          return clienteDoc;
        } else {
          print('--- LICENSING SERVICE: ERRO! Documento em /users aponta para uma licença inexistente em /clientes/$licenseId');
          throw LicenseException('A licença associada à sua conta ($licenseId) não foi encontrada.');
        }
      } else {
        print('--- LICENSING SERVICE: ERRO! Documento em /users existe, mas o campo "licenseId" está ausente ou vazio.');
        // Continua para o método de fallback
      }
    } else {
       print('--- LICENSING SERVICE: Documento não encontrado em /users. Tentando método antigo de fallback...');
    }

    // ---- LÓGICA ANTIGA DE FALLBACK ----
    print('--- LICENSING SERVICE: Executando busca por arrayContains (esperado falhar com as novas regras)...');
    final query = _firestore.collection('clientes').where('uidsPermitidos', arrayContains: user.uid).limit(1);
    final snapshot = await query.get();
    
    if (snapshot.docs.isNotEmpty) {
       print('--- LICENSING SERVICE: Licença encontrada pelo método de fallback. (Isso não deveria acontecer).');
       return snapshot.docs.first;
    }
    
    print('--- LICENSING SERVICE: NENHUMA licença encontrada para este usuário.');
    return null;

  } catch (e) {
    print('--- LICENSING SERVICE: Ocorreu uma exceção DENTRO de findLicenseDocumentForUser: $e');
    rethrow;
  }
}

  Future<void> checkAndRegisterDevice(User user) async {
    final clienteDoc = await findLicenseDocumentForUser(user);

    if (clienteDoc == null || !clienteDoc.exists) {
      throw LicenseException('Sua conta não está associada a nenhuma licença ativa. Contate o administrador da sua empresa.');
    }

    final clienteData = clienteDoc.data()!;
    final statusAssinatura = clienteData['statusAssinatura'];
    final limites = clienteData['limites'] as Map<String, dynamic>?;

    bool acessoPermitido = false;
    if (statusAssinatura == 'ativa') {
      acessoPermitido = true;
    } else if (statusAssinatura == 'trial') {
      final trialData = clienteData['trial'] as Map<String, dynamic>?;
      if (trialData != null && trialData['ativo'] == true) {
        final dataFim = (trialData['dataFim'] as Timestamp).toDate();
        if (DateTime.now().isBefore(dataFim)) {
          acessoPermitido = true;
        } else {
          throw LicenseException('Seu período de teste expirou. Contrate um plano.');
        }
      }
    }

    if (!acessoPermitido) {
      throw LicenseException('A assinatura da sua empresa está inativa ou expirou.');
    }

    if (limites == null) {
      throw LicenseException('Os limites do seu plano não estão configurados corretamente.');
    }

    final tipoDispositivo = kIsWeb ? 'desktop' : 'smartphone';
    final deviceId = await _getDeviceId();

    if (deviceId == null) {
      throw LicenseException('Não foi possível identificar seu dispositivo.');
    }

    final dispositivosAtivosRef = clienteDoc.reference.collection('dispositivosAtivos');
    final dispositivoExistente = await dispositivosAtivosRef.doc(deviceId).get();

    if (dispositivoExistente.exists) {
      return;
    }

    final contagemAtualSnapshot = await dispositivosAtivosRef.where('tipo', isEqualTo: tipoDispositivo).count().get();
    final contagemAtual = contagemAtualSnapshot.count ?? 0;
    final limiteAtual = limites[tipoDispositivo] as int? ?? 0;

    if (limiteAtual >= 0 && contagemAtual >= limiteAtual) {
      throw LicenseException('O limite de dispositivos do tipo "$tipoDispositivo" foi atingido para sua empresa.');
    }

    await dispositivosAtivosRef.doc(deviceId).set({
      'uidUsuario': user.uid,
      'emailUsuario': user.email,
      'tipo': tipoDispositivo,
      'registradoEm': FieldValue.serverTimestamp(),
      'nomeDispositivo': await _getDeviceName(),
    });
  }
  
  Future<Map<String, int>> getDeviceUsage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {'smartphone': 0, 'desktop': 0};

    final clienteDoc = await findLicenseDocumentForUser(user);
    if (clienteDoc == null || !clienteDoc.exists) {
      return {'smartphone': 0, 'desktop': 0};
    }

    return _getDeviceCountFromDoc(clienteDoc.reference);
  }
  
  Future<Map<String, int>> _getDeviceCountFromDoc(DocumentReference docRef) async {
    final dispositivosAtivosRef = docRef.collection('dispositivosAtivos');
    final smartphoneCount = (await dispositivosAtivosRef.where('tipo', isEqualTo: 'smartphone').count().get()).count ?? 0;
    final desktopCount = (await dispositivosAtivosRef.where('tipo', isEqualTo: 'desktop').count().get()).count ?? 0;
    return {'smartphone': smartphoneCount, 'desktop': desktopCount};
  }

  Future<String?> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    if (kIsWeb) {
      final webInfo = await deviceInfo.webBrowserInfo;
      return 'web_${webInfo.vendor}_${webInfo.userAgent}';
    } else if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor;
    }
    return null;
  }
  
  Future<String> _getDeviceName() async {
     final deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) return 'Navegador Web';
      if (Platform.isAndroid) return '${(await deviceInfo.androidInfo).manufacturer} ${(await deviceInfo.androidInfo).model}';
      if (Platform.isIOS) return (await deviceInfo.iosInfo).name;
      return 'Dispositivo Desconhecido';
  }
}
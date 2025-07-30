// lib/services/gerente_service.dart (VERSÃO COM IMPORTS CORRIGIDOS)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/services/licensing_service.dart';
import 'package:geoforestv1/models/projeto_model.dart'; // <<< CORREÇÃO: IMPORT ADICIONADO

class GerenteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LicensingService _licensingService = LicensingService();

  /// Retorna a lista completa de projetos (ativos e arquivados) da licença.
  Future<List<Projeto>> getTodosOsProjetosStream() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final licenseDoc = await _licensingService.findLicenseDocumentForUser(user);
    if (licenseDoc == null) {
      throw Exception("Licença não encontrada para o gerente.");
    }
    final licenseId = licenseDoc.id;

    final snapshot = await _firestore
        .collection('clientes')
        .doc(licenseId)
        .collection('projetos')
        .get();
    
    // Agora ele sabe o que é Projeto.fromMap
    return snapshot.docs.map((doc) => Projeto.fromMap(doc.data())).toList();
  }

  /// Retorna um "fluxo" (Stream) de dados em tempo real da coleção de coletas.
  Stream<List<Parcela>> getDadosColetaStream() async* {
    final user = _auth.currentUser;
    if (user == null) {
      yield [];
      return;
    }

    try {
      final licenseDoc = await _licensingService.findLicenseDocumentForUser(user);
      if (licenseDoc == null) {
        throw Exception("Licença não encontrada para o gerente.");
      }
      final licenseId = licenseDoc.id;

      final stream = _firestore
          .collection('clientes')
          .doc(licenseId)
          .collection('dados_coleta')
          .snapshots();

      await for (final querySnapshot in stream) {
        final parcelas = querySnapshot.docs
            .map((doc) => Parcela.fromMap(doc.data()))
            .toList();
        
        yield parcelas;
      }
    } catch (e) {
      yield* Stream.error(e);
    }
  }
}
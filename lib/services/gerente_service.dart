// lib/services/gerente_service.dart (VERSÃO ROBUSTA COM DEBUG)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // Para o debugPrint
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/services/licensing_service.dart';
import 'package:geoforestv1/models/projeto_model.dart';

class GerenteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LicensingService _licensingService = LicensingService();

  /// Retorna o ID da licença do usuário logado. Lança uma exceção se não encontrar.
  Future<String> _getLicenseId() async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint("--- [GerenteService] ERRO CRÍTICO: _getLicenseId chamado mas o usuário é nulo.");
      throw Exception("Usuário não está logado.");
    }

    final licenseDoc = await _licensingService.findLicenseDocumentForUser(user);
    if (licenseDoc == null) {
      debugPrint("--- [GerenteService] ERRO CRÍTICO: Não foi possível encontrar um documento de licença para o UID ${user.uid}.");
      throw Exception("Licença não encontrada para o gerente.");
    }
    debugPrint("--- [GerenteService] _getLicenseId obteve com sucesso o ID da licença: ${licenseDoc.id}");
    return licenseDoc.id;
  }

  /// Retorna a lista completa de projetos (ativos e arquivados) da licença.
  Future<List<Projeto>> getTodosOsProjetosStream() async {
    try {
      final licenseId = await _getLicenseId();
      debugPrint("--- [GerenteService] Buscando projetos para a licença: $licenseId");

      final snapshot = await _firestore
          .collection('clientes')
          .doc(licenseId)
          .collection('projetos')
          .get();
      
      debugPrint("--- [GerenteService] ${snapshot.docs.length} projetos encontrados no Firestore.");
      return snapshot.docs.map((doc) => Projeto.fromMap(doc.data())).toList();
    } catch (e) {
      debugPrint("--- [GerenteService] ERRO ao buscar projetos: $e");
      rethrow; 
    }
  }

  /// Retorna um "fluxo" (Stream) de dados em tempo real da coleção de coletas.
  Stream<List<Parcela>> getDadosColetaStream() async* {
    try {
      final licenseId = await _getLicenseId();
      debugPrint("--- [GerenteService] Iniciando stream para ouvir coletas da licença: $licenseId");

      final stream = _firestore
          .collection('clientes')
          .doc(licenseId)
          .collection('dados_coleta')
          .snapshots();

      await for (final querySnapshot in stream) {
        debugPrint("--- [GerenteService] Stream de coletas recebeu ${querySnapshot.docs.length} documentos.");
        
        final parcelas = querySnapshot.docs
            .map((doc) {
              try {
                return Parcela.fromMap(doc.data());
              } catch (e) {
                debugPrint("--- [GerenteService] ERRO ao converter um documento de parcela do Firestore: $e. Dados: ${doc.data()}");
                return null;
              }
            })
            .where((p) => p != null) // Filtra quaisquer parcelas que falharam na conversão
            .cast<Parcela>()
            .toList();
            
        yield parcelas;
      }
    } catch (e) {
      debugPrint("--- [GerenteService] ERRO CRÍTICO no stream de coletas: $e");
      yield* Stream.error(e); 
    }
  }
}
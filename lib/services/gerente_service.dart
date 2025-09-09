// lib/services/gerente_service.dart (VERSÃO CORRIGIDA E UNIFICADA)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/services/licensing_service.dart';

class GerenteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LicensingService _licensingService = LicensingService();

  // Função auxiliar para criar um stream para uma coleção específica de um cliente
  Stream<QuerySnapshot> _getStreamForCollection(String licenseId, String collectionName) {
    return _firestore
        .collection('clientes')
        .doc(licenseId)
        .collection(collectionName)
        .snapshots();
  }

  // Combina múltiplos streams em um único stream que emite a lista agregada.
  Stream<List<T>> _getAggregatedStream<T>({
    required List<String> licenseIds,
    required String collectionName,
    required T Function(Map<String, dynamic>) fromMap,
  }) {
    final controller = StreamController<List<T>>();
    final subscriptions = <StreamSubscription>[];
    final allData = <String, List<T>>{}; // Mapa para guardar os dados de cada licença

    void updateStream() {
      final aggregatedList = allData.values.expand((list) => list).toList();
      controller.add(aggregatedList);
    }

    if (licenseIds.isEmpty) {
      controller.add([]);
      Future.microtask(() => controller.close());
      return controller.stream;
    }

    for (final licenseId in licenseIds) {
      final stream = _getStreamForCollection(licenseId, collectionName);
      final subscription = stream.listen(
        (snapshot) {
          try {
            final dataList = snapshot.docs.map((doc) => fromMap(doc.data() as Map<String, dynamic>)).toList();
            allData[licenseId] = dataList;
            updateStream();
          } catch (e) {
            debugPrint("Erro ao converter dados do stream para $licenseId/$collectionName: $e");
          }
        },
        onError: (e) => debugPrint("Erro no stream para $licenseId/$collectionName: $e"),
      );
      subscriptions.add(subscription);
    }

    controller.onCancel = () {
      for (var sub in subscriptions) {
        sub.cancel();
      }
    };

    return controller.stream;
  }
  
  // Os métodos públicos agora usam o agregador
  Stream<List<Parcela>> getDadosColetaStream({required List<String> licenseIds}) {
    return _getAggregatedStream<Parcela>(
      licenseIds: licenseIds,
      collectionName: 'dados_coleta',
      fromMap: Parcela.fromMap,
    );
  }

  Stream<List<CubagemArvore>> getDadosCubagemStream({required List<String> licenseIds}) {
    return _getAggregatedStream<CubagemArvore>(
      licenseIds: licenseIds,
      collectionName: 'dados_cubagem',
      fromMap: CubagemArvore.fromMap,
    );
  }

  Stream<List<DiarioDeCampo>> getDadosDiarioStream({required List<String> licenseIds}) {
    return _getAggregatedStream<DiarioDeCampo>(
      licenseIds: licenseIds,
      collectionName: 'diarios_de_campo',
      fromMap: DiarioDeCampo.fromMap,
    );
  }
  
  // Este método busca os projetos da licença do usuário atual.
  // Ele NÃO precisa de agregação, pois projetos são específicos da licença local.
  Future<List<Projeto>> getTodosOsProjetosStream() async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception("Usuário não está logado.");

      final licenseDoc = await _licensingService.findLicenseDocumentForUser(user);
      if (licenseDoc == null) {
        debugPrint("--- [GerenteService] Nenhuma licença própria encontrada para ${user.uid}. Retornando 0 projetos próprios.");
        return []; 
      }

      final licenseId = licenseDoc.id;
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
}
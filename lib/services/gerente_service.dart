// lib/services/gerente_service.dart (VERSÃO LIMPA E FINAL)

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

  // (Método _getStreamForCollection removido pois não era mais usado)

  // Combina múltiplos streams em um único stream que emite a lista agregada.
  Stream<List<T>> _getAggregatedStream<T>({
    required List<String> licenseIds,
    required String collectionName,
    required T Function(Map<String, dynamic>) fromMap,
    Query Function(CollectionReference)? queryBuilder,
  }) {
    final controller = StreamController<List<T>>();
    final subscriptions = <StreamSubscription>[];
    final allData = <String, List<T>>{}; 

    void updateStream() {
      if (!controller.isClosed) {
        final aggregatedList = allData.values.expand((list) => list).toList();
        controller.add(aggregatedList);
      }
    }

    if (licenseIds.isEmpty) {
      controller.add([]);
      Future.microtask(() => controller.close());
      return controller.stream;
    }

    for (final licenseId in licenseIds) {
      // 1. Obtém a referência da coleção
      CollectionReference collectionRef = _firestore
          .collection('clientes')
          .doc(licenseId)
          .collection(collectionName);

      // 2. Aplica o filtro (queryBuilder) se ele existir
      Query query = collectionRef;
      if (queryBuilder != null) {
        query = queryBuilder(collectionRef);
      }

      final subscription = query.snapshots().listen(
        (snapshot) {
          try {
            final dataList = snapshot.docs
                .map((doc) => fromMap(doc.data() as Map<String, dynamic>))
                .toList();
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
  
  // --- MÉTODOS ORIGINAIS (Mantidos para compatibilidade ou uso global) ---

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

  // --- NOVOS MÉTODOS PARA LAZY LOADING (Carregamento sob Demanda) ---

  Stream<List<Parcela>> getParcelasDoProjetoStream({
    required List<String> licenseIds, 
    required int projetoId
  }) {
    return _getAggregatedStream<Parcela>(
      licenseIds: licenseIds,
      collectionName: 'dados_coleta',
      fromMap: Parcela.fromMap,
      queryBuilder: (collection) => collection.where('projetoId', isEqualTo: projetoId),
    );
  }
  
  Stream<List<Parcela>> getParcelasGlobalStream({required List<String> licenseIds}) {
  return _getAggregatedStream<Parcela>(
    licenseIds: licenseIds,
    collectionName: 'dados_coleta',
    fromMap: Parcela.fromMap,
    // REMOVEMOS o queryBuilder que filtrava por projetoId
  );
}

Stream<List<CubagemArvore>> getCubagensGlobalStream({required List<String> licenseIds}) {
  return _getAggregatedStream<CubagemArvore>(
    licenseIds: licenseIds,
    collectionName: 'dados_cubagem',
    fromMap: CubagemArvore.fromMap,
  );
}

  Stream<List<CubagemArvore>> getCubagensDoProjetoStream({
    required List<String> licenseIds,
    required List<int> talhoesIds 
  }) {
    if (talhoesIds.isEmpty) return Stream.value([]);
    
    return _getAggregatedStream<CubagemArvore>(
      licenseIds: licenseIds,
      collectionName: 'dados_cubagem',
      fromMap: CubagemArvore.fromMap,
    ).map((listaCompleta) {
      return listaCompleta.where((c) => c.talhaoId != null && talhoesIds.contains(c.talhaoId)).toList();
    });
  }
  
  Future<List<Projeto>> getTodosOsProjetosStream() async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception("Usuário não está logado.");

      final licenseDoc = await _licensingService.findLicenseDocumentForUser(user);
      if (licenseDoc == null) {
        debugPrint("--- [GerenteService] Nenhuma licença própria encontrada. Retornando 0 projetos.");
        return []; 
      }

      final licenseId = licenseDoc.id;
      final snapshot = await _firestore
          .collection('clientes')
          .doc(licenseId)
          .collection('projetos')
          .get();
      
      return snapshot.docs.map((doc) => Projeto.fromMap(doc.data())).toList();
    } catch (e) {
      debugPrint("--- [GerenteService] ERRO ao buscar projetos: $e");
      rethrow; 
    }
  }
}
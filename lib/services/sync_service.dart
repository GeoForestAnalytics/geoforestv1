// lib/services/sync_service.dart (VERSÃO CORRIGIDA PARA FORÇAR CONCLUÍDAS)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/cubagem_secao_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/sync_conflict_model.dart';
import 'package:geoforestv1/models/sync_progress_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/services/licensing_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
import 'dart:convert'; // <--- ADICIONE ESTA LINHA


import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geoforestv1/utils/app_config.dart';

class SyncService {
  final firestore.FirebaseFirestore _firestore = firestore.FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final LicensingService _licensingService = LicensingService();
  
  final _parcelaRepository = ParcelaRepository();
  final _cubagemRepository = CubagemRepository();
  final _projetoRepository = ProjetoRepository();
  
  final StreamController<SyncProgress> _progressStreamController = StreamController.broadcast();
  Stream<SyncProgress> get progressStream => _progressStreamController.stream;

  final List<SyncConflict> conflicts = [];
  bool _isCancelled = false;
  int _downloadTotal = 0;
  int _downloadados = 0;

  /// Cancela a sincronização em andamento
  void cancelarSincronizacao() {
    _isCancelled = true;
  }

  Future<void> sincronizarDados() async {
    conflicts.clear();
    _isCancelled = false;
    _downloadTotal = 0;
    _downloadados = 0;
    
    final user = _auth.currentUser;
    if (user == null) {
      _progressStreamController.add(SyncProgress(erro: "Usuário não está logado.", concluido: true));
      return;
    }

    // Verifica conectividade antes de iniciar
    try {
      final connectivityResults = await Connectivity().checkConnectivity().timeout(
        AppConfig.shortNetworkTimeout,
        onTimeout: () => [ConnectivityResult.none],
      );
      
      if (connectivityResults.isEmpty || connectivityResults.contains(ConnectivityResult.none)) {
        _progressStreamController.add(SyncProgress(
          erro: "Sem conexão com a internet. Verifique sua rede e tente novamente.",
          concluido: true,
        ));
        return;
      }
    } catch (e) {
      _progressStreamController.add(SyncProgress(
        erro: "Erro ao verificar conexão: $e",
        concluido: true,
      ));
      return;
    }

    try {
      final licenseDoc = await _licensingService.findLicenseDocumentForUser(user);
      final licenseIdDoUsuarioLogado = licenseDoc?.id;
      
      final totalParcelas = (await _parcelaRepository.getUnsyncedParcelas()).length;
      final totalCubagens = (await _cubagemRepository.getUnsyncedCubagens()).length;
      final totalGeral = totalParcelas + totalCubagens;
      
      _progressStreamController.add(SyncProgress(totalAProcessar: totalGeral, mensagem: "Preparando sincronização..."));

      if (licenseIdDoUsuarioLogado != null) {
        final cargo = (licenseDoc!.data()!['usuariosPermitidos'] as Map<String, dynamic>?)?[user.uid]?['cargo'] ?? 'equipe';
        if (cargo == 'gerente') {
          _progressStreamController.add(SyncProgress(totalAProcessar: totalGeral, mensagem: "Enviando estrutura de projetos..."));
          await _uploadHierarquiaCompleta(licenseIdDoUsuarioLogado);
        }
      }
      
      // Upload de dados (com lógica corrigida)
      await _uploadColetasNaoSincronizadas(licenseIdDoUsuarioLogado, totalGeral);

      _progressStreamController.add(SyncProgress(
        totalAProcessar: totalGeral,
        processados: totalGeral,
        mensagem: "Coletando dados da nuvem...",
        isDownloading: true,
        totalDownload: 0,
        downloadados: 0,
      ));
      
      if (licenseIdDoUsuarioLogado != null) {
        debugPrint("--- SyncService: Baixando dados da licença PRÓPRIA: $licenseIdDoUsuarioLogado");
        final idsHierarquiaLocal = await _downloadHierarquiaCompleta(licenseIdDoUsuarioLogado);
        await _downloadColetas(licenseIdDoUsuarioLogado, talhaoIdsParaBaixar: idsHierarquiaLocal);
      }
      
      final projetosDelegados = await _buscarProjetosDelegadosParaUsuario(user.uid);
      for (final entry in projetosDelegados.entries) {
        final licenseIdDoCliente = entry.key;
        final projetosParaBaixar = entry.value;
        debugPrint("--- SyncService: Baixando dados delegados da licença do CLIENTE: $licenseIdDoCliente para os projetos $projetosParaBaixar");
        
        final idsHierarquiaDelegada = await _downloadHierarquiaCompleta(licenseIdDoCliente, projetosParaBaixar: projetosParaBaixar);
        await _downloadColetas(licenseIdDoCliente, talhaoIdsParaBaixar: idsHierarquiaDelegada);
      }

      String finalMessage = "Sincronização Concluída!";
      if (conflicts.isNotEmpty) {
        finalMessage += " ${conflicts.length} conflito(s) foram detectados.";
      }
      _progressStreamController.add(SyncProgress(totalAProcessar: totalGeral, processados: totalGeral, mensagem: finalMessage, concluido: true));

    } catch(e, s) {
      String erroMsg = "Ocorreu um erro durante a sincronização";
      
      // Mensagens mais amigáveis para o usuário
      if (e.toString().contains('network') || e.toString().contains('connection')) {
        erroMsg = "Erro de conexão. Verifique sua internet e tente novamente.";
      } else if (e.toString().contains('timeout')) {
        erroMsg = "Tempo de espera esgotado. Tente novamente.";
      } else if (e.toString().contains('permission')) {
        erroMsg = "Sem permissão para sincronizar. Verifique suas credenciais.";
      } else {
        erroMsg = "Erro inesperado: ${e.toString().length > 100 ? e.toString().substring(0, 100) + '...' : e.toString()}";
      }
      
      debugPrint("Erro na sincronização: $e\n$s");
      _progressStreamController.add(SyncProgress(erro: erroMsg, concluido: true));
      rethrow;
    }
  }

  Future<Map<String, List<int>>> _buscarProjetosDelegadosParaUsuario(String uid) async {
    final query = _firestore.collectionGroup('chavesDeDelegacao').where('licenseIdConvidada', isEqualTo: uid).where('status', isEqualTo: 'ativa');
    final snapshot = await query.get();
    if (snapshot.docs.isEmpty) return {};
    final Map<String, List<int>> resultado = {};
    for (final doc in snapshot.docs) {
      final licenseIdDoCliente = doc.reference.parent.parent!.id;
      final projetosPermitidos = List<int>.from(doc.data()['projetosPermitidos'] ?? []);
      resultado.update(licenseIdDoCliente, (list) => list..addAll(projetosPermitidos), ifAbsent: () => projetosPermitidos);
    }
    return resultado;
  }

  Future<void> _uploadHierarquiaCompleta(String licenseId) async {
    final db = await _dbHelper.database;
    final todosProjetosLocais = (await db.query('projetos')).map(Projeto.fromMap).toList();
    if (todosProjetosLocais.isEmpty) return;

    final projetosPorDestino = groupBy<Projeto, String>(
      todosProjetosLocais,
      (projeto) => projeto.delegadoPorLicenseId ?? licenseId,
    );

    for (final entry in projetosPorDestino.entries) {
      final licenseIdDeDestino = entry.key;
      final projetosParaEsteDestino = entry.value;
      final batch = _firestore.batch();
      
      final bool isUploadingToSelf = licenseIdDeDestino == licenseId;

      debugPrint("SyncService: Enviando hierarquia para a licença: $licenseIdDeDestino. É a própria licença? $isUploadingToSelf");

      final projetosIds = projetosParaEsteDestino.map((p) => p.id!).toList();
      if (projetosIds.isEmpty) continue;

      for (var projeto in projetosParaEsteDestino) {
        final docRef = _firestore.collection('clientes').doc(licenseIdDeDestino).collection('projetos').doc(projeto.id.toString());
        final map = projeto.toMap();
        map['lastModified'] = firestore.FieldValue.serverTimestamp();
        if (isUploadingToSelf) {
          batch.set(docRef, map, firestore.SetOptions(merge: true));
        }
      }

      final atividades = await db.query('atividades', where: 'projetoId IN (${projetosIds.join(',')})');
      for (var a in atividades) {
        final docRef = _firestore.collection('clientes').doc(licenseIdDeDestino).collection('atividades').doc(a['id'].toString());
        final map = Map<String, dynamic>.from(a);
        map['lastModified'] = firestore.FieldValue.serverTimestamp();
        batch.set(docRef, map, firestore.SetOptions(merge: true));
      }
      
      final atividadeIds = atividades.map((a) => a['id'] as int).toList();
      if (atividadeIds.isNotEmpty) {
          final fazendas = await db.query('fazendas', where: 'atividadeId IN (${atividadeIds.join(',')})');
          for (var f in fazendas) {
              final docId = "${f['id']}_${f['atividadeId']}";
              final docRef = _firestore.collection('clientes').doc(licenseIdDeDestino).collection('fazendas').doc(docId);
              final map = Map<String, dynamic>.from(f);
              map['lastModified'] = firestore.FieldValue.serverTimestamp();
              batch.set(docRef, map, firestore.SetOptions(merge: true));
          }

          final todosTalhoes = await db.query('talhoes');
          final fazendasValidas = fazendas.map((f) => {'id': f['id'], 'atividadeId': f['atividadeId']}).toSet();
          final talhoesParaEnviar = todosTalhoes.where((t) {
              return fazendasValidas.any((f) => f['id'] == t['fazendaId'] && f['atividadeId'] == t['fazendaAtividadeId']);
          });

          for (var t in talhoesParaEnviar) {
              final docRef = _firestore.collection('clientes').doc(licenseIdDeDestino).collection('talhoes').doc(t['id'].toString());
              final talhaoObj = Talhao.fromMap(t);
              final map = talhaoObj.toFirestoreMap();
              map['lastModified'] = firestore.FieldValue.serverTimestamp();
              batch.set(docRef, map, firestore.SetOptions(merge: true));
          }
      }
      
      await batch.commit();
    }
  }
  
  Future<void> _uploadColetasNaoSincronizadas(String? licenseIdDoUsuarioLogado, int totalGeral) async {
    int processados = 0;
    // Conta apenas falhas consecutivas; zera a cada sucesso — não limita itens bem-sucedidos
    int falhasConsecutivas = 0;
    const maxFalhasConsecutivas = AppConfig.maxSyncAttempts;

    while (falhasConsecutivas < maxFalhasConsecutivas && !_isCancelled) {
      if (_isCancelled) {
        _progressStreamController.add(SyncProgress(erro: "Sincronização cancelada pelo usuário.", concluido: true));
        break;
      }

      if (totalGeral > 0) {
        _progressStreamController.add(SyncProgress(totalAProcessar: totalGeral, processados: processados, mensagem: "Enviando item ${processados + 1} de $totalGeral..."));
      }

      // --- PARCELAS ---
      final parcelaLocal = await _parcelaRepository.getOneUnsyncedParcel();
      if (parcelaLocal != null) {
        try {
          final projetoPai = await _projetoRepository.getProjetoPelaParcela(parcelaLocal);
          
          String? licenseIdDeDestino;
          if (projetoPai?.delegadoPorLicenseId != null) {
             licenseIdDeDestino = projetoPai!.delegadoPorLicenseId;
             debugPrint("--- [UPLOAD] Parcela ${parcelaLocal.idParcela} (Proj: ${projetoPai.nome}) é DELEGADA. Enviando para DONO: $licenseIdDeDestino");
          } else {
             licenseIdDeDestino = licenseIdDoUsuarioLogado;
             debugPrint("--- [UPLOAD] Parcela ${parcelaLocal.idParcela} é PRÓPRIA. Enviando para MIM: $licenseIdDeDestino");
          }
          
          if (licenseIdDeDestino == null) throw Exception("Licença de destino não encontrada para a parcela ${parcelaLocal.idParcela}.");
          
          final docRef = _firestore.collection('clientes').doc(licenseIdDeDestino).collection('dados_coleta').doc(parcelaLocal.uuid);
          final docServer = await docRef.get();
          
          bool deveEnviar = true;
          if (docServer.exists) {
            final serverData = docServer.data()!;
            final serverLastModified = (serverData['lastModified'] as firestore.Timestamp?)?.toDate();
            
            // >>> CORREÇÃO 1: LÓGICA DE PRIORIDADE PARA PARCELAS CONCLUÍDAS <<<
            final String statusServer = (serverData['status'] ?? 'pendente').toString().toLowerCase();
            
            if (parcelaLocal.status == StatusParcela.concluida && statusServer != 'concluida') {
               // Se eu concluí e o servidor não, EU GANHO. (Ignora data)
               deveEnviar = true;
               debugPrint("--- [FORCE UPDATE] Parcela concluída localmente. Forçando envio sobre versão pendente do servidor.");
            } 
            else if (serverLastModified != null && parcelaLocal.lastModified != null && serverLastModified.isAfter(parcelaLocal.lastModified!)) {
              // Caso padrão de conflito por data
              deveEnviar = false;
              conflicts.add(SyncConflict(
                type: ConflictType.parcela,
                localData: parcelaLocal,
                serverData: Parcela.fromMap(serverData),
                identifier: "Parcela ${parcelaLocal.idParcela} (Talhão: ${parcelaLocal.nomeTalhao})",
              ));
            }
          }
          
          if (deveEnviar) {
            await _uploadParcela(docRef, parcelaLocal);
          }
          await _parcelaRepository.markParcelaAsSynced(parcelaLocal.dbId!);
          processados++;
          falhasConsecutivas = 0;
          continue;
        } catch (e) {
          debugPrint("Falha ao enviar parcela ${parcelaLocal.idParcela}: $e");
          _progressStreamController.add(SyncProgress(
            mensagem: "Erro ao enviar parcela ${parcelaLocal.idParcela}. Continuando...",
          ));
          falhasConsecutivas++;
          continue;
        }
      }

      // --- CUBAGENS ---
      final cubagemLocal = await _cubagemRepository.getOneUnsyncedCubagem();
      if(cubagemLocal != null){
         try {
          final projetoPai = await _projetoRepository.getProjetoPelaCubagem(cubagemLocal);
          
          String? licenseIdDeDestino;
          if (projetoPai?.delegadoPorLicenseId != null) {
             licenseIdDeDestino = projetoPai!.delegadoPorLicenseId;
             debugPrint("--- [UPLOAD] Cubagem ${cubagemLocal.identificador} é DELEGADA. Enviando para DONO: $licenseIdDeDestino");
          } else {
             licenseIdDeDestino = licenseIdDoUsuarioLogado;
             debugPrint("--- [UPLOAD] Cubagem ${cubagemLocal.identificador} é PRÓPRIA. Enviando para MIM: $licenseIdDeDestino");
          }

           if (licenseIdDeDestino == null) throw Exception("Licença de destino não encontrada para a cubagem ${cubagemLocal.id}.");
          
          final docRef = _firestore.collection('clientes').doc(licenseIdDeDestino).collection('dados_cubagem').doc(cubagemLocal.id.toString());
          final docServer = await docRef.get();
          
          bool deveEnviar = true;
          if (docServer.exists) {
            final serverData = docServer.data()!;
            final serverLastModified = (serverData['lastModified'] as firestore.Timestamp?)?.toDate();
            
            // >>> CORREÇÃO 2: LÓGICA DE PRIORIDADE PARA CUBAGENS MEDIDAS <<<
            final double alturaServer = (serverData['alturaTotal'] as num?)?.toDouble() ?? 0.0;
            
            if (cubagemLocal.alturaTotal > 0 && alturaServer == 0) {
               // Se eu medi e o servidor não, EU GANHO. (Ignora data)
               deveEnviar = true;
               debugPrint("--- [FORCE UPDATE] Cubagem concluída localmente. Forçando envio.");
            }
            else if (serverLastModified != null && cubagemLocal.lastModified != null && serverLastModified.isAfter(cubagemLocal.lastModified!)) {
              deveEnviar = false;
              conflicts.add(SyncConflict(
                type: ConflictType.cubagem,
                localData: cubagemLocal,
                serverData: CubagemArvore.fromMap(serverData),
                identifier: "Cubagem ${cubagemLocal.identificador}",
              ));
            }
          }
          if(deveEnviar){
             await _uploadCubagem(docRef, cubagemLocal);
          }
          await _cubagemRepository.markCubagemAsSynced(cubagemLocal.id!);
          processados++;
          falhasConsecutivas = 0;
          continue;
        } catch (e) {
          debugPrint("Falha ao enviar cubagem ${cubagemLocal.id}: $e");
          _progressStreamController.add(SyncProgress(
            mensagem: "Erro ao enviar cubagem ${cubagemLocal.id}. Continuando...",
          ));
          falhasConsecutivas++;
          continue;
        }
      }

      // Se chegou aqui, não há mais itens para processar
      break;
    }

    if (falhasConsecutivas >= maxFalhasConsecutivas) {
      _progressStreamController.add(SyncProgress(
        erro: "Muitas falhas consecutivas. Verifique a conexão e sincronize novamente.",
        concluido: true,
      ));
    }
  }

  Future<void> _uploadParcela(firestore.DocumentReference docRef, Parcela parcela) async {
  // 1. Buscamos as árvores no SQLite para garantir que o pacote vá completo
  final arvores = await _parcelaRepository.getArvoresDaParcela(parcela.dbId!);
  final parcelaCompleta = parcela.copyWith(arvores: arvores);

  final Map<String, dynamic> parcelaMap = parcelaCompleta.toMap();
  final prefs = await SharedPreferences.getInstance();
  
  parcelaMap['nomeLider'] = parcela.nomeLider ?? prefs.getString('nome_lider');
  parcelaMap['lastModified'] = firestore.FieldValue.serverTimestamp();

  // 2. ENVIO ÚNICO: Removemos o "batch" daqui pois é apenas 1 documento
  await docRef.set(parcelaMap, firestore.SetOptions(merge: true));
  
  debugPrint("--- [SYNC] Parcela ${parcela.idParcela} enviada com sucesso (Compactada).");
}     
  
  Future<void> _uploadCubagem(firestore.DocumentReference docRef, CubagemArvore cubagem) async {
  final map = cubagem.toMap();
  
  // Transformamos a String do SQLite em Lista para o Firebase entender como Array
  if (map['secoes'] is String) {
    map['secoes'] = jsonDecode(map['secoes']);
  }
  
  map['lastModified'] = firestore.FieldValue.serverTimestamp();
  await docRef.set(map, firestore.SetOptions(merge: true));
}
  
  Future<void> _upsert(DatabaseExecutor txn, String table, Map<String, dynamic> data, String primaryKey, {String? secondaryKey}) async {
      List<dynamic> whereArgs = [data[primaryKey]];
      String whereClause = '$primaryKey = ?';
      if (secondaryKey != null) {
          whereClause += ' AND $secondaryKey = ?';
          whereArgs.add(data[secondaryKey]);
      }
      final existing = await txn.query(table, where: whereClause, whereArgs: whereArgs, limit: 1);
      if (existing.isNotEmpty) {
          final localLastModified = DateTime.tryParse(existing.first['lastModified']?.toString() ?? '');
          final serverLastModified = DateTime.tryParse(data['lastModified']?.toString() ?? '');
          
          bool deveAtualizar = false;
          
          if (serverLastModified != null && (localLastModified == null || serverLastModified.isAfter(localLastModified))) {
             deveAtualizar = true;
          } 
          // >>> CORREÇÃO 3: LÓGICA DE PRIORIDADE NO DOWNLOAD TAMBÉM <<<
          // Se o servidor diz que está concluído e eu não, o servidor ganha.
          else if (table == 'parcelas') {
             final statusLocal = existing.first['status']?.toString().toLowerCase();
             final statusServer = data['status']?.toString().toLowerCase();
             if (statusLocal != 'concluida' && statusServer == 'concluida') {
                deveAtualizar = true;
             }
          }

          if (deveAtualizar) {
            await txn.update(table, data, where: whereClause, whereArgs: whereArgs);
          }
      } else {
          await txn.insert(table, data);
      }
  }

  Future<List<int>> _downloadHierarquiaCompleta(String licenseId, {List<int>? projetosParaBaixar}) async {
    final db = await _dbHelper.database;
    final List<int> downloadedTalhaoIds = [];

    firestore.Query projetosQuery = _firestore.collection('clientes').doc(licenseId).collection('projetos');
    
    if (projetosParaBaixar != null && projetosParaBaixar.isNotEmpty) {
      for (var chunk in projetosParaBaixar.slices(10)) {
        final snap = await projetosQuery.where(firestore.FieldPath.documentId, whereIn: chunk.map((id) => id.toString()).toList()).get();
        for (var projDoc in snap.docs) {
          final talhaoIds = await _processarProjetoDaNuvem(projDoc, licenseId, db);
          downloadedTalhaoIds.addAll(talhaoIds);
        }
      }
    } else {
      // Só baixa projetos ativos — finalizados/arquivados/deletados ficam de fora
      final snap = await projetosQuery.where('status', isEqualTo: 'ativo').get();
      for (var projDoc in snap.docs) {
        final talhaoIds = await _processarProjetoDaNuvem(projDoc, licenseId, db);
        downloadedTalhaoIds.addAll(talhaoIds);
      }
    }
    return downloadedTalhaoIds;
  }

  Future<List<int>> _processarProjetoDaNuvem(firestore.QueryDocumentSnapshot projDoc, String licenseIdDeOrigem, Database db) async {
    try {
      final projetoData = projDoc.data() as Map<String, dynamic>; 
      final user = _auth.currentUser;
      
      if (user != null) {
        final licenseInfo = await _licensingService.findLicenseDocumentForUser(user);
        final meuLicenseId = licenseInfo?.id;

        if (meuLicenseId != null && licenseIdDeOrigem != meuLicenseId) {
            debugPrint("--- [SYNC] Marcando projeto ${projetoData['nome']} como DELEGADO de $licenseIdDeOrigem");
            projetoData['delegado_por_license_id'] = licenseIdDeOrigem;
        }
      }

      final projeto = Projeto.fromMap(projetoData);
      await db.transaction((txn) async {
          await _upsert(txn, 'projetos', projeto.toMap(), 'id');
      });
      
      return await _downloadFilhosDeProjeto(licenseIdDeOrigem, projeto.id!);

    } catch (e) {
      debugPrint("ERRO CRÍTICO ao processar projeto delegado (${projDoc.id}): $e");
      return []; 
    }
  }
  
  void _emitDownloadProgress(String label) {
    _progressStreamController.add(SyncProgress(
      mensagem: label,
      isDownloading: true,
      totalDownload: _downloadTotal,
      downloadados: _downloadados,
    ));
  }

  Future<void> _downloadColetas(String licenseId, {required List<int> talhaoIdsParaBaixar}) async {
    if (talhaoIdsParaBaixar.isEmpty) return;

    // Coleta todos os docs numa passagem só (sem gravar no banco) para saber o total
    final parcelaDocs = <firestore.QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final cubagemDocs = <firestore.QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (var chunk in talhaoIdsParaBaixar.slices(10)) {
      final pSnap = await _firestore
          .collection('clientes').doc(licenseId).collection('dados_coleta')
          .where('talhaoId', whereIn: chunk).get();
      parcelaDocs.addAll(pSnap.docs);
      final cSnap = await _firestore
          .collection('clientes').doc(licenseId).collection('dados_cubagem')
          .where('talhaoId', whereIn: chunk).get();
      cubagemDocs.addAll(cSnap.docs);
    }
    _downloadTotal += parcelaDocs.length + cubagemDocs.length;
    _emitDownloadProgress("Baixando dados da nuvem...");

    await _downloadParcelasDaNuvem(parcelaDocs);
    await _downloadCubagensDaNuvem(cubagemDocs);
  }
  
  Future<List<int>> _downloadFilhosDeProjeto(String licenseId, int projetoId) async {
    final db = await _dbHelper.database;
    final List<int> downloadedTalhaoIds = [];

    final atividadesSnap = await _firestore.collection('clientes').doc(licenseId).collection('atividades').where('projetoId', isEqualTo: projetoId).get();
    if (atividadesSnap.docs.isEmpty) return [];
    for (var ativDoc in atividadesSnap.docs) {
      final atividade = Atividade.fromMap(ativDoc.data());
      await db.transaction((txn) async { await _upsert(txn, 'atividades', atividade.toMap(), 'id'); });
      final fazendasSnap = await _firestore.collection('clientes').doc(licenseId).collection('fazendas').where('atividadeId', isEqualTo: atividade.id).get();
      for (var fazendaDoc in fazendasSnap.docs) {
        final fazenda = Fazenda.fromMap(fazendaDoc.data());
        await db.transaction((txn) async { await _upsert(txn, 'fazendas', fazenda.toMap(), 'id', secondaryKey: 'atividadeId'); });
        final talhoesSnap = await _firestore.collection('clientes').doc(licenseId).collection('talhoes').where('fazendaId', isEqualTo: fazenda.id).where('fazendaAtividadeId', isEqualTo: fazenda.atividadeId).get();
        for (var talhaoDoc in talhoesSnap.docs) {
          final data = talhaoDoc.data();
          data['projetoId'] = atividade.projetoId; 
          final talhao = Talhao.fromMap(data);
          await db.transaction((txn) async { await _upsert(txn, 'talhoes', talhao.toMap(), 'id'); });
          if (talhao.id != null) {
            downloadedTalhaoIds.add(talhao.id!);
          }
        }
      }
    }
    return downloadedTalhaoIds;
  }
  
  Future<void> _downloadParcelasDaNuvem(List<firestore.QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (docs.isEmpty) return;
    final db = await _dbHelper.database;
    for (final docSnapshot in docs) {
      final dadosDaNuvem = docSnapshot.data();
      final parcelaDaNuvem = Parcela.fromMap(dadosDaNuvem);
      bool salvouComSucesso = false;
      await db.transaction((txn) async {
        try {
          // 1. Verifica conflitos locais
          final parcelaLocalResult = await txn.query('parcelas', where: 'uuid = ?', whereArgs: [parcelaDaNuvem.uuid], limit: 1);
          if (parcelaLocalResult.isNotEmpty && parcelaLocalResult.first['isSynced'] == 0) {
            final statusLocal = parcelaLocalResult.first['status']?.toString().toLowerCase();
            final statusNuvem = parcelaDaNuvem.status.name.toLowerCase();
            if (!(statusLocal != 'concluida' && statusNuvem == 'concluida')) {
              debugPrint("PULANDO DOWNLOAD da parcela ${parcelaDaNuvem.idParcela} pois existem alterações locais não sincronizadas.");
              salvouComSucesso = true; // Pulado intencionalmente — não é erro
              return;
            }
          }
          // 2. Prepara arvores como JSON string (obrigatório para SQLite coluna TEXT)
          final rawArvores = dadosDaNuvem['arvores'];
          final String arvoresJson;
          if (rawArvores is List) {
            arvoresJson = jsonEncode(rawArvores);
          } else if (rawArvores is String) {
            arvoresJson = rawArvores;
          } else {
            arvoresJson = jsonEncode(parcelaDaNuvem.arvores.map((a) => a.toMap()).toList());
          }

          // 3. Salva a Parcela (cabeçalho)
          final pMap = parcelaDaNuvem.toMap();
          pMap['arvores'] = arvoresJson;
          pMap['isSynced'] = 1;
          await _upsert(txn, 'parcelas', pMap, 'uuid');

          // 4. Recupera o ID local e desempacota árvores na tabela relacional
          final idLocal = (await txn.query('parcelas', where: 'uuid = ?', whereArgs: [parcelaDaNuvem.uuid], limit: 1))
              .map((map) => Parcela.fromMap(map)).first.dbId!;

          var listaArvores = rawArvores;
          if (listaArvores is String) {
            try { listaArvores = jsonDecode(listaArvores); } catch (_) { listaArvores = []; }
          }
          if (listaArvores is List && listaArvores.isNotEmpty) {
            await txn.delete('arvores', where: 'parcelaId = ?', whereArgs: [idLocal]);
            for (var item in listaArvores) {
              if (item is Map<String, dynamic>) {
                final arvoreDbMap = Arvore.fromMap(item).toMap();
                arvoreDbMap['parcelaId'] = idLocal;
                arvoreDbMap.remove('id');
                arvoreDbMap['lastModified'] = DateTime.now().toIso8601String();
                await txn.insert('arvores', arvoreDbMap);
              }
            }
          }
          salvouComSucesso = true;
        } catch (e, s) {
          debugPrint("Erro CRÍTICO ao sincronizar parcela ${parcelaDaNuvem.uuid}: $e\n$s");
        }
      });
      if (salvouComSucesso) {
        _downloadados++;
        _emitDownloadProgress("Baixando amostras...");
      }
    }
  }
   
  Future<void> _downloadCubagensDaNuvem(
    List<firestore.QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (docs.isEmpty) return;
    final db = await _dbHelper.database;
    for (final docSnapshot in docs) {
      final dadosDaNuvem = docSnapshot.data();
      final cubagemDaNuvem = CubagemArvore.fromMap(dadosDaNuvem);
      bool salvouComSucesso = false;
      await db.transaction((txn) async {
        try {
          final rawSecoes = dadosDaNuvem['secoes'];
          final String secoesJson;
          if (rawSecoes is List) {
            secoesJson = jsonEncode(rawSecoes);
          } else if (rawSecoes is String) {
            secoesJson = rawSecoes;
          } else {
            secoesJson = jsonEncode([]);
          }

          final cMap = cubagemDaNuvem.toMap();
          cMap['secoes'] = secoesJson;
          cMap['isSynced'] = 1;
          await _upsert(txn, 'cubagens_arvores', cMap, 'id');
          await txn.delete('cubagens_secoes', where: 'cubagemArvoreId = ?', whereArgs: [cubagemDaNuvem.id]);

          var listaSecoes = rawSecoes;
          if (listaSecoes is String) {
            try { listaSecoes = jsonDecode(listaSecoes); } catch (_) { listaSecoes = []; }
          }
          bool secoesInseridasViaJson = false;
          if (listaSecoes is List && listaSecoes.isNotEmpty) {
            for (var secMap in listaSecoes) {
              if (secMap is Map<String, dynamic>) {
                final secaoDbMap = CubagemSecao.fromMap(secMap).toMap();
                secaoDbMap['cubagemArvoreId'] = cubagemDaNuvem.id;
                secaoDbMap.remove('id');
                secaoDbMap['lastModified'] = DateTime.now().toIso8601String();
                await txn.insert('cubagens_secoes', secaoDbMap);
              }
            }
            secoesInseridasViaJson = true;
          }
          if (!secoesInseridasViaJson) {
            final secoesSnapshot = await docSnapshot.reference.collection('secoes').get();
            if (secoesSnapshot.docs.isNotEmpty) {
              for (final doc in secoesSnapshot.docs) {
                final secaoDbMap = CubagemSecao.fromMap(doc.data()).toMap();
                secaoDbMap['cubagemArvoreId'] = cubagemDaNuvem.id;
                await txn.insert('cubagens_secoes', secaoDbMap, conflictAlgorithm: ConflictAlgorithm.replace);
              }
            }
          }
          salvouComSucesso = true;
        } catch (e, s) {
          debugPrint("Erro CRÍTICO ao sincronizar cubagem ${cubagemDaNuvem.id}: $e\n$s");
        }
      });
      if (salvouComSucesso) {
        _downloadados++;
        _emitDownloadProgress("Baixando cubagens...");
      }
    }
  }
  
  Future<void> atualizarStatusProjetoNaFirebase(String projetoId, String novoStatus) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Usuário não está logado.");
    final licenseDoc = await _licensingService.findLicenseDocumentForUser(user);
    if (licenseDoc == null) throw Exception("Não foi possível encontrar a licença para atualizar o projeto.");
    final licenseId = licenseDoc.id;
    final projetoRef = _firestore.collection('clientes').doc(licenseId).collection('projetos').doc(projetoId);
    await projetoRef.update({'status': novoStatus});
  }


  Future<void> sincronizarDiarioDeCampo(DiarioDeCampo diario) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Usuário não está logado.");
    final licenseDoc = await _licensingService.findLicenseDocumentForUser(user);
    if (licenseDoc == null) throw Exception("Licença do usuário não encontrada.");
    final licenseId = licenseDoc.id;
    final docId = '${diario.dataRelatorio}_${diario.nomeLider.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-')}';
    final docRef = _firestore.collection('clientes').doc(licenseId).collection('diarios_de_campo').doc(docId);
    final diarioMap = diario.toMap();
    diarioMap['lastModifiedServer'] = firestore.FieldValue.serverTimestamp();
    await docRef.set(diarioMap, firestore.SetOptions(merge: true));
  }
}
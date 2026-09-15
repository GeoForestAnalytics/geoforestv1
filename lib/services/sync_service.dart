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
import 'package:geoforestv1/data/repositories/pilha_repository.dart';
import 'package:geoforestv1/data/repositories/estoque_repository.dart';
import 'package:geoforestv1/data/repositories/silvi_repository.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/models/pilha_madeira_model.dart';
import 'package:geoforestv1/models/estoque_saida_model.dart';
import 'package:geoforestv1/models/silvi_model.dart';
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
  final _pilhaRepository = PilhaRepository();
  final _estoqueRepository = EstoqueRepository();
  final _silviRepository = SilviRepository();
  final _projetoRepository = ProjetoRepository();
  
  final StreamController<SyncProgress> _progressStreamController = StreamController.broadcast();
  Stream<SyncProgress> get progressStream => _progressStreamController.stream;

  final List<SyncConflict> conflicts = [];
  bool _isCancelled = false;
  int _downloadTotal = 0;
  int _downloadados = 0;
  String _userModulo = 'todos';

  static const _tiposColheita = {'PILHA', 'COLHEITA', 'PILHAS'};
  static const _tiposSilvi = {'SILVI', 'SILVICULTURA'};

  bool _tipoMatchesModulo(String tipo) {
    if (_userModulo == 'todos') return true;
    final t = tipo.toUpperCase();
    switch (_userModulo) {
      case 'colheita': return _tiposColheita.contains(t);
      case 'silvicultura': return _tiposSilvi.contains(t);
      default: return !_tiposColheita.contains(t) && !_tiposSilvi.contains(t);
    }
  }

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
      
      // Reativa cubagens importadas via CSV que têm seções locais mas secoes='[]'
      await _cubagemRepository.reativarCubagensComSecoesLocais();

      final totalParcelas = (await _parcelaRepository.getUnsyncedParcelas()).length;
      final totalCubagens = (await _cubagemRepository.getUnsyncedCubagens()).length;
      final totalPilhas = await _pilhaRepository.getUnsyncedPilhasCount();
      final totalEstoques = await _estoqueRepository.getUnsyncedEstoquesCount();
      final totalSilvi = await _silviRepository.getUnsyncedOperacoesCount();
      final totalGeral = totalParcelas + totalCubagens + totalPilhas + totalEstoques + totalSilvi;

      debugPrint("--- [SYNC] Pendentes: $totalParcelas parcelas, $totalCubagens cubagens, $totalPilhas pilhas, $totalEstoques estoques, $totalSilvi silvi");
      _progressStreamController.add(SyncProgress(totalAProcessar: totalGeral, mensagem: "Preparando: $totalParcelas parcelas, $totalCubagens cubagens, $totalPilhas pilhas, $totalEstoques estoques, $totalSilvi silvi pendentes..."));

      String cargo = 'equipe';
      _userModulo = 'todos';
      if (licenseIdDoUsuarioLogado != null) {
        final usuariosMap = licenseDoc!.data()!['usuariosPermitidos'] as Map<String, dynamic>?;
        cargo = usuariosMap?[user.uid]?['cargo'] ?? 'equipe';
        _userModulo = usuariosMap?[user.uid]?['modulo'] ?? 'todos';
        debugPrint("--- [SYNC] Módulo do usuário: $_userModulo, Cargo: $cargo");
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
        var idsParaBaixar = await _downloadHierarquiaCompleta(licenseIdDoUsuarioLogado, isGerente: cargo == 'gerente');
        // Fallback: se a hierarquia não retornou IDs (docs sem campo 'status', rede lenta, etc.)
        // usa os talhões que já existem localmente para tentar baixar as coletas
        if (idsParaBaixar.isEmpty) {
          debugPrint("--- SyncService: Hierarquia retornou 0 IDs. Usando talhões locais como fallback.");
          idsParaBaixar = await _getTodosOsTalhaoIdsLocais();
        }
        await _downloadColetas(licenseIdDoUsuarioLogado, talhaoIdsParaBaixar: idsParaBaixar);
      }

      final projetosDelegados = await _buscarProjetosDelegadosParaUsuario(user.uid);
      for (final entry in projetosDelegados.entries) {
        final licenseIdDoCliente = entry.key;
        final projetosParaBaixar = entry.value;
        debugPrint("--- SyncService: Baixando dados delegados da licença do CLIENTE: $licenseIdDoCliente para os projetos $projetosParaBaixar");

        // Projetos delegados: coletores só recebem projetos ativos (não finalizados)
        final idsHierarquiaDelegada = await _downloadHierarquiaCompleta(licenseIdDoCliente, projetosParaBaixar: projetosParaBaixar, isGerente: cargo == 'gerente');
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

  Future<List<int>> _getTodosOsTalhaoIdsLocais() async {
    final db = await _dbHelper.database;
    final result = await db.query('talhoes', columns: ['id']);
    return result.map((r) => r['id'] as int).toList();
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

          final talhaoIdsEnviados = <int>[];
          for (var t in talhoesParaEnviar) {
              final docRef = _firestore.collection('clientes').doc(licenseIdDeDestino).collection('talhoes').doc(t['id'].toString());
              final talhaoObj = Talhao.fromMap(t);
              final map = talhaoObj.toFirestoreMap();
              map['lastModified'] = firestore.FieldValue.serverTimestamp();
              batch.set(docRef, map, firestore.SetOptions(merge: true));
              talhaoIdsEnviados.add(t['id'] as int);
          }

          // ── Upload centroides de pilha (OS de colheita) ──────────────
          if (talhaoIdsEnviados.isNotEmpty) {
              for (final chunk in talhaoIdsEnviados.slices(10)) {
                  final centroides = await db.query(
                      DbCentroidesPilha.tableName,
                      where: 'talhaoId IN (${chunk.join(',')})',
                  );
                  for (var c in centroides) {
                      final docRef = _firestore
                          .collection('clientes')
                          .doc(licenseIdDeDestino)
                          .collection('centroides_pilha')
                          .doc(c[DbCentroidesPilha.id].toString());
                      final map = Map<String, dynamic>.from(c);
                      map['lastModified'] = firestore.FieldValue.serverTimestamp();
                      batch.set(docRef, map, firestore.SetOptions(merge: true));
                  }

                  // ── Upload centroides de silvicultura (OS de silvi) ──────
                  final centroidesSilvi = await db.query(
                      DbCentroidesSilvi.tableName,
                      where: '${DbCentroidesSilvi.talhaoId} IN (${chunk.join(',')})',
                  );
                  for (var c in centroidesSilvi) {
                      final docRef = _firestore
                          .collection('clientes')
                          .doc(licenseIdDeDestino)
                          .collection('centroides_silvi')
                          .doc(c[DbCentroidesSilvi.id].toString());
                      final map = Map<String, dynamic>.from(c);
                      map['lastModified'] = firestore.FieldValue.serverTimestamp();
                      batch.set(docRef, map, firestore.SetOptions(merge: true));
                  }
              }
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

      // --- PARCELAS (apenas inventário/todos) ---
      if (_userModulo == 'todos' || _userModulo == 'inventario') {
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
                 deveEnviar = true;
                 debugPrint("--- [FORCE UPDATE] Parcela concluída localmente. Forçando envio sobre versão pendente do servidor.");
              } else if (serverLastModified != null && parcelaLocal.lastModified != null && serverLastModified.isAfter(parcelaLocal.lastModified!)) {
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
      }

      // --- CUBAGENS (apenas inventário/todos) ---
      if (_userModulo == 'todos' || _userModulo == 'inventario') {
        final cubagemLocal = await _cubagemRepository.getOneUnsyncedCubagem();
        if (cubagemLocal != null) {
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
                 deveEnviar = true;
                 debugPrint("--- [FORCE UPDATE] Cubagem concluída localmente. Forçando envio.");
              } else if (serverLastModified != null && cubagemLocal.lastModified != null && serverLastModified.isAfter(cubagemLocal.lastModified!)) {
                deveEnviar = false;
                conflicts.add(SyncConflict(
                  type: ConflictType.cubagem,
                  localData: cubagemLocal,
                  serverData: CubagemArvore.fromMap(serverData),
                  identifier: "Cubagem ${cubagemLocal.identificador}",
                ));
              }
            }
            if (deveEnviar) {
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
      }

      // --- PILHAS (apenas colheita/todos) ---
      if (_userModulo == 'todos' || _userModulo == 'colheita') {
        try {
          final pilhaLocal = await _pilhaRepository.getOneUnsyncedPilha();
          if (pilhaLocal != null) {
            if (licenseIdDoUsuarioLogado == null) throw Exception("Licença de destino não encontrada para a pilha ${pilhaLocal.id}.");
            final docRef = _firestore
                .collection('clientes')
                .doc(licenseIdDoUsuarioLogado)
                .collection('dados_pilhas')
                .doc(pilhaLocal.id.toString());
            await _uploadPilha(docRef, pilhaLocal);
            await _pilhaRepository.markPilhaAsSynced(pilhaLocal.id!);
            processados++;
            falhasConsecutivas = 0;
            continue;
          }
        } catch (e) {
          debugPrint("Falha ao enviar pilha: $e");
          _progressStreamController.add(SyncProgress(
            mensagem: "Erro ao enviar pilha. Continuando...",
          ));
          falhasConsecutivas++;
          continue;
        }
      }

      // --- ESTOQUES DE SAÍDA (apenas colheita/todos) ---
      if (_userModulo == 'todos' || _userModulo == 'colheita') {
        try {
          final estoqueLocal = await _estoqueRepository.getOneUnsyncedEstoque();
          if (estoqueLocal != null) {
            if (licenseIdDoUsuarioLogado == null) throw Exception("Licença não encontrada para estoque ${estoqueLocal.id}.");
            final docRef = _firestore
                .collection('clientes')
                .doc(licenseIdDoUsuarioLogado)
                .collection('dados_estoques')
                .doc(estoqueLocal.id.toString());
            await _uploadEstoque(docRef, estoqueLocal);
            await _estoqueRepository.markEstoqueAsSynced(estoqueLocal.id!);
            processados++;
            falhasConsecutivas = 0;
            continue;
          }
        } catch (e) {
          debugPrint("Falha ao enviar estoque: $e");
          _progressStreamController.add(SyncProgress(mensagem: "Erro ao enviar estoque. Continuando..."));
          falhasConsecutivas++;
          continue;
        }
      }

      // --- OPERAÇÕES SILVI (apenas silvicultura/todos) ---
      if (_userModulo == 'todos' || _userModulo == 'silvicultura') {
        try {
          final silviLocal = await _silviRepository.getOneUnsyncedOperacao();
          if (silviLocal != null) {
            if (licenseIdDoUsuarioLogado == null) throw Exception("Licença não encontrada para operação silvi ${silviLocal.id}.");
            final docRef = _firestore
                .collection('clientes')
                .doc(licenseIdDoUsuarioLogado)
                .collection('dados_operacoes_silvi')
                .doc(silviLocal.id.toString());
            await _uploadOperacaoSilvi(docRef, silviLocal);
            await _silviRepository.markOperacaoAsSynced(silviLocal.id!);
            processados++;
            falhasConsecutivas = 0;
            continue;
          }
        } catch (e) {
          debugPrint("Falha ao enviar operação silvi: $e");
          _progressStreamController.add(SyncProgress(mensagem: "Erro ao enviar operação silvi. Continuando..."));
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
  
  Future<void> _uploadPilha(firestore.DocumentReference docRef, PilhaMadeira pilha) async {
    final map = pilha.toMap();
    if (map[DbPilhasMadeira.secoes] is String) {
      map[DbPilhasMadeira.secoes] = jsonDecode(map[DbPilhasMadeira.secoes] as String);
    }
    final liderSalvo = map[DbPilhasMadeira.nomeLider];
    if (liderSalvo == null || (liderSalvo as String).isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      map[DbPilhasMadeira.nomeLider] = prefs.getString('nome_lider');
    }
    map['lastModified'] = firestore.FieldValue.serverTimestamp();
    await docRef.set(map, firestore.SetOptions(merge: true));
    debugPrint("--- [SYNC] Pilha ${pilha.id} enviada com sucesso.");
  }

  Future<void> _uploadEstoque(firestore.DocumentReference docRef, EstoqueSaida estoque) async {
    final map = estoque.toMap();
    final liderSalvo = map[DbEstoqueSaida.nomeLider];
    if (liderSalvo == null || (liderSalvo as String).isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      map[DbEstoqueSaida.nomeLider] = prefs.getString('nome_lider');
    }
    map['lastModified'] = firestore.FieldValue.serverTimestamp();
    await docRef.set(map, firestore.SetOptions(merge: true));
    debugPrint("--- [SYNC] Estoque ${estoque.id} enviado com sucesso.");
  }

  Future<void> _uploadOperacaoSilvi(firestore.DocumentReference docRef, OperacaoSilvi op) async {
    final map = op.toMap();
    final liderSalvo = map[DbOperacoesSilvi.nomeLider];
    if (liderSalvo == null || (liderSalvo as String).isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      map[DbOperacoesSilvi.nomeLider] = prefs.getString('nome_lider');
    }
    map['lastModified'] = firestore.FieldValue.serverTimestamp();
    await docRef.set(map, firestore.SetOptions(merge: true));
    debugPrint("--- [SYNC] Operação silvi ${op.id} enviada com sucesso.");
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

  Future<List<int>> _downloadHierarquiaCompleta(String licenseId, {List<int>? projetosParaBaixar, bool isGerente = false}) async {
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
      // Baixa todos os projetos — filtra deletados localmente.
      // Não filtra por 'status' no Firestore porque docs antigos podem não ter esse campo,
      // o que faria a query retornar vazia e pular o download de coletas.
      final snap = await projetosQuery.get();
      for (var projDoc in snap.docs) {
        final data = projDoc.data() as Map<String, dynamic>;
        final status = (data['status'] as String?)?.toLowerCase();
        if (status == 'deletado') continue;
        // Coletores não recebem projetos finalizados
        if (!isGerente && status == 'finalizado') continue;
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
    final pilhaDocs = <firestore.QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final estoqueDocs = <firestore.QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final silviDocs = <firestore.QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final baixaInv = _userModulo == 'todos' || _userModulo == 'inventario';
    final baixaCol = _userModulo == 'todos' || _userModulo == 'colheita';
    final baixaSil = _userModulo == 'todos' || _userModulo == 'silvicultura';
    for (var chunk in talhaoIdsParaBaixar.slices(10)) {
      if (baixaInv) {
        try {
          final pSnap = await _firestore
              .collection('clientes').doc(licenseId).collection('dados_coleta')
              .where('talhaoId', whereIn: chunk).get();
          parcelaDocs.addAll(pSnap.docs);
        } catch (e) { debugPrint("Erro ao buscar dados_coleta: $e"); }

        try {
          final cSnap = await _firestore
              .collection('clientes').doc(licenseId).collection('dados_cubagem')
              .where('talhaoId', whereIn: chunk).get();
          cubagemDocs.addAll(cSnap.docs);
        } catch (e) { debugPrint("Erro ao buscar dados_cubagem: $e"); }
      }

      if (baixaCol) {
        try {
          final piSnap = await _firestore
              .collection('clientes').doc(licenseId).collection('dados_pilhas')
              .where('talhaoId', whereIn: chunk).get();
          pilhaDocs.addAll(piSnap.docs);
        } catch (e) { debugPrint("Erro ao buscar dados_pilhas: $e"); }

        try {
          final eSnap = await _firestore
              .collection('clientes').doc(licenseId).collection('dados_estoques')
              .where(DbEstoqueSaida.talhaoId, whereIn: chunk).get();
          estoqueDocs.addAll(eSnap.docs);
        } catch (e) { debugPrint("Erro ao buscar dados_estoques: $e"); }
      }

      if (baixaSil) {
        try {
          final sSnap = await _firestore
              .collection('clientes').doc(licenseId).collection('dados_operacoes_silvi')
              .where(DbOperacoesSilvi.talhaoId, whereIn: chunk).get();
          silviDocs.addAll(sSnap.docs);
        } catch (e) { debugPrint("Erro ao buscar dados_operacoes_silvi: $e"); }
      }
    }
    _downloadTotal += parcelaDocs.length + cubagemDocs.length + pilhaDocs.length + estoqueDocs.length + silviDocs.length;
    _emitDownloadProgress("Baixando dados da nuvem...");

    await _downloadParcelasDaNuvem(parcelaDocs);
    await _downloadCubagensDaNuvem(cubagemDocs);
    await _downloadPilhasDaNuvem(pilhaDocs);
    await _downloadEstoquesDaNuvem(estoqueDocs);
    await _downloadOperacoesSilviDaNuvem(silviDocs);
  }
  
  Future<List<int>> _downloadFilhosDeProjeto(String licenseId, int projetoId) async {
    final db = await _dbHelper.database;
    final List<int> downloadedTalhaoIds = [];

    final atividadesSnap = await _firestore.collection('clientes').doc(licenseId).collection('atividades').where('projetoId', isEqualTo: projetoId).get();
    if (atividadesSnap.docs.isEmpty) return [];
    for (var ativDoc in atividadesSnap.docs) {
      final atividade = Atividade.fromMap(ativDoc.data());
      if (!_tipoMatchesModulo(atividade.tipo)) continue;
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

    // ── Download centroides de pilha e silvicultura para os talhões ──────
    final baixaCentrPilha = _userModulo == 'todos' || _userModulo == 'colheita';
    final baixaCentrSilvi = _userModulo == 'todos' || _userModulo == 'silvicultura';
    for (final chunk in downloadedTalhaoIds.slices(10)) {
      // Centroides de pilha — apenas para módulo colheita/todos
      if (baixaCentrPilha) {
        try {
          final centroideSnap = await _firestore
              .collection('clientes')
              .doc(licenseId)
              .collection('centroides_pilha')
              .where(DbCentroidesPilha.talhaoId, whereIn: chunk)
              .get();
          for (final doc in centroideSnap.docs) {
            final data = Map<String, dynamic>.from(doc.data());
            final ts = data[DbCentroidesPilha.lastModified];
            if (ts is firestore.Timestamp) {
              data[DbCentroidesPilha.lastModified] = ts.toDate().toIso8601String();
            }
            await db.transaction((txn) async {
              await _upsert(txn, DbCentroidesPilha.tableName, data, DbCentroidesPilha.id);
            });
          }
        } catch (e) {
          debugPrint("Erro ao baixar centroides de pilha: $e");
        }
      }

      // Centroides de silvicultura — apenas para módulo silvicultura/todos
      if (baixaCentrSilvi) {
        try {
          final silviSnap = await _firestore
              .collection('clientes')
              .doc(licenseId)
              .collection('centroides_silvi')
              .where(DbCentroidesSilvi.talhaoId, whereIn: chunk)
              .get();
          for (final doc in silviSnap.docs) {
            final data = Map<String, dynamic>.from(doc.data());
            final ts = data[DbCentroidesSilvi.lastModified];
            if (ts is firestore.Timestamp) {
              data[DbCentroidesSilvi.lastModified] = ts.toDate().toIso8601String();
            }
            await db.transaction((txn) async {
              await _upsert(txn, DbCentroidesSilvi.tableName, data, DbCentroidesSilvi.id);
            });
          }
        } catch (e) {
          debugPrint("Erro ao baixar centroides de silvi: $e");
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
          var listaSecoes = rawSecoes;
          if (listaSecoes is String) {
            try { listaSecoes = jsonDecode(listaSecoes); } catch (_) { listaSecoes = []; }
          }
          bool secoesInseridasViaJson = false;
          if (listaSecoes is List && listaSecoes.isNotEmpty) {
            // Só apaga seções locais se o Firestore tem seções para repor
            await txn.delete('cubagens_secoes', where: 'cubagemArvoreId = ?', whereArgs: [cubagemDaNuvem.id]);
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
              await txn.delete('cubagens_secoes', where: 'cubagemArvoreId = ?', whereArgs: [cubagemDaNuvem.id]);
              for (final doc in secoesSnapshot.docs) {
                final secaoDbMap = CubagemSecao.fromMap(doc.data()).toMap();
                secaoDbMap['cubagemArvoreId'] = cubagemDaNuvem.id;
                await txn.insert('cubagens_secoes', secaoDbMap, conflictAlgorithm: ConflictAlgorithm.replace);
              }
            }
            // Se Firestore também não tem seções, preserva as locais
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
  
  Future<void> _downloadPilhasDaNuvem(
    List<firestore.QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (docs.isEmpty) return;
    final db = await _dbHelper.database;
    await _pilhaRepository.ensureSchema();
    for (final docSnapshot in docs) {
      final dadosDaNuvem = Map<String, dynamic>.from(docSnapshot.data());
      // Converte Timestamp do Firestore para ISO string antes de processar
      final ts = dadosDaNuvem[DbPilhasMadeira.lastModified];
      if (ts is firestore.Timestamp) {
        dadosDaNuvem[DbPilhasMadeira.lastModified] = ts.toDate().toIso8601String();
      }
      try {
        final rawSecoes = dadosDaNuvem[DbPilhasMadeira.secoes];
        final String secoesJson;
        if (rawSecoes is List) {
          secoesJson = jsonEncode(rawSecoes);
        } else if (rawSecoes is String) {
          secoesJson = rawSecoes;
        } else {
          secoesJson = jsonEncode([]);
        }

        final pMap = PilhaMadeira.fromMap(dadosDaNuvem).toMap();
        pMap[DbPilhasMadeira.secoes] = secoesJson;
        pMap[DbPilhasMadeira.isSynced] = 1;

        await db.transaction((txn) async {
          await _upsert(txn, DbPilhasMadeira.tableName, pMap, DbPilhasMadeira.id);
        });
        _downloadados++;
        _emitDownloadProgress("Baixando pilhas...");
      } catch (e, s) {
        debugPrint("Erro ao sincronizar pilha ${dadosDaNuvem['id']}: $e\n$s");
      }
    }
  }

  Future<void> _downloadEstoquesDaNuvem(
    List<firestore.QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (docs.isEmpty) return;
    final db = await _dbHelper.database;
    for (final doc in docs) {
      final data = Map<String, dynamic>.from(doc.data());
      final ts = data[DbEstoqueSaida.lastModified];
      if (ts is firestore.Timestamp) {
        data[DbEstoqueSaida.lastModified] = ts.toDate().toIso8601String();
      }
      try {
        // Injeta o ID do documento Firestore para que o upsert encontre o registro local
        data[DbEstoqueSaida.id] = int.tryParse(doc.id);
        final eMap = EstoqueSaida.fromMap(data).toMap();
        eMap[DbEstoqueSaida.isSynced] = 1;
        await db.transaction((txn) async {
          await _upsert(txn, DbEstoqueSaida.tableName, eMap, DbEstoqueSaida.id);
        });
        _downloadados++;
        _emitDownloadProgress("Baixando estoques...");
      } catch (e) {
        debugPrint("Erro ao sincronizar estoque ${data['id']}: $e");
      }
    }
  }

  Future<void> _downloadOperacoesSilviDaNuvem(
    List<firestore.QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (docs.isEmpty) return;
    final db = await _dbHelper.database;
    for (final doc in docs) {
      final data = Map<String, dynamic>.from(doc.data());
      final ts = data[DbOperacoesSilvi.lastModified];
      if (ts is firestore.Timestamp) {
        data[DbOperacoesSilvi.lastModified] = ts.toDate().toIso8601String();
      }
      try {
        data[DbOperacoesSilvi.id] = int.tryParse(doc.id);
        final op = OperacaoSilvi.fromMap(data);
        final opMap = op.toMap();
        opMap[DbOperacoesSilvi.isSynced] = 1;
        await db.transaction((txn) async {
          await _upsert(txn, DbOperacoesSilvi.tableName, opMap, DbOperacoesSilvi.id);
        });
        _downloadados++;
        _emitDownloadProgress("Baixando operações silvi...");
      } catch (e) {
        debugPrint("Erro ao sincronizar operação silvi ${data['id']}: $e");
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
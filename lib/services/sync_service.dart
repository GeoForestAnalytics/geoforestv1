// lib/services/sync_service.dart (VERSÃO COMPLETA E CORRIGIDA)

import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/cubagem_secao_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/services/licensing_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';

class SyncService {
  final firestore.FirebaseFirestore _firestore = firestore.FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final LicensingService _licensingService = LicensingService();
  
  final _parcelaRepository = ParcelaRepository();
  final _cubagemRepository = CubagemRepository();
  final _projetoRepository = ProjetoRepository();

  Future<void> sincronizarDados() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Usuário não está logado.");

    final licenseDoc = await _licensingService.findLicenseDocumentForUser(user);
    if (licenseDoc == null) {
      throw Exception("Não foi possível encontrar uma licença válida para sincronizar os dados.");
    }
    final licenseId = licenseDoc.id;
    final licenseData = licenseDoc.data()!;
    
    final usuariosPermitidos = licenseData['usuariosPermitidos'] as Map<String, dynamic>? ?? {};
    final dadosDoUsuario = usuariosPermitidos[user.uid] as Map<String, dynamic>?;
    final cargo = dadosDoUsuario?['cargo'] as String? ?? 'equipe';

    if (cargo == 'gerente') {
      debugPrint("Sincronização em modo GERENTE: Upload e Download completos.");
      await _uploadHierarquiaCompleta(licenseId);
      await _uploadColetasNaoSincronizadas(licenseId);
      await _downloadHierarquiaCompleta(licenseId);
      await _downloadProjetosDelegados(licenseId);
      await _downloadColetas(licenseId);
    } else {
      debugPrint("Sincronização em modo EQUIPE: Upload de coletas e Download geral.");
      await _uploadColetasNaoSincronizadas(licenseId);
      await _downloadHierarquiaCompleta(licenseId);
      await _downloadProjetosDelegados(licenseId);
      await _downloadColetas(licenseId);
    }
  }

  Future<void> _uploadHierarquiaCompleta(String licenseId) async {
    final db = await _dbHelper.database;
    final batch = _firestore.batch();
    
    final projetosProprios = await db.query('projetos', where: 'delegado_por_license_id IS NULL');
    if (projetosProprios.isEmpty) return;
    
    final projetosIds = projetosProprios.map((p) => p['id']).toList();

    for (var registro in projetosProprios) {
      final docRef = _firestore.collection('clientes').doc(licenseId).collection('projetos').doc(registro['id'].toString());
      batch.set(docRef, registro, firestore.SetOptions(merge: true));
    }

    if(projetosIds.isEmpty) {
        await batch.commit();
        debugPrint("Hierarquia de projetos próprios (sem atividades) enviada para a nuvem.");
        return;
    }

    final atividades = await db.query('atividades', where: 'projetoId IN (${projetosIds.join(',')})');
    final atividadeIds = atividades.map((a) => a['id']).toList();
    for (var a in atividades) {
        final docRef = _firestore.collection('clientes').doc(licenseId).collection('atividades').doc(a['id'].toString());
        batch.set(docRef, a, firestore.SetOptions(merge: true));
    }

    if (atividadeIds.isNotEmpty) {
        final fazendas = await db.query('fazendas', where: 'atividadeId IN (${atividadeIds.join(',')})');
        final fazendaIds = fazendas.map((f) => f['id'] as String).toList();
        for (var f in fazendas) {
            final docId = "${f['id']}_${f['atividadeId']}";
            final docRef = _firestore.collection('clientes').doc(licenseId).collection('fazendas').doc(docId);
            batch.set(docRef, f, firestore.SetOptions(merge: true));
        }

        if (fazendaIds.isNotEmpty) {
            final placeholders = List.filled(fazendaIds.length, '?').join(',');
            final talhoes = await db.query('talhoes', where: 'fazendaId IN ($placeholders)', whereArgs: fazendaIds);
            for (var t in talhoes) {
                final docRef = _firestore.collection('clientes').doc(licenseId).collection('talhoes').doc(t['id'].toString());
                batch.set(docRef, t, firestore.SetOptions(merge: true));
            }
        }
    }
    
    await batch.commit();
    debugPrint("Hierarquia de projetos próprios enviada para a nuvem.");
  }

  // <<< MÉTODO DE EXCLUSÃO COMPLETO E CORRIGIDO >>>
  Future<void> deletarProjetoCompletoDoFirebase(String licenseId, int projetoId) async {
    debugPrint("INICIANDO EXCLUSÃO REMOTA COMPLETA para o projeto $projetoId...");
    final clienteRef = _firestore.collection('clientes').doc(licenseId);
    
    // NOTA: O Firestore limita as operações em lote (batch) a 500.
    // Para projetos muito grandes, esta exclusão no cliente pode falhar.
    // A solução mais robusta para exclusões em cascata é usar uma Cloud Function.
    firestore.WriteBatch batch = _firestore.batch();
    int operationCount = 0;

    Future<void> commitBatchIfNeeded() async {
        if (operationCount >= 490) { // Deixa uma margem de segurança
            await batch.commit();
            batch = _firestore.batch();
            operationCount = 0;
            debugPrint(" > Lote de exclusão executado. Iniciando novo lote.");
        }
    }

    // 1. Encontrar todos os IDs de atividades, fazendas e talhões do projeto
    final atividadesSnap = await clienteRef.collection('atividades').where('projetoId', isEqualTo: projetoId).get();
    final List<int> atividadeIds = atividadesSnap.docs.map((doc) => doc.data()['id'] as int).toList();
    final List<int> talhaoIds = [];

    if (atividadeIds.isNotEmpty) {
        final fazendasSnap = await clienteRef.collection('fazendas').where('atividadeId', whereIn: atividadeIds).get();
        final List<String> fazendaIdsStr = fazendasSnap.docs.map((doc) => doc.data()['id'] as String).toList();
        
        if (fazendaIdsStr.isNotEmpty) {
            final talhoesSnap = await clienteRef.collection('talhoes').where('fazendaId', whereIn: fazendaIdsStr).get();
            for (final doc in talhoesSnap.docs) {
                talhaoIds.add(doc.data()['id'] as int);
            }
        }
    }

    // 2. Apagar todos os dados de COLETA (Parcelas e suas Árvores)
    if (talhaoIds.isNotEmpty) {
        final parcelasSnap = await clienteRef.collection('dados_coleta').where('talhaoId', whereIn: talhaoIds).get();
        for (final doc in parcelasSnap.docs) {
            final arvoresSnap = await doc.reference.collection('arvores').get();
            for (final arvDoc in arvoresSnap.docs) {
                batch.delete(arvDoc.reference);
                operationCount++;
                await commitBatchIfNeeded();
            }
            batch.delete(doc.reference);
            operationCount++;
            await commitBatchIfNeeded();
        }
        debugPrint(" > ${parcelasSnap.docs.length} parcelas e suas árvores marcadas para exclusão.");
        
        // 3. Apagar todos os dados de CUBAGEM (Cubagens e suas Seções)
        final cubagensSnap = await clienteRef.collection('dados_cubagem').where('talhaoId', whereIn: talhaoIds).get();
        for (final doc in cubagensSnap.docs) {
            final secoesSnap = await doc.reference.collection('secoes').get();
            for (final secDoc in secoesSnap.docs) {
                batch.delete(secDoc.reference);
                operationCount++;
                await commitBatchIfNeeded();
            }
            batch.delete(doc.reference);
            operationCount++;
            await commitBatchIfNeeded();
        }
        debugPrint(" > ${cubagensSnap.docs.length} cubagens e suas seções marcadas para exclusão.");
    }
    
    // 4. Apagar a hierarquia de metadados (Talhões, Fazendas, Atividades)
    for (final id in talhaoIds) {
      batch.delete(clienteRef.collection('talhoes').doc(id.toString()));
      operationCount++;
      await commitBatchIfNeeded();
    }
    // Repita para Fazendas e Atividades se eles tiverem IDs simples e conhecidos.
    // A busca anterior já os encontrou.
    if(atividadeIds.isNotEmpty) {
      final fazendasSnap = await clienteRef.collection('fazendas').where('atividadeId', whereIn: atividadeIds).get();
      for (final doc in fazendasSnap.docs) {
        batch.delete(doc.reference);
        operationCount++;
        await commitBatchIfNeeded();
      }
    }
    for (final doc in atividadesSnap.docs) {
      batch.delete(doc.reference);
      operationCount++;
      await commitBatchIfNeeded();
    }
    
    // 5. Apagar o projeto em si
    final projetoRef = clienteRef.collection('projetos').doc(projetoId.toString());
    batch.delete(projetoRef);
    operationCount++;
    debugPrint(" > Documento do projeto marcado para exclusão.");

    // 6. Executar o lote final de operações
    await batch.commit();
    debugPrint("EXCLUSÃO REMOTA CONCLUÍDA.");
  }

  Future<void> _uploadColetasNaoSincronizadas(String licenseIdDoUsuarioLogado) async {
    // ---- UPLOAD DE PARCELAS ----
    final List<Parcela> parcelasNaoSincronizadas = await _parcelaRepository.getUnsyncedParcelas();
    if (parcelasNaoSincronizadas.isNotEmpty) {
      final batch = _firestore.batch();
      final prefs = await SharedPreferences.getInstance();
      final nomeLider = prefs.getString('nome_lider');

      for (final parcela in parcelasNaoSincronizadas) {
        final projetoPai = await _projetoRepository.getProjetoPelaParcela(parcela);
        String? licenseIdDeDestino;

        if (projetoPai != null) {
          licenseIdDeDestino = projetoPai.delegadoPorLicenseId ?? projetoPai.licenseId;
          debugPrint("DIRECIONANDO Parcela ${parcela.idParcela} para licença: $licenseIdDeDestino");
        }

        if (licenseIdDeDestino == null) {
          debugPrint("AVISO: Não foi possível determinar a licença de destino para a parcela ${parcela.idParcela}. Pulando upload.");
          continue;
        }

        final docRef = _firestore.collection('clientes').doc(licenseIdDeDestino).collection('dados_coleta').doc(parcela.uuid);
        final parcelaMap = parcela.toMap();
        parcelaMap['nomeLider'] = nomeLider;
        batch.set(docRef, parcelaMap, firestore.SetOptions(merge: true));

        final arvores = await _parcelaRepository.getArvoresDaParcela(parcela.dbId!);
        for (final arvore in arvores) {
          final arvoreRef = docRef.collection('arvores').doc(arvore.id.toString());
          batch.set(arvoreRef, arvore.toMap());
        }
      }
      await batch.commit();
      for (final parcela in parcelasNaoSincronizadas) {
        await _parcelaRepository.markParcelaAsSynced(parcela.dbId!);
      }
      debugPrint("${parcelasNaoSincronizadas.length} parcelas locais foram sincronizadas.");
    }

    // ---- UPLOAD DE CUBAGENS ----
    final List<CubagemArvore> cubagensNaoSincronizadas = await _cubagemRepository.getUnsyncedCubagens();
    if (cubagensNaoSincronizadas.isNotEmpty) {
      final batch = _firestore.batch();
      for (final cubagem in cubagensNaoSincronizadas) {
        if (cubagem.id == null) continue;
        final projetoPai = await _projetoRepository.getProjetoPelaCubagem(cubagem);
        String? licenseIdDeDestino;

        if (projetoPai != null) {
          licenseIdDeDestino = projetoPai.delegadoPorLicenseId ?? projetoPai.licenseId;
        }
        
        if (licenseIdDeDestino == null) {
            debugPrint("AVISO: Não foi possível determinar a licença de destino para a cubagem ${cubagem.id}. Pulando upload.");
            continue;
        }
        
        final docRef = _firestore.collection('clientes').doc(licenseIdDeDestino).collection('dados_cubagem').doc(cubagem.id.toString());
        batch.set(docRef, cubagem.toMap(), firestore.SetOptions(merge: true));

        final secoes = await _cubagemRepository.getSecoesPorArvoreId(cubagem.id!);
        for (final secao in secoes) {
          final secaoRef = docRef.collection('secoes').doc(secao.id.toString());
          batch.set(secaoRef, secao.toMap());
        }
      }
      await batch.commit();
      for (final cubagem in cubagensNaoSincronizadas) {
        await _cubagemRepository.markCubagemAsSynced(cubagem.id!);
      }
      debugPrint("${cubagensNaoSincronizadas.length} cubagens locais foram sincronizadas.");
    }
  }
    
  Future<void> _downloadHierarquiaCompleta(String licenseId) async {
    final db = await _dbHelper.database;
    
    final projetosSnap = await _firestore.collection('clientes').doc(licenseId).collection('projetos').get();
    for (var doc in projetosSnap.docs) {
      final data = doc.data();
      data['licenseId'] = licenseId; 
      if (data['status'] != 'arquivado') {
        await db.insert('projetos', data, conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        await db.delete('projetos', where: 'id = ?', whereArgs: [data['id']]);
      }
    }
    
    final atividadesSnap = await _firestore.collection('clientes').doc(licenseId).collection('atividades').get();
    for (var doc in atividadesSnap.docs) {
      await db.insert('atividades', doc.data(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    
    final fazendasSnap = await _firestore.collection('clientes').doc(licenseId).collection('fazendas').get();
    for (var doc in fazendasSnap.docs) {
      await db.insert('fazendas', doc.data(), conflictAlgorithm: ConflictAlgorithm.replace);
    }

    final talhoesSnap = await _firestore.collection('clientes').doc(licenseId).collection('talhoes').get();
    for (var doc in talhoesSnap.docs) {
      await db.insert('talhoes', doc.data(), conflictAlgorithm: ConflictAlgorithm.replace);
    }

    debugPrint("Hierarquia da própria licença baixada localmente.");
  }

  Future<void> _downloadProjetosDelegados(String licenseIdDoUsuarioLogado) async {
    final db = await _dbHelper.database;
    final query = _firestore.collectionGroup('chavesDeDelegacao')
        .where('licenseIdConvidada', isEqualTo: licenseIdDoUsuarioLogado)
        .where('status', isEqualTo: 'ativa');
    
    final snapshot = await query.get();
    if (snapshot.docs.isEmpty) {
      debugPrint("Nenhum projeto delegado encontrado para baixar.");
      return;
    }

    for (final docChave in snapshot.docs) {
      final licenseIdDoCliente = docChave.reference.parent.parent!.id;
      final dataChave = docChave.data();
      final projetosPermitidosIds = (dataChave['projetosPermitidos'] as List<dynamic>).map((e) => e as int).toList();

      if (projetosPermitidosIds.isEmpty) continue;

      for (final projetoId in projetosPermitidosIds) {
        final projDoc = await _firestore.collection('clientes').doc(licenseIdDoCliente)
            .collection('projetos').doc(projetoId.toString()).get();
        
        if (projDoc.exists) {
          final projetoData = projDoc.data()!;
          projetoData['delegado_por_license_id'] = licenseIdDoCliente;
          
          await db.insert('projetos', projetoData, conflictAlgorithm: ConflictAlgorithm.replace);
          await _downloadFilhosDeProjeto(licenseIdDoCliente, projetoId);
        }
      }
    }
    debugPrint("Projetos delegados e sua hierarquia foram baixados com sucesso.");
  }

  Future<void> _downloadFilhosDeProjeto(String licenseIdDoCliente, int projetoId) async {
    final db = await _dbHelper.database;

    final atividadesSnap = await _firestore.collection('clientes').doc(licenseIdDoCliente)
        .collection('atividades').where('projetoId', isEqualTo: projetoId).get();
    
    final atividadeIds = <int>[];
    for (var doc in atividadesSnap.docs) {
      await db.insert('atividades', doc.data(), conflictAlgorithm: ConflictAlgorithm.replace);
      atividadeIds.add(doc.data()['id'] as int);
    }
    if (atividadeIds.isEmpty) return;
    
    final fazendasSnap = await _firestore.collection('clientes').doc(licenseIdDoCliente)
        .collection('fazendas').where('atividadeId', whereIn: atividadeIds).get();
    
    final fazendaIds = <String>[];
    for (var doc in fazendasSnap.docs) {
      await db.insert('fazendas', doc.data(), conflictAlgorithm: ConflictAlgorithm.replace);
      fazendaIds.add(doc.data()['id'] as String);
    }
    if (fazendaIds.isEmpty) return;

    final talhoesSnap = await _firestore.collection('clientes').doc(licenseIdDoCliente)
        .collection('talhoes').where('fazendaId', whereIn: fazendaIds).get();

    for (var doc in talhoesSnap.docs) {
      await db.insert('talhoes', doc.data(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _downloadColetas(String licenseId) async {
    await _downloadParcelasDaNuvem(licenseId);
    await _downloadCubagensDaNuvem(licenseId);
  }

  Future<void> _downloadParcelasDaNuvem(String licenseId) async {
    final querySnapshot = await _firestore.collection('clientes').doc(licenseId).collection('dados_coleta').get();
    if (querySnapshot.docs.isEmpty) return;

    final db = await _dbHelper.database;
    int novasParcelas = 0;
    int parcelasAtualizadas = 0;

    for (final docSnapshot in querySnapshot.docs) {
      final dadosDaNuvem = docSnapshot.data();
      final parcelaDaNuvem = Parcela.fromMap(dadosDaNuvem);
      
      final parcelaLocalResult = await db.query('parcelas', where: 'uuid = ?', whereArgs: [parcelaDaNuvem.uuid], limit: 1);
      
      await db.transaction((txn) async {
        try {
          final talhaoIdLocal = parcelaDaNuvem.talhaoId;
          if (talhaoIdLocal == null) return;
          
          final pMap = parcelaDaNuvem.toMap();
          pMap['isSynced'] = 1;
          
          if (parcelaLocalResult.isEmpty) {
            pMap.remove('id');
            final novoIdParcelaLocal = await txn.insert('parcelas', pMap);
            await _sincronizarArvores(txn, docSnapshot, novoIdParcelaLocal);
            novasParcelas++;
          } else {
            final parcelaLocal = Parcela.fromMap(parcelaLocalResult.first);
            pMap['id'] = parcelaLocal.dbId;
            await txn.update('parcelas', pMap, where: 'id = ?', whereArgs: [parcelaLocal.dbId]);
            await txn.delete('arvores', where: 'parcelaId = ?', whereArgs: [parcelaLocal.dbId]);
            await _sincronizarArvores(txn, docSnapshot, parcelaLocal.dbId!);
            parcelasAtualizadas++;
          }
        } catch (e, s) {
          debugPrint("Erro CRÍTICO ao sincronizar parcela ${parcelaDaNuvem.uuid}: $e\n$s");
        }
      });
    }
    if (novasParcelas > 0) debugPrint("$novasParcelas novas parcelas foram baixadas da nuvem.");
    if (parcelasAtualizadas > 0) debugPrint("$parcelasAtualizadas parcelas existentes foram atualizadas.");
  }
  
  Future<void> _sincronizarArvores(DatabaseExecutor txn, firestore.DocumentSnapshot docSnapshot, int idParcelaLocal) async {
      final arvoresSnapshot = await docSnapshot.reference.collection('arvores').get();
      if (arvoresSnapshot.docs.isNotEmpty) {
        final arvoresDaNuvem = arvoresSnapshot.docs.map((doc) => Arvore.fromMap(doc.data())).toList();
        for (final arvore in arvoresDaNuvem) {
          final aMap = arvore.toMap();
          aMap['parcelaId'] = idParcelaLocal;
          await txn.insert('arvores', aMap, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
  }
  
  Future<void> _downloadCubagensDaNuvem(String licenseId) async {
    final querySnapshot = await _firestore.collection('clientes').doc(licenseId).collection('dados_cubagem').get();
    if (querySnapshot.docs.isEmpty) return;

    final db = await _dbHelper.database;
    int novasCubagens = 0;

    for (final docSnapshot in querySnapshot.docs) {
      final dadosDaNuvem = docSnapshot.data();
      final cubagemDaNuvem = CubagemArvore.fromMap(dadosDaNuvem);

      final cubagemLocalExistente = await db.query('cubagens_arvores', where: 'id = ?', whereArgs: [cubagemDaNuvem.id]);
      if (cubagemLocalExistente.isNotEmpty) continue;

      await db.transaction((txn) async {
        try {
          final talhaoIdLocal = cubagemDaNuvem.talhaoId;
          if (talhaoIdLocal == null) return;
          final talhoes = await txn.query('talhoes', where: 'id = ?', whereArgs: [talhaoIdLocal]);
          if (talhoes.isEmpty) return;

          final cMap = cubagemDaNuvem.toMap();
          cMap['isSynced'] = 1;
          await txn.insert('cubagens_arvores', cMap, conflictAlgorithm: ConflictAlgorithm.replace);

          final secoesSnapshot = await docSnapshot.reference.collection('secoes').get();
          if (secoesSnapshot.docs.isNotEmpty) {
            final secoesDaNuvem = secoesSnapshot.docs.map((doc) => CubagemSecao.fromMap(doc.data())).toList();
            for (final secao in secoesDaNuvem) {
              await txn.insert('cubagens_secoes', secao.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
          novasCubagens++;
        } catch (e, s) {
          debugPrint("Erro CRÍTICO ao sincronizar cubagem ${cubagemDaNuvem.id}: $e\n$s");
        }
      });
    }
    if (novasCubagens > 0) debugPrint("$novasCubagens novas cubagens foram baixadas da nuvem.");
  }
  
  Future<void> atualizarStatusProjetoNaFirebase(String projetoId, String novoStatus) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Usuário não está logado.");

    final licenseDoc = await _licensingService.findLicenseDocumentForUser(user);
    if (licenseDoc == null) throw Exception("Não foi possível encontrar a licença para atualizar o projeto.");
    
    final licenseId = licenseDoc.id;
    final projetoRef = _firestore.collection('clientes').doc(licenseId).collection('projetos').doc(projetoId);
    await projetoRef.update({'status': novoStatus});
    debugPrint("Status do projeto $projetoId atualizado para '$novoStatus' no Firebase.");
  }
}
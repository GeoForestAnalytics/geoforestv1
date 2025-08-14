// lib/services/sync_service.dart (VERSÃO FINAL E COMPLETA COM TUDO INTEGRADO)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/cubagem_secao_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/sync_conflict_model.dart'; // <<< Importa o modelo de conflito
import 'package:geoforestv1/models/sync_progress_model.dart';
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
  
  final StreamController<SyncProgress> _progressStreamController = StreamController.broadcast();
  Stream<SyncProgress> get progressStream => _progressStreamController.stream;

  // Lista para guardar os conflitos encontrados durante a sincronização
  final List<SyncConflict> conflicts = [];

  Future<void> sincronizarDados() async {
    conflicts.clear(); // Limpa conflitos de sincronizações anteriores
    final user = _auth.currentUser;
    if (user == null) {
      _progressStreamController.add(SyncProgress(erro: "Usuário não está logado.", concluido: true));
      throw Exception("Usuário não está logado.");
    }

    try {
      final licenseDoc = await _licensingService.findLicenseDocumentForUser(user);
      if (licenseDoc == null) {
        _progressStreamController.add(SyncProgress(erro: "Licença de usuário não encontrada.", concluido: true));
        throw Exception("Não foi possível encontrar uma licença válida para sincronizar os dados.");
      }
      
      final licenseId = licenseDoc.id;
      final licenseData = licenseDoc.data()!;
      
      final usuariosPermitidos = licenseData['usuariosPermitidos'] as Map<String, dynamic>? ?? {};
      final dadosDoUsuario = usuariosPermitidos[user.uid] as Map<String, dynamic>?;
      final cargo = dadosDoUsuario?['cargo'] as String? ?? 'equipe';

      final totalParcelas = (await _parcelaRepository.getUnsyncedParcelas()).length;
      final totalCubagens = (await _cubagemRepository.getUnsyncedCubagens()).length;
      final totalGeral = totalParcelas + totalCubagens;
      
      _progressStreamController.add(SyncProgress(totalAProcessar: totalGeral, mensagem: "Preparando sincronização..."));

      if (cargo == 'gerente') {
        _progressStreamController.add(SyncProgress(totalAProcessar: totalGeral, mensagem: "Enviando estrutura de projetos..."));
        await _uploadHierarquiaCompleta(licenseId);
      }
      
      await _uploadColetasNaoSincronizadas(licenseId, totalGeral);

      _progressStreamController.add(SyncProgress(totalAProcessar: totalGeral, processados: totalGeral, mensagem: "Baixando dados da nuvem..."));
      await _downloadHierarquiaCompleta(licenseId);
      await _downloadProjetosDelegados(licenseId);
      await _downloadColetas(licenseId);

      String finalMessage = "Sincronização Concluída!";
      if (conflicts.isNotEmpty) {
        finalMessage += " ${conflicts.length} conflito(s) foram detectados e precisam de sua atenção.";
      }

      _progressStreamController.add(SyncProgress(
        totalAProcessar: totalGeral, 
        processados: totalGeral, 
        mensagem: finalMessage, 
        concluido: true
      ));

    } catch(e) {
      final erroMsg = "Ocorreu um erro geral na sincronização: $e";
      debugPrint(erroMsg);
      _progressStreamController.add(SyncProgress(erro: erroMsg, concluido: true));
      rethrow;
    }
  }

  Future<void> _uploadColetasNaoSincronizadas(String licenseIdDoUsuarioLogado, int totalGeral) async {
    int processados = 0;

    while (true) {
      if (totalGeral > 0) {
        _progressStreamController.add(SyncProgress(
          totalAProcessar: totalGeral,
          processados: processados,
          mensagem: "Verificando item ${processados + 1} de $totalGeral...",
        ));
      }
      
      // --- LÓGICA DE VERIFICAÇÃO PARA PARCELAS ---
      final parcelaLocal = await _parcelaRepository.getOneUnsyncedParcel();
      if (parcelaLocal != null) {
        try {
          final projetoPai = await _projetoRepository.getProjetoPelaParcela(parcelaLocal);
          final licenseIdDeDestino = projetoPai?.delegadoPorLicenseId ?? projetoPai?.licenseId ?? licenseIdDoUsuarioLogado;
          final docRef = _firestore.collection('clientes').doc(licenseIdDeDestino).collection('dados_coleta').doc(parcelaLocal.uuid);
          
          final docServer = await docRef.get();

          bool deveEnviar = true; // Assumimos que podemos enviar por padrão

          if (docServer.exists) {
            final serverData = docServer.data()!;
            // Firestore retorna um Timestamp, precisamos convertê-lo para DateTime para comparar
            final serverLastModified = (serverData['lastModified'] as firestore.Timestamp?)?.toDate();
            
            if (serverLastModified != null && parcelaLocal.lastModified != null) {
              // Compara as datas. Se a do servidor for mais nova, temos um conflito.
              if (serverLastModified.isAfter(parcelaLocal.lastModified!)) {
                deveEnviar = false; // Bloqueia o envio
                debugPrint("!!! CONFLITO DETECTADO para a parcela ${parcelaLocal.idParcela} !!!");
                conflicts.add(SyncConflict(
                  type: ConflictType.parcela,
                  localData: parcelaLocal,
                  serverData: Parcela.fromMap(serverData),
                  identifier: "Parcela ${parcelaLocal.idParcela} (Talhão: ${parcelaLocal.nomeTalhao})",
                ));
              }
            }
          }

          if (deveEnviar) {
            await _uploadParcela(docRef, parcelaLocal);
          }
          
          await _parcelaRepository.markParcelaAsSynced(parcelaLocal.dbId!);
          processados++;
          continue;

        } catch (e) {
          final erroMsg = "Falha ao verificar/enviar parcela ${parcelaLocal.idParcela}. Verifique sua conexão.";
          debugPrint("$erroMsg Erro: $e");
          _progressStreamController.add(SyncProgress(erro: erroMsg, concluido: true));
          break;
        }
      }

      // --- LÓGICA DE VERIFICAÇÃO PARA CUBAGENS (análoga à de parcelas) ---
      final cubagemLocal = await _cubagemRepository.getOneUnsyncedCubagem();
      if(cubagemLocal != null){
         try {
          final projetoPai = await _projetoRepository.getProjetoPelaCubagem(cubagemLocal);
          final licenseIdDeDestino = projetoPai?.delegadoPorLicenseId ?? projetoPai?.licenseId ?? licenseIdDoUsuarioLogado;
          final docRef = _firestore.collection('clientes').doc(licenseIdDeDestino).collection('dados_cubagem').doc(cubagemLocal.id.toString());
          
          final docServer = await docRef.get();
          bool deveEnviar = true;

          if (docServer.exists) {
            final serverData = docServer.data()!;
            final serverLastModified = (serverData['lastModified'] as firestore.Timestamp?)?.toDate();
            
            if (serverLastModified != null && cubagemLocal.lastModified != null) {
              if (serverLastModified.isAfter(cubagemLocal.lastModified!)) {
                deveEnviar = false;
                debugPrint("!!! CONFLITO DETECTADO para a cubagem ${cubagemLocal.identificador} !!!");
                conflicts.add(SyncConflict(
                  type: ConflictType.cubagem,
                  localData: cubagemLocal,
                  serverData: CubagemArvore.fromMap(serverData),
                  identifier: "Cubagem ${cubagemLocal.identificador}",
                ));
              }
            }
          }
          
          if(deveEnviar){
             await _uploadCubagem(docRef, cubagemLocal);
          }

          await _cubagemRepository.markCubagemAsSynced(cubagemLocal.id!);
          processados++;
          continue;
        } catch (e) {
          final erroMsg = "Falha ao verificar/enviar cubagem ${cubagemLocal.id}. Verifique sua conexão.";
          debugPrint("$erroMsg Erro: $e");
          _progressStreamController.add(SyncProgress(erro: erroMsg, concluido: true));
          break;
        }
      }
      
      break;
    }
  }

  Future<void> _uploadParcela(firestore.DocumentReference docRef, Parcela parcela) async {
      final firestoreBatch = _firestore.batch();
      final parcelaMap = parcela.toMap();
      final prefs = await SharedPreferences.getInstance();
      parcelaMap['nomeLider'] = parcela.nomeLider ?? prefs.getString('nome_lider');
      parcelaMap['lastModified'] = firestore.FieldValue.serverTimestamp();
      firestoreBatch.set(docRef, parcelaMap, firestore.SetOptions(merge: true));
      
      final arvores = await _parcelaRepository.getArvoresDaParcela(parcela.dbId!);
      for (final arvore in arvores) {
        final arvoreRef = docRef.collection('arvores').doc(arvore.id.toString());
        firestoreBatch.set(arvoreRef, arvore.toMap());
      }
      await firestoreBatch.commit();
  }

  Future<void> _uploadCubagem(firestore.DocumentReference docRef, CubagemArvore cubagem) async {
      final firestoreBatch = _firestore.batch();
      final cubagemMap = cubagem.toMap();
      final prefs = await SharedPreferences.getInstance();
      cubagemMap['nomeLider'] = cubagem.nomeLider ?? prefs.getString('nome_lider');
      cubagemMap['lastModified'] = firestore.FieldValue.serverTimestamp();
      firestoreBatch.set(docRef, cubagemMap, firestore.SetOptions(merge: true));
      
      final secoes = await _cubagemRepository.getSecoesPorArvoreId(cubagem.id!);
      for (final secao in secoes) {
        final secaoRef = docRef.collection('secoes').doc(secao.id.toString());
        firestoreBatch.set(secaoRef, secao.toMap());
      }
      await firestoreBatch.commit();
  }

  // --- FUNÇÕES DA VERSÃO ANTERIOR QUE ESTAVAM CORRETAS ---

  Future<void> _uploadHierarquiaCompleta(String licenseId) async {
    final db = await _dbHelper.database;
    final batch = _firestore.batch();
    
    final projetosProprios = await db.query('projetos', where: 'delegado_por_license_id IS NULL AND licenseId = ?', whereArgs: [licenseId]);
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

  Future<void> _downloadHierarquiaCompleta(String licenseId) async {
    final db = await _dbHelper.database;
    
    final projetosSnap = await _firestore.collection('clientes').doc(licenseId).collection('projetos').get();
    final idsNaWeb = projetosSnap.docs.map((doc) => doc.data()['id'] as int).toSet();

    final projetosLocais = await db.query('projetos', columns: ['id'], where: 'licenseId = ? AND delegado_por_license_id IS NULL', whereArgs: [licenseId]);
    final idsLocais = projetosLocais.map((map) => map['id'] as int).toSet();

    final idsParaDeletar = idsLocais.difference(idsNaWeb);

    if (idsParaDeletar.isNotEmpty) {
      await db.delete('projetos', where: 'id IN (${List.filled(idsParaDeletar.length, '?').join(',')})', whereArgs: idsParaDeletar.toList());
      debugPrint("${idsParaDeletar.length} projetos obsoletos foram removidos do banco de dados local.");
    }
    
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
    final idsAtividadesNaWeb = atividadesSnap.docs.map((doc) => doc.data()['id'] as int).toSet();
    
    final atividadesLocais = await db.query('atividades', columns: ['id'], where: 'projetoId IN (SELECT id FROM projetos WHERE delegado_por_license_id IS NULL AND licenseId = ?)', whereArgs: [licenseId]);
    final idsAtividadesLocais = atividadesLocais.map((map) => map['id'] as int).toSet();
    final idsAtividadesParaDeletar = idsAtividadesLocais.difference(idsAtividadesNaWeb);
    if (idsAtividadesParaDeletar.isNotEmpty) {
      await db.delete('atividades', where: 'id IN (${List.filled(idsAtividadesParaDeletar.length, '?').join(',')})', whereArgs: idsAtividadesParaDeletar.toList());
    }

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

    debugPrint("Hierarquia completa da própria licença (Projetos, Atividades, Fazendas, Talhões) foi baixada e sincronizada localmente.");
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
      final projetosPermitidosIds = (dataChave['projetosPermitidos'] as List<dynamic>).cast<int>();

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
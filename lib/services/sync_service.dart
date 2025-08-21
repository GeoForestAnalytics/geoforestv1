// lib/services/sync_service.dart (VERSÃO COM SINCRONIZAÇÃO DE DIÁRIO)

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

import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart'; // <<< NOVO IMPORT

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

  Future<void> sincronizarDados() async {
    conflicts.clear();
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
      
      await _dbHelper.database;
      
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

    } catch(e, s) {
      final erroMsg = "Ocorreu um erro geral na sincronização: $e";
      debugPrint("$erroMsg\n$s");
      _progressStreamController.add(SyncProgress(erro: erroMsg, concluido: true));
      rethrow;
    }
  }

  Future<void> _uploadHierarquiaCompleta(String licenseId) async {
    final db = await _dbHelper.database;
    final batch = _firestore.batch();
    
    final projetosProprios = await db.query('projetos', where: 'delegado_por_license_id IS NULL AND licenseId = ?', whereArgs: [licenseId]);
    if (projetosProprios.isEmpty) return;
    for (var p in projetosProprios) {
      final docRef = _firestore.collection('clientes').doc(licenseId).collection('projetos').doc(p['id'].toString());
      final map = Projeto.fromMap(p).toMap();
      map['lastModified'] = firestore.FieldValue.serverTimestamp();
      batch.set(docRef, map, firestore.SetOptions(merge: true));
    }

    final projetosIds = projetosProprios.map((p) => p['id'] as int).toList();
    if(projetosIds.isEmpty) return;
    
    final atividades = await db.query('atividades', where: 'projetoId IN (${projetosIds.join(',')})');
    for (var a in atividades) {
        final docRef = _firestore.collection('clientes').doc(licenseId).collection('atividades').doc(a['id'].toString());
        final map = Map<String, dynamic>.from(a);
        map['lastModified'] = firestore.FieldValue.serverTimestamp();
        batch.set(docRef, map, firestore.SetOptions(merge: true));
    }

    final atividadeIds = atividades.map((a) => a['id'] as int).toList();
    if (atividadeIds.isEmpty) return;
    
    final fazendas = await db.query('fazendas', where: 'atividadeId IN (${atividadeIds.join(',')})');
    for (var f in fazendas) {
        final docId = "${f['id']}_${f['atividadeId']}";
        final docRef = _firestore.collection('clientes').doc(licenseId).collection('fazendas').doc(docId);
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
        final docRef = _firestore.collection('clientes').doc(licenseId).collection('talhoes').doc(t['id'].toString());
        final map = Talhao.fromMap(t).toFirestoreMap();
        map['lastModified'] = firestore.FieldValue.serverTimestamp();
        batch.set(docRef, map, firestore.SetOptions(merge: true));
    }
    
    await batch.commit();
  }
  
  Future<void> _uploadColetasNaoSincronizadas(String licenseIdDoUsuarioLogado, int totalGeral) async {
    int processados = 0;
    while (true) {
      if (totalGeral > 0) {
        _progressStreamController.add(SyncProgress(
          totalAProcessar: totalGeral,
          processados: processados,
          mensagem: "Enviando item ${processados + 1} de $totalGeral...",
        ));
      }
      final parcelaLocal = await _parcelaRepository.getOneUnsyncedParcel();
      if (parcelaLocal != null) {
        try {
          final projetoPai = await _projetoRepository.getProjetoPelaParcela(parcelaLocal);
          final licenseIdDeDestino = projetoPai?.delegadoPorLicenseId ?? projetoPai?.licenseId ?? licenseIdDoUsuarioLogado;
          final docRef = _firestore.collection('clientes').doc(licenseIdDeDestino).collection('dados_coleta').doc(parcelaLocal.uuid);
          final docServer = await docRef.get();
          bool deveEnviar = true;
          if (docServer.exists) {
            final serverData = docServer.data()!;
            final serverLastModified = (serverData['lastModified'] as firestore.Timestamp?)?.toDate();
            if (serverLastModified != null && parcelaLocal.lastModified != null) {
              if (serverLastModified.isAfter(parcelaLocal.lastModified!)) {
                deveEnviar = false;
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
          final erroMsg = "Falha ao enviar parcela ${parcelaLocal.idParcela}.";
          _progressStreamController.add(SyncProgress(erro: erroMsg, concluido: true));
          break;
        }
      }
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
          final erroMsg = "Falha ao enviar cubagem ${cubagemLocal.id}.";
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
        final arvoreMap = arvore.toMap();
        arvoreMap['lastModified'] = firestore.FieldValue.serverTimestamp();
        final arvoreRef = docRef.collection('arvores').doc(arvore.id.toString());
        firestoreBatch.set(arvoreRef, arvoreMap);
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
        final secaoMap = secao.toMap();
        secaoMap['lastModified'] = firestore.FieldValue.serverTimestamp();
        final secaoRef = docRef.collection('secoes').doc(secao.id.toString());
        firestoreBatch.set(secaoRef, secaoMap);
      }
      await firestoreBatch.commit();
  }
  
  Future<void> _upsert(DatabaseExecutor txn, String table, Map<String, dynamic> data, String primaryKey, {String? secondaryKey}) async {
      List<String> whereArgs = [data[primaryKey].toString()];
      String whereClause = '$primaryKey = ?';
      if (secondaryKey != null) {
          whereClause += ' AND $secondaryKey = ?';
          whereArgs.add(data[secondaryKey].toString());
      }
      final existing = await txn.query(table, where: whereClause, whereArgs: whereArgs, limit: 1);
      if (existing.isNotEmpty) {
          await txn.update(table, data, where: whereClause, whereArgs: whereArgs);
      } else {
          await txn.insert(table, data);
      }
  }

  Future<void> _downloadHierarquiaCompleta(String licenseId) async {
    final db = await _dbHelper.database;
    final projetosSnap = await _firestore.collection('clientes').doc(licenseId).collection('projetos').get();

    for (var projDoc in projetosSnap.docs) {
        final projeto = Projeto.fromMap(projDoc.data());
        
        await db.transaction((txn) async {
            await _upsert(txn, 'projetos', projeto.toMap(), 'id');
        });
        
        await _downloadFilhosDeProjeto(licenseId, projeto.id!);
    }
  }

  Future<void> _downloadProjetosDelegados(String licenseIdDoUsuarioLogado) async {
    final db = await _dbHelper.database;
    final query = _firestore.collectionGroup('chavesDeDelegacao')
        .where('licenseIdConvidada', isEqualTo: licenseIdDoUsuarioLogado)
        .where('status', isEqualTo: 'ativa');
    final snapshot = await query.get();
    if (snapshot.docs.isEmpty) return;
    
    for (final docChave in snapshot.docs) {
      final licenseIdDoCliente = docChave.reference.parent.parent!.id;
      final dataChave = docChave.data();
      final projetosPermitidosIds = (dataChave['projetosPermitidos'] as List<dynamic>).cast<int>();
      if (projetosPermitidosIds.isEmpty) continue;

      for (final projetoId in projetosPermitidosIds) {
        final projDoc = await _firestore.collection('clientes').doc(licenseIdDoCliente)
            .collection('projetos').doc(projetoId.toString()).get();
        if (projDoc.exists) {
            final projeto = Projeto.fromMap(projDoc.data()!)
                .copyWith(delegadoPorLicenseId: licenseIdDoCliente);
            await db.transaction((txn) async {
                await _upsert(txn, 'projetos', projeto.toMap(), 'id');
            });
            await _downloadFilhosDeProjeto(licenseIdDoCliente, projetoId);
        }
      }
    }
  }

  Future<void> _downloadFilhosDeProjeto(String licenseId, int projetoId) async {
    final db = await _dbHelper.database;
    
    final atividadesSnap = await _firestore.collection('clientes').doc(licenseId)
        .collection('atividades').where('projetoId', isEqualTo: projetoId).get();
    if (atividadesSnap.docs.isEmpty) return;

    for (var ativDoc in atividadesSnap.docs) {
      final atividade = Atividade.fromMap(ativDoc.data());
      await db.transaction((txn) async {
         await _upsert(txn, 'atividades', atividade.toMap(), 'id');
      });

      final fazendasSnap = await _firestore.collection('clientes').doc(licenseId)
          .collection('fazendas').where('atividadeId', isEqualTo: atividade.id).get();
          
      for (var fazendaDoc in fazendasSnap.docs) {
        final fazenda = Fazenda.fromMap(fazendaDoc.data());
        await db.transaction((txn) async {
           await _upsert(txn, 'fazendas', fazenda.toMap(), 'id', secondaryKey: 'atividadeId');
        });

        final talhoesSnap = await _firestore.collection('clientes').doc(licenseId)
            .collection('talhoes')
            .where('fazendaId', isEqualTo: fazenda.id)
            .where('fazendaAtividadeId', isEqualTo: fazenda.atividadeId)
            .get();
            
        for (var talhaoDoc in talhoesSnap.docs) {
          final data = talhaoDoc.data();
          data['projetoId'] = atividade.projetoId; 
          final talhao = Talhao.fromMap(data);
          await db.transaction((txn) async {
             await _upsert(txn, 'talhoes', talhao.toMap(), 'id');
          });
        }
      }
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
    for (final docSnapshot in querySnapshot.docs) {
      final dadosDaNuvem = docSnapshot.data();
      final parcelaDaNuvem = Parcela.fromMap(dadosDaNuvem);
      await db.transaction((txn) async {
        try {
          final pMap = parcelaDaNuvem.toMap();
          pMap['isSynced'] = 1;
          await _upsert(txn, 'parcelas', pMap, 'uuid');
          final parcelaLocalResult = await txn.query('parcelas', where: 'uuid = ?', whereArgs: [parcelaDaNuvem.uuid], limit: 1);
          final idLocal = Parcela.fromMap(parcelaLocalResult.first).dbId!;
          await txn.delete('arvores', where: 'parcelaId = ?', whereArgs: [idLocal]);
          await _sincronizarArvores(txn, docSnapshot, idLocal);
        } catch (e, s) {
          debugPrint("Erro CRÍTICO ao sincronizar parcela ${parcelaDaNuvem.uuid}: $e\n$s");
        }
      });
    }
  }
  
  Future<void> _sincronizarArvores(DatabaseExecutor txn, firestore.DocumentSnapshot docSnapshot, int idParcelaLocal) async {
      final arvoresSnapshot = await docSnapshot.reference.collection('arvores').get();
      if (arvoresSnapshot.docs.isNotEmpty) {
        for (final doc in arvoresSnapshot.docs) {
          final arvore = Arvore.fromMap(doc.data());
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
    for (final docSnapshot in querySnapshot.docs) {
      final dadosDaNuvem = docSnapshot.data();
      final cubagemDaNuvem = CubagemArvore.fromMap(dadosDaNuvem);
      await db.transaction((txn) async {
        try {
          final cMap = cubagemDaNuvem.toMap();
          cMap['isSynced'] = 1;
          await _upsert(txn, 'cubagens_arvores', cMap, 'id');
          
          await txn.delete('cubagens_secoes', where: 'cubagemArvoreId = ?', whereArgs: [cubagemDaNuvem.id]);
          
          final secoesSnapshot = await docSnapshot.reference.collection('secoes').get();

          if (secoesSnapshot.docs.isNotEmpty) {
            for (final doc in secoesSnapshot.docs) {
              final secao = CubagemSecao.fromMap(doc.data());
              secao.cubagemArvoreId = cubagemDaNuvem.id; 
              await txn.insert('cubagens_secoes', secao.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }

        } catch (e, s) {
          debugPrint("Erro CRÍTICO ao sincronizar cubagem ${cubagemDaNuvem.id}: $e\n$s");
        }
      });
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

  // <<< MÉTODO NOVO ADICIONADO AQUI >>>
  /// Envia um único documento de Diário de Campo para o Firestore.
  Future<void> sincronizarDiarioDeCampo(DiarioDeCampo diario) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Usuário não está logado.");

    final licenseDoc = await _licensingService.findLicenseDocumentForUser(user);
    if (licenseDoc == null) throw Exception("Licença do usuário não encontrada.");
    
    final licenseId = licenseDoc.id;

    // A ID do documento será uma combinação da data e do líder para garantir que seja único por dia/equipe.
    final docId = '${diario.dataRelatorio}_${diario.nomeLider.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-')}';

    final docRef = _firestore
        .collection('clientes')
        .doc(licenseId)
        .collection('diarios_de_campo')
        .doc(docId);

    final diarioMap = diario.toMap();
    // Adiciona o timestamp do servidor para controle de versão na nuvem
    diarioMap['lastModifiedServer'] = firestore.FieldValue.serverTimestamp();

    await docRef.set(diarioMap, firestore.SetOptions(merge: true));
  }
}
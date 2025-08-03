// lib/services/sync_service.dart (VERSÃO FINAL, COMPLETA E CORRIGIDA)

import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/cubagem_secao_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/services/licensing_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';

class SyncService {
  final firestore.FirebaseFirestore _firestore = firestore.FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final LicensingService _licensingService = LicensingService();
  
  final _parcelaRepository = ParcelaRepository();
  final _cubagemRepository = CubagemRepository();
  final _talhaoRepository = TalhaoRepository();

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
      debugPrint("Sincronização em modo GERENTE: Upload primeiro, depois Download.");
      await _uploadHierarquiaCompleta(licenseId);
      await _uploadColetasNaoSincronizadas(licenseId);
    } else { 
      debugPrint("Sincronização em modo EQUIPE: Upload primeiro, depois Download.");
      await _uploadColetasNaoSincronizadas(licenseId);
    }

    await _downloadHierarquiaCompleta(licenseId);
    await _downloadProjetosDelegados(licenseId);
    await _downloadColetas(licenseId);
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

  Future<void> _uploadColetasNaoSincronizadas(String licenseIdDoUsuarioLogado) async {
    final db = await _dbHelper.database;
    final firestoreBatch = _firestore.batch();
    final prefs = await SharedPreferences.getInstance();
    final nomeLider = prefs.getString('nome_lider');

    final List<Parcela> parcelasNaoSincronizadas = await _parcelaRepository.getUnsyncedParcelas();
    if (parcelasNaoSincronizadas.isNotEmpty) {
      for (final parcela in parcelasNaoSincronizadas) {
        if (parcela.talhaoId == null) continue;
        final talhaoLocal = await _talhaoRepository.getTalhaoById(parcela.talhaoId!);
        if (talhaoLocal == null) continue;
        final fazendaLocalResult = await db.query('fazendas', where: 'id = ? AND atividadeId = ?', whereArgs: [talhaoLocal.fazendaId, talhaoLocal.fazendaAtividadeId]);
        if (fazendaLocalResult.isEmpty) continue;
        final atividadeLocalResult = await db.query('atividades', where: 'id = ?', whereArgs: [talhaoLocal.fazendaAtividadeId]);
        if (atividadeLocalResult.isEmpty) continue;
        final projetoLocalResult = await db.query('projetos', where: 'id = ?', whereArgs: [atividadeLocalResult.first['projetoId']]);
        if (projetoLocalResult.isEmpty) continue;
        final projetoPai = Projeto.fromMap(projetoLocalResult.first);
        final licenseIdDeDestino = projetoPai.delegadoPorLicenseId ?? projetoPai.licenseId;
        if (licenseIdDeDestino == null) continue;

        firestoreBatch.set(_firestore.collection('clientes').doc(licenseIdDeDestino).collection('projetos').doc(projetoPai.id.toString()), projetoPai.toMap(), firestore.SetOptions(merge: true));
        firestoreBatch.set(_firestore.collection('clientes').doc(licenseIdDeDestino).collection('atividades').doc(atividadeLocalResult.first['id'].toString()), atividadeLocalResult.first, firestore.SetOptions(merge: true));
        final fazendaDocId = "${fazendaLocalResult.first['id']}_${fazendaLocalResult.first['atividadeId']}";
        firestoreBatch.set(_firestore.collection('clientes').doc(licenseIdDeDestino).collection('fazendas').doc(fazendaDocId), fazendaLocalResult.first, firestore.SetOptions(merge: true));
        firestoreBatch.set(_firestore.collection('clientes').doc(licenseIdDeDestino).collection('talhoes').doc(talhaoLocal.id.toString()), talhaoLocal.toMap(), firestore.SetOptions(merge: true));
        
        final parcelaDocRef = _firestore.collection('clientes').doc(licenseIdDeDestino).collection('dados_coleta').doc(parcela.uuid);
        final parcelaMap = parcela.toMap();
        parcelaMap['nomeLider'] = nomeLider;
        firestoreBatch.set(parcelaDocRef, parcelaMap, firestore.SetOptions(merge: true));
        final arvores = await _parcelaRepository.getArvoresDaParcela(parcela.dbId!);
        for (final arvore in arvores) {
          final arvoreRef = parcelaDocRef.collection('arvores').doc(arvore.id.toString());
          firestoreBatch.set(arvoreRef, arvore.toMap());
        }
      }
    }

    final List<CubagemArvore> cubagensNaoSincronizadas = await _cubagemRepository.getUnsyncedCubagens();
    if (cubagensNaoSincronizadas.isNotEmpty) {
      for (final cubagem in cubagensNaoSincronizadas) {
        if (cubagem.talhaoId == null) continue;
        final talhaoLocal = await _talhaoRepository.getTalhaoById(cubagem.talhaoId!);
        if (talhaoLocal == null) continue;
        final fazendaLocalResult = await db.query('fazendas', where: 'id = ? AND atividadeId = ?', whereArgs: [talhaoLocal.fazendaId, talhaoLocal.fazendaAtividadeId]);
        if (fazendaLocalResult.isEmpty) continue;
        final atividadeLocalResult = await db.query('atividades', where: 'id = ?', whereArgs: [talhaoLocal.fazendaAtividadeId]);
        if (atividadeLocalResult.isEmpty) continue;
        final projetoLocalResult = await db.query('projetos', where: 'id = ?', whereArgs: [atividadeLocalResult.first['projetoId']]);
        if (projetoLocalResult.isEmpty) continue;
        final projetoPai = Projeto.fromMap(projetoLocalResult.first);
        final licenseIdDeDestino = projetoPai.delegadoPorLicenseId ?? projetoPai.licenseId;
        if (licenseIdDeDestino == null) continue;

        firestoreBatch.set(_firestore.collection('clientes').doc(licenseIdDeDestino).collection('projetos').doc(projetoPai.id.toString()), projetoPai.toMap(), firestore.SetOptions(merge: true));
        firestoreBatch.set(_firestore.collection('clientes').doc(licenseIdDeDestino).collection('atividades').doc(atividadeLocalResult.first['id'].toString()), atividadeLocalResult.first, firestore.SetOptions(merge: true));
        final fazendaDocId = "${fazendaLocalResult.first['id']}_${fazendaLocalResult.first['atividadeId']}";
        firestoreBatch.set(_firestore.collection('clientes').doc(licenseIdDeDestino).collection('fazendas').doc(fazendaDocId), fazendaLocalResult.first, firestore.SetOptions(merge: true));
        firestoreBatch.set(_firestore.collection('clientes').doc(licenseIdDeDestino).collection('talhoes').doc(talhaoLocal.id.toString()), talhaoLocal.toMap(), firestore.SetOptions(merge: true));

        final cubagemDocRef = _firestore.collection('clientes').doc(licenseIdDeDestino).collection('dados_cubagem').doc(cubagem.id.toString());
        final cubagemMap = cubagem.toMap();
        cubagemMap['nomeLider'] = cubagem.nomeLider ?? nomeLider;
        firestoreBatch.set(cubagemDocRef, cubagemMap, firestore.SetOptions(merge: true));
        final secoes = await _cubagemRepository.getSecoesPorArvoreId(cubagem.id!);
        for (final secao in secoes) {
          final secaoRef = cubagemDocRef.collection('secoes').doc(secao.id.toString());
          firestoreBatch.set(secaoRef, secao.toMap());
        }
      }
    }
    
    if (parcelasNaoSincronizadas.isNotEmpty || cubagensNaoSincronizadas.isNotEmpty) {
      await firestoreBatch.commit();
      
      for (final parcela in parcelasNaoSincronizadas) {
        await _parcelaRepository.markParcelaAsSynced(parcela.dbId!);
      }
      for (final cubagem in cubagensNaoSincronizadas) {
        await _cubagemRepository.markCubagemAsSynced(cubagem.id!);
      }
      debugPrint("${parcelasNaoSincronizadas.length} parcelas e ${cubagensNaoSincronizadas.length} cubagens foram sincronizadas.");
    }
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
    
    final atividadesLocais = await db.query('atividades', columns: ['id'], where: 'projetoId IN (SELECT id FROM projetos WHERE delegado_por_license_id IS NULL)');
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
// lib/data/repositories/parcela_repository.dart (VERSÃO COMPLETA E REFATORADA)

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class ParcelaRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<Parcela> saveFullColeta(Parcela p, List<Arvore> arvores) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();

    return await db.transaction<Parcela>((txn) async {
      int pId;
      
      Parcela parcelaModificavel = p.copyWith(isSynced: false);
      
      final pMap = parcelaModificavel.toMap();
      final d = parcelaModificavel.dataColeta ?? DateTime.now();
      pMap[DbParcelas.dataColeta] = d.toIso8601String();
      pMap[DbParcelas.lastModified] = now;

      if (pMap[DbParcelas.projetoId] == null && pMap[DbParcelas.talhaoId] != null) {
        final List<Map<String, dynamic>> talhaoInfo = await txn.rawQuery('''
          SELECT A.${DbAtividades.projetoId} FROM ${DbTalhoes.tableName} T
          INNER JOIN ${DbFazendas.tableName} F ON F.${DbFazendas.id} = T.${DbTalhoes.fazendaId} AND F.${DbFazendas.atividadeId} = T.${DbTalhoes.fazendaAtividadeId}
          INNER JOIN ${DbAtividades.tableName} A ON F.${DbFazendas.atividadeId} = A.${DbAtividades.id}
          WHERE T.${DbTalhoes.id} = ? LIMIT 1
        ''', [pMap[DbParcelas.talhaoId]]);

        if (talhaoInfo.isNotEmpty) {
          pMap[DbParcelas.projetoId] = talhaoInfo.first[DbAtividades.projetoId];
          parcelaModificavel = parcelaModificavel.copyWith(projetoId: talhaoInfo.first[DbAtividades.projetoId] as int?);
        }
      }

      final prefs = await SharedPreferences.getInstance();
      String? nomeDoResponsavel = prefs.getString('nome_lider');
      if (nomeDoResponsavel == null || nomeDoResponsavel.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          nomeDoResponsavel = user.displayName ?? user.email;
        }
      }
      if (nomeDoResponsavel != null) {
        pMap[DbParcelas.nomeLider] = nomeDoResponsavel;
        parcelaModificavel = parcelaModificavel.copyWith(nomeLider: nomeDoResponsavel);
      }

      if (parcelaModificavel.dbId == null) {
        pMap.remove(DbParcelas.id);
        pId = await txn.insert(DbParcelas.tableName, pMap);
        parcelaModificavel = parcelaModificavel.copyWith(dbId: pId, dataColeta: d);
      } else {
        pId = parcelaModificavel.dbId!;
        await txn.update(DbParcelas.tableName, pMap, where: '${DbParcelas.id} = ?', whereArgs: [pId]);
      }
      
      await txn.delete(DbArvores.tableName, where: '${DbArvores.parcelaId} = ?', whereArgs: [pId]);
      
      final List<Arvore> arvoresSalvasComId = [];
      for (final a in arvores) {
        final aMap = a.toMap();
        aMap.remove(DbArvores.id); 
        aMap[DbArvores.parcelaId] = pId;
        aMap[DbArvores.lastModified] = now;
        final newId = await txn.insert(DbArvores.tableName, aMap); 
        arvoresSalvasComId.add(a.copyWith(id: newId));
      }
      
      parcelaModificavel.arvores = arvoresSalvasComId;
      return parcelaModificavel;
    });
  }

  Future<void> saveBatchParcelas(List<Parcela> parcelas) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();
    for (final p in parcelas) {
      final map = p.toMap();
      map[DbParcelas.lastModified] = now;
      batch.insert(DbParcelas.tableName, map, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<int> updateParcela(Parcela p) async {
    final db = await _dbHelper.database;
    final map = p.toMap();
    map[DbParcelas.lastModified] = DateTime.now().toIso8601String();
    return await db.update(DbParcelas.tableName, map, where: '${DbParcelas.id} = ?', whereArgs: [p.dbId]);
  }

  Future<void> updateParcelaStatus(int parcelaId, StatusParcela novoStatus) async {
    final db = await _dbHelper.database;
    await db.update(
      DbParcelas.tableName,
      {
        DbParcelas.status: novoStatus.name,
        DbParcelas.lastModified: DateTime.now().toIso8601String(),
      },
      where: '${DbParcelas.id} = ?',
      whereArgs: [parcelaId],
    );
  }

  Future<List<Parcela>> getTodasAsParcelas() async {
    final db = await _dbHelper.database;
    final maps = await db.query(DbParcelas.tableName, orderBy: '${DbParcelas.dataColeta} DESC');
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<Parcela?> getParcelaById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(DbParcelas.tableName, where: '${DbParcelas.id} = ?', whereArgs: [id]);
    if (maps.isNotEmpty) return Parcela.fromMap(maps.first);
    return null;
  }

  Future<Parcela?> getParcelaPorIdParcela(int talhaoId, String idParcela) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      DbParcelas.tableName,
      where: '${DbParcelas.talhaoId} = ? AND ${DbParcelas.idParcela} = ?',
      whereArgs: [talhaoId, idParcela.trim()],
    );
    if (maps.isNotEmpty) {
      return Parcela.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Parcela>> getParcelasDoTalhao(int talhaoId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbParcelas.tableName,
      where: '${DbParcelas.talhaoId} = ?',
      whereArgs: [talhaoId],
      orderBy: '${DbParcelas.dataColeta} DESC',
    );
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<List<Arvore>> getArvoresDaParcela(int parcelaId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbArvores.tableName,
      where: '${DbArvores.parcelaId} = ?',
      whereArgs: [parcelaId],
      orderBy: '${DbArvores.linha}, ${DbArvores.posicaoNaLinha}, ${DbArvores.id}',
    );
    return List.generate(maps.length, (i) => Arvore.fromMap(maps[i]));
  }

  Future<List<Parcela>> getUnsyncedParcelas() async {
    final db = await _dbHelper.database;
    final maps = await db.query(DbParcelas.tableName, where: '${DbParcelas.isSynced} = ?', whereArgs: [0]);
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<void> markParcelaAsSynced(int id) async {
    final db = await _dbHelper.database;
    await db.update(DbParcelas.tableName, {DbParcelas.isSynced: 1}, where: '${DbParcelas.id} = ?', whereArgs: [id]);
  }

  Future<List<Parcela>> getUnexportedConcludedParcelasByLider(String nomeLider) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbParcelas.tableName,
      where: '${DbParcelas.status} = ? AND ${DbParcelas.exportada} = ? AND ${DbParcelas.nomeLider} = ?',
      whereArgs: [StatusParcela.concluida.name, 0, nomeLider],
    );
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<List<Parcela>> getConcludedParcelasByLiderParaBackup(String nomeLider) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbParcelas.tableName,
      where: '${DbParcelas.status} = ? AND ${DbParcelas.nomeLider} = ?',
      whereArgs: [StatusParcela.concluida.name, nomeLider],
    );
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<List<Parcela>> getUnexportedConcludedParcelasFiltrado({Set<int>? projetoIds, Set<String>? lideresNomes}) async {
    final db = await _dbHelper.database;
    String whereClause = '${DbParcelas.status} = ? AND ${DbParcelas.exportada} = ? AND ${DbParcelas.projetoId} IS NOT NULL';
    List<dynamic> whereArgs = [StatusParcela.concluida.name, 0];

    if (projetoIds != null && projetoIds.isNotEmpty) {
      whereClause += ' AND ${DbParcelas.projetoId} IN (${List.filled(projetoIds.length, '?').join(',')})';
      whereArgs.addAll(projetoIds);
    }
    if (lideresNomes != null && lideresNomes.isNotEmpty) {
      whereClause += ' AND ${DbParcelas.nomeLider} IN (${List.filled(lideresNomes.length, '?').join(',')})';
      whereArgs.addAll(lideresNomes);
    }

    final maps = await db.query(DbParcelas.tableName, where: whereClause, whereArgs: whereArgs);
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<List<Parcela>> getTodasConcluidasParcelasFiltrado({Set<int>? projetoIds, Set<String>? lideresNomes}) async {
    final db = await _dbHelper.database;
    String whereClause = '${DbParcelas.status} = ? AND ${DbParcelas.projetoId} IS NOT NULL';
    List<dynamic> whereArgs = [StatusParcela.concluida.name];

    if (projetoIds != null && projetoIds.isNotEmpty) {
      whereClause += ' AND ${DbParcelas.projetoId} IN (${List.filled(projetoIds.length, '?').join(',')})';
      whereArgs.addAll(projetoIds);
    }
    if (lideresNomes != null && lideresNomes.isNotEmpty) {
      whereClause += ' AND ${DbParcelas.nomeLider} IN (${List.filled(lideresNomes.length, '?').join(',')})';
      whereArgs.addAll(lideresNomes);
    }

    final maps = await db.query(DbParcelas.tableName, where: whereClause, whereArgs: whereArgs);
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<void> marcarParcelasComoExportadas(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.update(
      DbParcelas.tableName,
      {DbParcelas.exportada: 1},
      where: '${DbParcelas.id} IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  Future<Set<String>> getDistinctLideres() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbParcelas.tableName,
      distinct: true,
      columns: [DbParcelas.nomeLider],
      where: '${DbParcelas.nomeLider} IS NOT NULL AND ${DbParcelas.nomeLider} != ?',
      whereArgs: [''],
    );
    final lideres = maps.map((map) => map[DbParcelas.nomeLider] as String).toSet();
    final gerenteMaps = await db.query(
      DbParcelas.tableName,
      columns: [DbParcelas.id],
      where: '${DbParcelas.nomeLider} IS NULL OR ${DbParcelas.nomeLider} = ?',
      whereArgs: [''],
      limit: 1,
    );
    if (gerenteMaps.isNotEmpty) {
      lideres.add('Gerente');
    }
    return lideres;
  }

  Future<void> deletarMultiplasParcelas(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.delete(
      DbParcelas.tableName,
      where: '${DbParcelas.id} IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  Future<int> limparParcelasExportadas() async {
    final db = await _dbHelper.database;
    final count = await db.delete(DbParcelas.tableName, where: '${DbParcelas.exportada} = ?', whereArgs: [1]);
    debugPrint('$count parcelas exportadas foram apagadas.');
    return count;
  }

  Future<void> limparTodasAsParcelas() async {
    final db = await _dbHelper.database;
    await db.delete(DbParcelas.tableName);
    debugPrint('Tabela de parcelas e árvores limpa.');
  }

  Future<Parcela?> getOneUnsyncedParcel() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbParcelas.tableName,
      where: '${DbParcelas.isSynced} = ?',
      whereArgs: [0],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Parcela.fromMap(maps.first);
    }
    return null;
  }
  
  Future<List<Parcela>> getParcelasDoDiaPorEquipeEFiltros({
    required String nomeLider,
    required DateTime dataSelecionada,
    required int talhaoId,
    String? up,
  }) async {
    final db = await _dbHelper.database;
    
    final dataFormatadaParaQuery = DateFormat('yyyy-MM-dd').format(dataSelecionada);

    String whereClause = '${DbParcelas.nomeLider} = ? AND DATE(${DbParcelas.dataColeta}) = ?';
    List<dynamic> whereArgs = [nomeLider, dataFormatadaParaQuery];

    if (talhaoId != 0) {
      whereClause += ' AND ${DbParcelas.talhaoId} = ?';
      whereArgs.add(talhaoId);
    }
    
    if (up != null && up.isNotEmpty) {
      whereClause += ' AND ${DbParcelas.up} = ?';
      whereArgs.add(up);
    }

    final List<Map<String, dynamic>> maps = await db.query(
      DbParcelas.tableName,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: '${DbParcelas.dataColeta} DESC',
    );

    if (maps.isNotEmpty) {
      return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
    }
    return [];
  }
}
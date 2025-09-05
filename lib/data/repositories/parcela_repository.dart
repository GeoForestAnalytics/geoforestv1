// lib/data/repositories/parcela_repository.dart (VERSÃO ATUALIZADA E CORRIGIDA)

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class ParcelaRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // <<< INÍCIO DA CORREÇÃO: SUBSTITUA A FUNÇÃO INTEIRA POR ESTA >>>
  Future<Parcela> saveFullColeta(Parcela p, List<Arvore> arvores) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();

    // A função de transação agora retorna a Parcela salva, garantindo consistência.
    return await db.transaction<Parcela>((txn) async {
      int pId;
      
      // Cria uma cópia da parcela para evitar modificar o objeto original.
      Parcela parcelaModificavel = p.copyWith(isSynced: false);
      
      final pMap = parcelaModificavel.toMap();
      final d = parcelaModificavel.dataColeta ?? DateTime.now();
      pMap['dataColeta'] = d.toIso8601String();
      pMap['lastModified'] = now;

      // Lógica para garantir que o projetoId está presente.
      if (pMap['projetoId'] == null && pMap['talhaoId'] != null) {
        final List<Map<String, dynamic>> talhaoInfo = await txn.rawQuery('''
          SELECT A.projetoId FROM talhoes T
          INNER JOIN fazendas F ON F.id = T.fazendaId AND F.atividadeId = T.fazendaAtividadeId
          INNER JOIN atividades A ON F.atividadeId = A.id
          WHERE T.id = ? LIMIT 1
        ''', [pMap['talhaoId']]);

        if (talhaoInfo.isNotEmpty) {
          pMap['projetoId'] = talhaoInfo.first['projetoId'];
          parcelaModificavel = parcelaModificavel.copyWith(projetoId: talhaoInfo.first['projetoId'] as int?);
        }
      }

      // Lógica para adicionar o nome do líder.
      final prefs = await SharedPreferences.getInstance();
      String? nomeDoResponsavel = prefs.getString('nome_lider');
      if (nomeDoResponsavel == null || nomeDoResponsavel.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          nomeDoResponsavel = user.displayName ?? user.email;
        }
      }
      if (nomeDoResponsavel != null) {
        pMap['nomeLider'] = nomeDoResponsavel;
        // Atualiza o nome do líder no objeto também.
        parcelaModificavel = parcelaModificavel.copyWith(nomeLider: nomeDoResponsavel);
      }

      // Salva ou atualiza a parcela.
      if (parcelaModificavel.dbId == null) {
        pMap.remove('id');
        pId = await txn.insert('parcelas', pMap);
        // Atualiza o objeto com o ID do banco e a data de coleta correta.
        parcelaModificavel = parcelaModificavel.copyWith(dbId: pId, dataColeta: d);
      } else {
        pId = parcelaModificavel.dbId!;
        await txn.update('parcelas', pMap, where: 'id = ?', whereArgs: [pId]);
      }
      
      // Salva as árvores associadas.
      await txn.delete('arvores', where: 'parcelaId = ?', whereArgs: [pId]);
      for (final a in arvores) {
        final aMap = a.toMap();
        aMap['parcelaId'] = pId;
        aMap['lastModified'] = now;
        await txn.insert('arvores', aMap);
      }

      // Anexa a lista de árvores salvas ao objeto final.
      parcelaModificavel.arvores = arvores;
      
      // Retorna o objeto Parcela completo e consistente.
      return parcelaModificavel; 
    });
  }
  // <<< FIM DA CORREÇÃO >>>


  Future<void> saveBatchParcelas(List<Parcela> parcelas) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();
    for (final p in parcelas) {
      final map = p.toMap();
      map['lastModified'] = now;
      batch.insert('parcelas', map,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<int> updateParcela(Parcela p) async {
    final db = await _dbHelper.database;
    final map = p.toMap();
    map['lastModified'] = DateTime.now().toIso8601String();
    return await db
        .update('parcelas', map, where: 'id = ?', whereArgs: [p.dbId]);
  }

  Future<void> updateParcelaStatus(int parcelaId, StatusParcela novoStatus) async {
    final db = await _dbHelper.database;
    await db.update('parcelas', {
      'status': novoStatus.name,
      'lastModified': DateTime.now().toIso8601String(),
    },
        where: 'id = ?', whereArgs: [parcelaId]);
  }

  // --- MÉTODOS DE CONSULTA (GET) ---

  Future<List<Parcela>> getTodasAsParcelas() async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas', orderBy: 'dataColeta DESC');
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<Parcela?> getParcelaById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) return Parcela.fromMap(maps.first);
    return null;
  }

  Future<Parcela?> getParcelaPorIdParcela(int talhaoId, String idParcela) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'parcelas',
      where: 'talhaoId = ? AND idParcela = ?',
      whereArgs: [talhaoId, idParcela.trim()],
    );

    if (maps.isNotEmpty) {
      return Parcela.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Parcela>> getParcelasDoTalhao(int talhaoId) async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas',
        where: 'talhaoId = ?',
        whereArgs: [talhaoId],
        orderBy: 'dataColeta DESC');
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<List<Arvore>> getArvoresDaParcela(int parcelaId) async {
    final db = await _dbHelper.database;
    final maps = await db.query('arvores',
        where: 'parcelaId = ?',
        whereArgs: [parcelaId],
        orderBy: 'linha, posicaoNaLinha, id');
    return List.generate(maps.length, (i) => Arvore.fromMap(maps[i]));
  }

  // --- MÉTODOS PARA SINCRONIZAÇÃO ---

  Future<List<Parcela>> getUnsyncedParcelas() async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas', where: 'isSynced = ?', whereArgs: [0]);
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<void> markParcelaAsSynced(int id) async {
    final db = await _dbHelper.database;
    await db.update('parcelas', {'isSynced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // --- MÉTODOS PARA EXPORTAÇÃO ---

  Future<List<Parcela>> getUnexportedConcludedParcelasByLider(
      String nomeLider) async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas',
        where: 'status = ? AND exportada = ? AND nomeLider = ?',
        whereArgs: [StatusParcela.concluida.name, 0, nomeLider]);
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<List<Parcela>> getConcludedParcelasByLiderParaBackup(
      String nomeLider) async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas',
        where: 'status = ? AND nomeLider = ?',
        whereArgs: [StatusParcela.concluida.name, nomeLider]);
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<List<Parcela>> getUnexportedConcludedParcelasFiltrado(
      {Set<int>? projetoIds, Set<String>? lideresNomes}) async {
    final db = await _dbHelper.database;
    String whereClause = 'status = ? AND exportada = ? AND projetoId IS NOT NULL';
    List<dynamic> whereArgs = [StatusParcela.concluida.name, 0];

    if (projetoIds != null && projetoIds.isNotEmpty) {
      whereClause +=
          ' AND projetoId IN (${List.filled(projetoIds.length, '?').join(',')})';
      whereArgs.addAll(projetoIds);
    }
    if (lideresNomes != null && lideresNomes.isNotEmpty) {
      whereClause +=
          ' AND nomeLider IN (${List.filled(lideresNomes.length, '?').join(',')})';
      whereArgs.addAll(lideresNomes);
    }

    final maps =
        await db.query('parcelas', where: whereClause, whereArgs: whereArgs);
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<List<Parcela>> getTodasConcluidasParcelasFiltrado(
      {Set<int>? projetoIds, Set<String>? lideresNomes}) async {
    final db = await _dbHelper.database;
    String whereClause = 'status = ? AND projetoId IS NOT NULL';
    List<dynamic> whereArgs = [StatusParcela.concluida.name];

    if (projetoIds != null && projetoIds.isNotEmpty) {
      whereClause +=
          ' AND projetoId IN (${List.filled(projetoIds.length, '?').join(',')})';
      whereArgs.addAll(projetoIds);
    }
    if (lideresNomes != null && lideresNomes.isNotEmpty) {
      whereClause +=
          ' AND nomeLider IN (${List.filled(lideresNomes.length, '?').join(',')})';
      whereArgs.addAll(lideresNomes);
    }

    final maps =
        await db.query('parcelas', where: whereClause, whereArgs: whereArgs);
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<void> marcarParcelasComoExportadas(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.update('parcelas', {'exportada': 1},
        where: 'id IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids);
  }

  Future<Set<String>> getDistinctLideres() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
        'parcelas',
        distinct: true,
        columns: ['nomeLider'],
        where: 'nomeLider IS NOT NULL AND nomeLider != ?',
        whereArgs: ['']
    );
    final lideres = maps.map((map) => map['nomeLider'] as String).toSet();
    final gerenteMaps = await db.query(
      'parcelas',
      columns: ['id'],
      where: 'nomeLider IS NULL OR nomeLider = ?',
      whereArgs: [''],
      limit: 1,
    );
    if (gerenteMaps.isNotEmpty) {
      lideres.add('Gerente');
    }
    return lideres;
  }

  // --- MÉTODOS DE LIMPEZA ---

  Future<void> deletarMultiplasParcelas(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.delete('parcelas',
        where: 'id IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids);
  }

  Future<int> limparParcelasExportadas() async {
    final db = await _dbHelper.database;
    final count =
        await db.delete('parcelas', where: 'exportada = ?', whereArgs: [1]);
    debugPrint('$count parcelas exportadas foram apagadas.');
    return count;
  }

  Future<void> limparTodasAsParcelas() async {
    final db = await _dbHelper.database;
    await db.delete('parcelas');
    debugPrint('Tabela de parcelas e árvores limpa.');
  }

  Future<Parcela?> getOneUnsyncedParcel() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'parcelas',
      where: 'isSynced = ?',
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

    String whereClause = 'nomeLider = ? AND DATE(dataColeta) = ?';
    List<dynamic> whereArgs = [nomeLider, dataFormatadaParaQuery];

    if (talhaoId != 0) {
      whereClause += ' AND talhaoId = ?';
      whereArgs.add(talhaoId);
    }
    
    if (up != null && up.isNotEmpty) {
      whereClause += ' AND up = ?';
      whereArgs.add(up);
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'parcelas',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'dataColeta DESC',
    );

    if (maps.isNotEmpty) {
      return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
    }
    return [];
  }
}
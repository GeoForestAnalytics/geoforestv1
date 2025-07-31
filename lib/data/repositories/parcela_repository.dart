// lib/data/repositories/parcela_repository.dart (VERSÃO COM LÓGICA DE DATA)
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:sqflite/sqflite.dart';

class ParcelaRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // ... (todos os outros métodos como saveParcela, getParcelasDoTalhao, etc. permanecem aqui)
  Future<Parcela> saveParcela(Parcela parcela) async {
    final db = await _dbHelper.database;
    final dbId = await db.insert('parcelas', parcela.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    return parcela.copyWith(dbId: dbId);
  }

  Future<Parcela?> getParcelaPorIdParcela(int talhaoId, String idParcela) async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas', where: 'talhaoId = ? AND idParcela = ?', whereArgs: [talhaoId, idParcela], limit: 1);
    if (maps.isNotEmpty) return Parcela.fromMap(maps.first);
    return null;
  }

  Future<List<Parcela>> getParcelasDoTalhao(int talhaoId) async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas', where: 'talhaoId = ?', whereArgs: [talhaoId], orderBy: 'dataColeta DESC');
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<List<Parcela>> getUnsyncedParcelas() async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas', where: 'isSynced = ?', whereArgs: [0]);
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<void> markParcelaAsSynced(int id) async {
    final db = await _dbHelper.database;
    await db.update('parcelas', {'isSynced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> limparTodasAsParcelas() async {
    final db = await _dbHelper.database;
    await db.delete('parcelas');
    debugPrint('Tabela de parcelas e árvores limpa.');
  }

  Future<void> saveBatchParcelas(List<Parcela> parcelas) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final p in parcelas) {
      batch.insert('parcelas', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<Parcela> saveFullColeta(Parcela p, List<Arvore> arvores) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      int pId;
      p.isSynced = false;
      final pMap = p.toMap();
      final d = p.dataColeta ?? DateTime.now();
      pMap['dataColeta'] = d.toIso8601String();
      if (p.dbId == null) {
        pMap.remove('id');
        pId = await txn.insert('parcelas', pMap);
        p.dbId = pId;
        p.dataColeta = d;
      } else {
        pId = p.dbId!;
        await txn.update('parcelas', pMap, where: 'id = ?', whereArgs: [pId]);
      }
      await txn.delete('arvores', where: 'parcelaId = ?', whereArgs: [pId]);
      for (final a in arvores) {
        final aMap = a.toMap();
        aMap['parcelaId'] = pId;
        await txn.insert('arvores', aMap);
      }
    });
    return p;
  }

  Future<Parcela?> getParcelaById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) return Parcela.fromMap(maps.first);
    return null;
  }

  Future<List<Arvore>> getArvoresDaParcela(int parcelaId) async {
    final db = await _dbHelper.database;
    final maps = await db.query('arvores', where: 'parcelaId = ?', whereArgs: [parcelaId], orderBy: 'linha, posicaoNaLinha, id');
    return List.generate(maps.length, (i) => Arvore.fromMap(maps[i]));
  }

  Future<int> deleteParcela(int id) async {
    final db = await _dbHelper.database;
    return await db.delete('parcelas', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletarMultiplasParcelas(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.delete('parcelas', where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
  }

  Future<int> updateParcela(Parcela p) async {
    final db = await _dbHelper.database;
    return await db.update('parcelas', p.toMap(), where: 'id = ?', whereArgs: [p.dbId]);
  }

  Future<int> limparParcelasExportadas() async {
    final db = await _dbHelper.database;
    final count = await db.delete('parcelas', where: 'exportada = ?', whereArgs: [1]);
    debugPrint('$count parcelas exportadas foram apagadas.');
    return count;
  }

  Future<void> updateParcelaStatus(int parcelaId, StatusParcela novoStatus) async {
    final db = await _dbHelper.database;
    await db.update('parcelas', {'status': novoStatus.name}, where: 'id = ?', whereArgs: [parcelaId]);
  }
  
  // <<< NOVO MÉTODO PARA RESTAURAR A LÓGICA ORIGINAL >>>
  /// Busca parcelas concluídas HOJE que ainda não foram exportadas.
  Future<List<Parcela>> getTodaysUnexportedConcludedParcelas() async {
    final db = await _dbHelper.database;

    // Calcula o início e o fim do dia de hoje
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final maps = await db.query('parcelas', 
        where: 'status = ? AND exportada = ? AND dataColeta >= ? AND dataColeta < ?', 
        whereArgs: [
          StatusParcela.concluida.name, 
          0,
          startOfDay.toIso8601String(),
          endOfDay.toIso8601String()
        ]
    );
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  /// Busca TODAS as parcelas concluídas que ainda não foram exportadas (sem filtro de data).
  Future<List<Parcela>> getUnexportedConcludedParcelas() async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas', 
        where: 'status = ? AND exportada = ?', 
        whereArgs: [StatusParcela.concluida.name, 0]
    );
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }
  
  /// Busca TODAS as parcelas concluídas, ideal para backup completo.
  Future<List<Parcela>> getTodasAsParcelasConcluidasParaBackup() async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas', where: 'status = ?', whereArgs: [StatusParcela.concluida.name]);
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  /// Marca uma lista de parcelas como exportadas no banco de dados.
  Future<void> marcarParcelasComoExportadas(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.update('parcelas', {'exportada': 1}, where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
  }
}
// lib/data/repositories/talhao_repository.dart (VERSÃO REFATORADA)

import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:sqflite/sqflite.dart';

class TalhaoRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> insertTalhao(Talhao t) async {
    final db = await _dbHelper.database;
    final map = t.toMap();
    map[DbTalhoes.lastModified] = DateTime.now().toIso8601String();
    return await db.insert(DbTalhoes.tableName, map, conflictAlgorithm: ConflictAlgorithm.fail);
  }

  Future<int> updateTalhao(Talhao t) async {
    final db = await _dbHelper.database;
    final map = t.toMap();
    map[DbTalhoes.lastModified] = DateTime.now().toIso8601String();
    return await db.update(DbTalhoes.tableName, map, where: '${DbTalhoes.id} = ?', whereArgs: [t.id]);
  }
  
  Future<Talhao?> getTalhaoById(int id) async {
    final db = await _dbHelper.database;
    
    final maps = await db.rawQuery('''
        SELECT T.*, F.${DbFazendas.nome} as fazendaNome, A.${DbAtividades.projetoId} as ${DbTalhoes.projetoId} 
        FROM ${DbTalhoes.tableName} T
        INNER JOIN ${DbFazendas.tableName} F ON F.${DbFazendas.id} = T.${DbTalhoes.fazendaId} AND F.${DbFazendas.atividadeId} = T.${DbTalhoes.fazendaAtividadeId}
        INNER JOIN ${DbAtividades.tableName} A ON F.${DbFazendas.atividadeId} = A.${DbAtividades.id}
        WHERE T.${DbTalhoes.id} = ?
        LIMIT 1
    ''', [id]);

    if (maps.isNotEmpty) {
      return Talhao.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Talhao>> getTalhoesDaFazenda(String fazendaId, int fazendaAtividadeId) async {
    final db = await _dbHelper.database;

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT T.*, F.${DbFazendas.nome} as fazendaNome, A.${DbAtividades.projetoId} as ${DbTalhoes.projetoId} 
      FROM ${DbTalhoes.tableName} T
      INNER JOIN ${DbFazendas.tableName} F ON F.${DbFazendas.id} = T.${DbTalhoes.fazendaId} AND F.${DbFazendas.atividadeId} = T.${DbTalhoes.fazendaAtividadeId}
      INNER JOIN ${DbAtividades.tableName} A ON F.${DbFazendas.atividadeId} = A.${DbAtividades.id}
      WHERE T.${DbTalhoes.fazendaId} = ? AND T.${DbTalhoes.fazendaAtividadeId} = ?
      ORDER BY T.${DbTalhoes.nome} ASC
    ''', [fazendaId, fazendaAtividadeId]);
    
    return List.generate(maps.length, (i) => Talhao.fromMap(maps[i]));
  }

  Future<void> deleteTalhao(int id) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete(DbCubagensArvores.tableName, where: '${DbCubagensArvores.talhaoId} = ?', whereArgs: [id]);
      await txn.delete(DbParcelas.tableName, where: '${DbParcelas.talhaoId} = ?', whereArgs: [id]);
      await txn.delete(DbTalhoes.tableName, where: '${DbTalhoes.id} = ?', whereArgs: [id]);
    });
  }

  Future<double> getAreaTotalTalhoesDaFazenda(String fazendaId, int fazendaAtividadeId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT SUM(${DbTalhoes.areaHa}) as total FROM ${DbTalhoes.tableName} WHERE ${DbTalhoes.fazendaId} = ? AND ${DbTalhoes.fazendaAtividadeId} = ?',
      [fazendaId, fazendaAtividadeId]
    );
    if (result.isNotEmpty && result.first['total'] != null) return (result.first['total'] as num).toDouble();
    return 0.0;
  }
  
  Future<List<Talhao>> getTalhoesComParcelasConcluidas() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> idMaps = await db.query(
      DbParcelas.tableName,
      distinct: true,
      columns: [DbParcelas.talhaoId],
      where: '${DbParcelas.status} = ?',
      whereArgs: [StatusParcela.concluida.name]
    );
    if (idMaps.isEmpty) return [];
    
    final ids = idMaps.map((map) => map[DbParcelas.talhaoId] as int).toList();
    
    final List<Map<String, dynamic>> talhoesMaps = await db.rawQuery('''
      SELECT T.*, F.${DbFazendas.nome} as fazendaNome, A.${DbAtividades.projetoId} as ${DbTalhoes.projetoId} 
      FROM ${DbTalhoes.tableName} T
      INNER JOIN ${DbFazendas.tableName} F ON F.${DbFazendas.id} = T.${DbTalhoes.fazendaId} AND F.${DbFazendas.atividadeId} = T.${DbTalhoes.fazendaAtividadeId}
      INNER JOIN ${DbAtividades.tableName} A ON F.${DbFazendas.atividadeId} = A.${DbAtividades.id}
      WHERE T.${DbTalhoes.id} IN (${List.filled(ids.length, '?').join(',')})
    ''', ids);
    return List.generate(talhoesMaps.length, (i) => Talhao.fromMap(talhoesMaps[i]));
  }

  Future<List<Talhao>> getTodosOsTalhoes() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT T.*, F.${DbFazendas.nome} as fazendaNome, A.${DbAtividades.projetoId} as ${DbTalhoes.projetoId}
      FROM ${DbTalhoes.tableName} T
      INNER JOIN ${DbFazendas.tableName} F ON F.${DbFazendas.id} = T.${DbTalhoes.fazendaId} AND F.${DbFazendas.atividadeId} = T.${DbTalhoes.fazendaAtividadeId}
      INNER JOIN ${DbAtividades.tableName} A ON F.${DbFazendas.atividadeId} = A.${DbAtividades.id}
      ORDER BY T.${DbTalhoes.nome} ASC
    ''');
    return List.generate(maps.length, (i) => Talhao.fromMap(maps[i]));
  }
}
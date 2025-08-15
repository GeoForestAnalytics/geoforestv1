// lib/data/repositories/talhao_repository.dart (VERSÃO FINALMENTE CORRETA)

import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:sqflite/sqflite.dart';

class TalhaoRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> insertTalhao(Talhao t) async {
    final db = await _dbHelper.database;
    final map = t.toMap();
    map['lastModified'] = DateTime.now().toIso8601String();
    return await db.insert('talhoes', map, conflictAlgorithm: ConflictAlgorithm.fail);
  }

  Future<int> updateTalhao(Talhao t) async {
    final db = await _dbHelper.database;
    final map = t.toMap();
    map['lastModified'] = DateTime.now().toIso8601String();
    return await db.update('talhoes', map, where: 'id = ?', whereArgs: [t.id]);
  }
  
  // <<< CORREÇÃO PRINCIPAL AQUI >>>
  Future<Talhao?> getTalhaoById(int id) async {
    final db = await _dbHelper.database;
    
    // A consulta com JOIN para pegar o projetoId está CORRETA.
    final maps = await db.rawQuery('''
        SELECT T.*, F.nome as fazendaNome, A.projetoId as projetoId 
        FROM talhoes T
        INNER JOIN fazendas F ON F.id = T.fazendaId AND F.atividadeId = T.fazendaAtividadeId
        INNER JOIN atividades A ON F.atividadeId = A.id
        WHERE T.id = ?
        LIMIT 1
    ''', [id]);

    if (maps.isNotEmpty) {
      // O factory Talhao.fromMap saberá como ler o projetoId.
      return Talhao.fromMap(maps.first);
    }
    return null;
  }

  // <<< CORREÇÃO APLICADA AQUI TAMBÉM >>>
  Future<List<Talhao>> getTalhoesDaFazenda(String fazendaId, int fazendaAtividadeId) async {
    final db = await _dbHelper.database;

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT T.*, F.nome as fazendaNome, A.projetoId as projetoId 
      FROM talhoes T
      INNER JOIN fazendas F ON F.id = T.fazendaId AND F.atividadeId = T.fazendaAtividadeId
      INNER JOIN atividades A ON F.atividadeId = A.id
      WHERE T.fazendaId = ? AND T.fazendaAtividadeId = ?
      ORDER BY T.nome ASC
    ''', [fazendaId, fazendaAtividadeId]);
    
    return List.generate(maps.length, (i) => Talhao.fromMap(maps[i]));
  }

  Future<void> deleteTalhao(int id) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('cubagens_arvores', where: 'talhaoId = ?', whereArgs: [id]);
      await txn.delete('parcelas', where: 'talhaoId = ?', whereArgs: [id]);
      await txn.delete('talhoes', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<double> getAreaTotalTalhoesDaFazenda(String fazendaId, int fazendaAtividadeId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT SUM(areaHa) as total FROM talhoes WHERE fazendaId = ? AND fazendaAtividadeId = ?', [fazendaId, fazendaAtividadeId]);
    if (result.isNotEmpty && result.first['total'] != null) return (result.first['total'] as num).toDouble();
    return 0.0;
  }
  
  Future<List<Talhao>> getTalhoesComParcelasConcluidas() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> idMaps = await db.query('parcelas', distinct: true, columns: ['talhaoId'], where: 'status = ?', whereArgs: [StatusParcela.concluida.name]);
    if (idMaps.isEmpty) return [];
    final ids = idMaps.map((map) => map['talhaoId'] as int).toList();
    
    // <<< CORREÇÃO APLICADA AQUI TAMBÉM >>>
    final List<Map<String, dynamic>> talhoesMaps = await db.rawQuery('''
      SELECT T.*, F.nome as fazendaNome, A.projetoId as projetoId 
      FROM talhoes T
      INNER JOIN fazendas F ON F.id = T.fazendaId AND F.atividadeId = T.fazendaAtividadeId
      INNER JOIN atividades A ON F.atividadeId = A.id
      WHERE T.id IN (${List.filled(ids.length, '?').join(',')})
    ''', ids);
    return List.generate(talhoesMaps.length, (i) => Talhao.fromMap(talhoesMaps[i]));
  }

  Future<List<Talhao>> getTodosOsTalhoes() async {
    final db = await _dbHelper.database;
    // <<< CORREÇÃO APLICADA AQUI TAMBÉM >>>
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT T.*, F.nome as fazendaNome, A.projetoId as projetoId
      FROM talhoes T
      INNER JOIN fazendas F ON F.id = T.fazendaId AND F.atividadeId = T.fazendaAtividadeId
      INNER JOIN atividades A ON F.atividadeId = A.id
      ORDER BY T.nome ASC
    ''');
    return List.generate(maps.length, (i) => Talhao.fromMap(maps[i]));
  }
}

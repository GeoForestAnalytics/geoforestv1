// lib/data/repositories/talhao_repository.dart (VERSÃO CORRIGIDA)

import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:sqflite/sqflite.dart';

class TalhaoRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // AJUSTE 1: Insert agora apenas insere, usando .fail para segurança.
  Future<int> insertTalhao(Talhao t) async {
    final db = await _dbHelper.database;
    return await db.insert('talhoes', t.toMap(), conflictAlgorithm: ConflictAlgorithm.fail);
  }

  // AJUSTE 2: Adiciona um método de update explícito e seguro.
  Future<int> updateTalhao(Talhao t) async {
    final db = await _dbHelper.database;
    return await db.update('talhoes', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
  }
  
  // AJUSTE 3: Adiciona um método para buscar um talhão específico (necessário para a UI)
  Future<Talhao?> getTalhaoById(int id) async {
  final db = await _dbHelper.database;
  
  // <<< INÍCIO DA CORREÇÃO >>>
  // A consulta agora faz JOIN com 'fazendas' E 'atividades' para pegar
  // tanto o 'fazendaNome' quanto o 'projetoId'.
  final maps = await db.rawQuery('''
      SELECT T.*, F.nome as fazendaNome, A.projetoId as projetoId 
      FROM talhoes T
      INNER JOIN fazendas F ON F.id = T.fazendaId AND F.atividadeId = T.fazendaAtividadeId
      INNER JOIN atividades A ON F.atividadeId = A.id
      WHERE T.id = ?
      LIMIT 1
  ''', [id]);
  // <<< FIM DA CORREÇÃO >>>

  if (maps.isNotEmpty) {
    // Agora o 'maps.first' já contém o 'projetoId', e o factory Talhao.fromMap
    // que você corrigiu saberá como lê-lo.
    return Talhao.fromMap(maps.first);
  }
  return null;
}

// MÉTODO getTalhoesDaFazenda CORRIGIDO
Future<List<Talhao>> getTalhoesDaFazenda(String fazendaId, int fazendaAtividadeId) async {
  final db = await _dbHelper.database;

  // <<< INÍCIO DA CORREÇÃO >>>
  // A mesma lógica de JOIN é aplicada aqui.
  final List<Map<String, dynamic>> maps = await db.rawQuery('''
    SELECT T.*, F.nome as fazendaNome, A.projetoId as projetoId 
    FROM talhoes T
    INNER JOIN fazendas F ON F.id = T.fazendaId AND F.atividadeId = T.fazendaAtividadeId
    INNER JOIN atividades A ON F.atividadeId = A.id
    WHERE T.fazendaId = ? AND T.fazendaAtividadeId = ?
    ORDER BY T.nome ASC
  ''', [fazendaId, fazendaAtividadeId]);
  // <<< FIM DA CORREÇÃO >>>
  
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
    final List<Map<String, dynamic>> talhoesMaps = await db.rawQuery('''
      SELECT T.*, F.nome as fazendaNome 
      FROM talhoes T
      INNER JOIN fazendas F ON F.id = T.fazendaId AND F.atividadeId = T.fazendaAtividadeId
      WHERE T.id IN (${List.filled(ids.length, '?').join(',')})
    ''', ids);
    return List.generate(talhoesMaps.length, (i) => Talhao.fromMap(talhoesMaps[i]));
  }

  Future<List<Talhao>> getTodosOsTalhoes() async {
    final db = await _dbHelper.database;
    // Usamos a mesma query complexa para já trazer o nome da fazenda junto
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
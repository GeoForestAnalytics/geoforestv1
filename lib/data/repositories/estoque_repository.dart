import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/estoque_saida_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EstoqueRepository {
  Future<List<EstoqueSaida>> getTodosEstoques() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(DbEstoqueSaida.tableName,
        orderBy: '${DbEstoqueSaida.dataRegistro} DESC');
    return rows.map(EstoqueSaida.fromMap).toList();
  }

  Future<List<EstoqueSaida>> getEstoquesDoTalhao(int talhaoId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      DbEstoqueSaida.tableName,
      where: '${DbEstoqueSaida.talhaoId} = ?',
      whereArgs: [talhaoId],
      orderBy: '${DbEstoqueSaida.dataRegistro} DESC',
    );
    return rows.map(EstoqueSaida.fromMap).toList();
  }

  Future<List<EstoqueSaida>> getEstoquesPorLideresNomes({
    bool apenasNaoExportadas = true,
    Set<String>? lideresNomes,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final where = <String>[];
    final args = <dynamic>[];

    if (apenasNaoExportadas) where.add('${DbEstoqueSaida.exportada} = 0');
    if (lideresNomes != null && lideresNomes.isNotEmpty) {
      where.add('${DbEstoqueSaida.nomeLider} IN (${lideresNomes.map((_) => '?').join(',')})');
      args.addAll(lideresNomes);
    }

    final rows = await db.query(
      DbEstoqueSaida.tableName,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: '${DbEstoqueSaida.dataRegistro} DESC',
    );
    return rows.map(EstoqueSaida.fromMap).toList();
  }

  Future<List<EstoqueSaida>> getEstoquesPorLideres({bool apenasNaoExportadas = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final equipe = prefs.getStringList('equipeAtual') ?? [];

    final db = await DatabaseHelper.instance.database;
    List<Map<String, dynamic>> rows;

    if (equipe.isEmpty) {
      rows = await db.query(DbEstoqueSaida.tableName,
          where: apenasNaoExportadas ? '${DbEstoqueSaida.exportada} = 0' : null,
          orderBy: '${DbEstoqueSaida.dataRegistro} DESC');
    } else {
      final placeholders = List.filled(equipe.length, '?').join(', ');
      final whereExportada = apenasNaoExportadas
          ? ' AND ${DbEstoqueSaida.exportada} = 0'
          : '';
      rows = await db.rawQuery(
        'SELECT * FROM ${DbEstoqueSaida.tableName} '
        'WHERE ${DbEstoqueSaida.nomeLider} IN ($placeholders)$whereExportada '
        'ORDER BY ${DbEstoqueSaida.dataRegistro} DESC',
        equipe,
      );
    }
    return rows.map(EstoqueSaida.fromMap).toList();
  }

  Future<int> inserir(EstoqueSaida e) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert(DbEstoqueSaida.tableName, e.toMap());
  }

  Future<void> atualizar(EstoqueSaida e) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      DbEstoqueSaida.tableName,
      e.copyWith(isSynced: false).toMap(),
      where: '${DbEstoqueSaida.id} = ?',
      whereArgs: [e.id],
    );
  }

  Future<void> deletar(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(DbEstoqueSaida.tableName,
        where: '${DbEstoqueSaida.id} = ?', whereArgs: [id]);
  }

  Future<int> getUnsyncedEstoquesCount() async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM ${DbEstoqueSaida.tableName} WHERE ${DbEstoqueSaida.isSynced} = 0');
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<EstoqueSaida?> getOneUnsyncedEstoque() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(DbEstoqueSaida.tableName,
        where: '${DbEstoqueSaida.isSynced} = 0', limit: 1);
    if (rows.isEmpty) return null;
    return EstoqueSaida.fromMap(rows.first);
  }

  Future<void> markEstoqueAsSynced(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      DbEstoqueSaida.tableName,
      {DbEstoqueSaida.isSynced: 1},
      where: '${DbEstoqueSaida.id} = ?',
      whereArgs: [id],
    );
  }

  Future<void> marcarComoExportadas(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      DbEstoqueSaida.tableName,
      {DbEstoqueSaida.exportada: 1, DbEstoqueSaida.lastModified: now},
      where: '${DbEstoqueSaida.id} IN (${ids.join(',')})',
    );
  }
}

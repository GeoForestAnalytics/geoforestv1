import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/pilha_madeira_model.dart';
import 'package:sqflite/sqflite.dart';

class PilhaRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // Garante que colunas opcionais existam antes de qualquer escrita.
  // Evita falha quando a migração não rodou (ex: dispositivo já estava na versão atual).
  Future<void> ensureSchema() async {
    final db = await _dbHelper.database;
    await _ensureColumns(db);
  }

  Future<void> _ensureColumns(Database db) async {
    final cols = [
      (DbPilhasMadeira.comprimentoToraReal, 'REAL'),
      (DbPilhasMadeira.observacoes, 'TEXT'),
      (DbPilhasMadeira.fotos, 'TEXT'),
      (DbPilhasMadeira.fatorEmpilhamento, 'REAL DEFAULT 0.65'),
      (DbPilhasMadeira.isSynced, 'INTEGER DEFAULT 0 NOT NULL'),
      (DbPilhasMadeira.exportada, 'INTEGER DEFAULT 0 NOT NULL'),
      (DbPilhasMadeira.lastModified, 'TEXT'),
      (DbPilhasMadeira.nomeLider, 'TEXT'),
    ];
    final info = await db.rawQuery('PRAGMA table_info(${DbPilhasMadeira.tableName})');
    final existing = info.map((r) => r['name'] as String).toSet();
    for (final col in cols) {
      if (!existing.contains(col.$1)) {
        await db.execute('ALTER TABLE ${DbPilhasMadeira.tableName} ADD COLUMN ${col.$1} ${col.$2}');
      }
    }
  }

  // ── Centroids ──────────────────────────────────────────────────────────────

  Future<CentroidePilha?> getCentroideParaTalhao(int talhaoId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(DbCentroidesPilha.tableName,
        where: '${DbCentroidesPilha.talhaoId} = ?', whereArgs: [talhaoId], limit: 1);
    if (maps.isEmpty) return null;
    return CentroidePilha.fromMap(maps.first);
  }

  Future<CentroidePilha?> getCentroideById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(DbCentroidesPilha.tableName,
        where: '${DbCentroidesPilha.id} = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return CentroidePilha.fromMap(maps.first);
  }

  Future<List<CentroidePilha>> getTodosCentroides() async {
    final db = await _dbHelper.database;
    final maps = await db.query(DbCentroidesPilha.tableName,
        orderBy: '${DbCentroidesPilha.nomeFazenda}, ${DbCentroidesPilha.nomeTalhao}');
    return maps.map((m) => CentroidePilha.fromMap(m)).toList();
  }

  Future<List<CentroidePilha>> getCentroidesParaAtividade(int atividadeId) async {
    final db = await _dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT c.* FROM ${DbCentroidesPilha.tableName} c
      JOIN ${DbTalhoes.tableName} t ON c.${DbCentroidesPilha.talhaoId} = t.${DbTalhoes.id}
      JOIN ${DbFazendas.tableName} f ON t.${DbTalhoes.fazendaId} = f.${DbFazendas.id}
        AND t.${DbTalhoes.fazendaAtividadeId} = f.${DbFazendas.atividadeId}
      WHERE f.${DbFazendas.atividadeId} = ?
    ''', [atividadeId]);
    return maps.map((m) => CentroidePilha.fromMap(m)).toList();
  }

  // ── Pilhas ─────────────────────────────────────────────────────────────────

  Future<PilhaMadeira?> getPilhaById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(DbPilhasMadeira.tableName,
        where: '${DbPilhasMadeira.id} = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return PilhaMadeira.fromMap(maps.first);
  }

  Future<List<PilhaMadeira>> getPilhasDoTalhao(int talhaoId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbPilhasMadeira.tableName,
      where: '${DbPilhasMadeira.talhaoId} = ?',
      whereArgs: [talhaoId],
      orderBy: '${DbPilhasMadeira.numeroPilha} ASC',
    );
    return maps.map((m) => PilhaMadeira.fromMap(m)).toList();
  }

  Future<PilhaMadeira?> getOneUnsyncedPilha() async {
    final db = await _dbHelper.database;
    await _ensureColumns(db);
    // Cobre tanto isSynced = 0 quanto NULL (SQLite trata NULL != 0)
    final maps = await db.query(
      DbPilhasMadeira.tableName,
      where: '(${DbPilhasMadeira.isSynced} = 0 OR ${DbPilhasMadeira.isSynced} IS NULL)',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return PilhaMadeira.fromMap(maps.first);
  }

  Future<int> getUnsyncedPilhasCount() async {
    final db = await _dbHelper.database;
    await _ensureColumns(db);
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM ${DbPilhasMadeira.tableName} WHERE (${DbPilhasMadeira.isSynced} = 0 OR ${DbPilhasMadeira.isSynced} IS NULL)',
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<void> markPilhaAsSynced(int id) async {
    final db = await _dbHelper.database;
    await db.update(
      DbPilhasMadeira.tableName,
      {
        DbPilhasMadeira.isSynced: 1,
        DbPilhasMadeira.lastModified: DateTime.now().toIso8601String(),
      },
      where: '${DbPilhasMadeira.id} = ?',
      whereArgs: [id],
    );
  }

  Future<int> getProximoNumeroPilha(String nomeFazenda) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT MAX(${DbPilhasMadeira.numeroPilha}) as maxNum FROM ${DbPilhasMadeira.tableName} WHERE ${DbPilhasMadeira.nomeFazenda} = ?',
      [nomeFazenda],
    );
    final maxNum = (result.first['maxNum'] as int?) ?? 0;
    return maxNum + 1;
  }

  Future<List<PilhaMadeira>> getUnexportedPilhasByLider(String nomeLider) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbPilhasMadeira.tableName,
      where: '${DbPilhasMadeira.nomeLider} = ? AND ${DbPilhasMadeira.exportada} = 0',
      whereArgs: [nomeLider],
      orderBy: '${DbPilhasMadeira.dataColeta} ASC',
    );
    return maps.map((m) => PilhaMadeira.fromMap(m)).toList();
  }

  Future<List<PilhaMadeira>> getAllPilhasByLider(String nomeLider) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbPilhasMadeira.tableName,
      where: '${DbPilhasMadeira.nomeLider} = ?',
      whereArgs: [nomeLider],
      orderBy: '${DbPilhasMadeira.dataColeta} ASC',
    );
    return maps.map((m) => PilhaMadeira.fromMap(m)).toList();
  }

  Future<void> marcarPilhasComoExportadas(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.update(
      DbPilhasMadeira.tableName,
      {DbPilhasMadeira.exportada: 1, DbPilhasMadeira.lastModified: DateTime.now().toIso8601String()},
      where: '${DbPilhasMadeira.id} IN (${ids.map((_) => '?').join(',')})',
      whereArgs: ids,
    );
  }

  Future<Set<String>> getDistinctLideres() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT DISTINCT ${DbPilhasMadeira.nomeLider} FROM ${DbPilhasMadeira.tableName} WHERE ${DbPilhasMadeira.nomeLider} IS NOT NULL',
    );
    return result.map((r) => r[DbPilhasMadeira.nomeLider] as String).toSet();
  }

  Future<List<PilhaMadeira>> getPilhasPorLideres({
    required bool apenasNaoExportadas,
    Set<String>? lideresNomes,
  }) async {
    final db = await _dbHelper.database;
    final where = <String>[];
    final args = <dynamic>[];

    if (apenasNaoExportadas) {
      where.add('${DbPilhasMadeira.exportada} = 0');
    }
    if (lideresNomes != null && lideresNomes.isNotEmpty) {
      where.add('${DbPilhasMadeira.nomeLider} IN (${lideresNomes.map((_) => '?').join(',')})');
      args.addAll(lideresNomes);
    }

    final maps = await db.query(
      DbPilhasMadeira.tableName,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: '${DbPilhasMadeira.dataColeta} ASC',
    );
    return maps.map((m) => PilhaMadeira.fromMap(m)).toList();
  }

  Future<int> savePilha(PilhaMadeira pilha) async {
    final db = await _dbHelper.database;
    await _ensureColumns(db);
    final map = pilha.toMap();
    map.remove(DbPilhasMadeira.id);
    return await db.insert(DbPilhasMadeira.tableName, map,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePilha(PilhaMadeira pilha) async {
    final db = await _dbHelper.database;
    await _ensureColumns(db);
    await db.update(
      DbPilhasMadeira.tableName,
      pilha.toMap(),
      where: '${DbPilhasMadeira.id} = ?',
      whereArgs: [pilha.id],
    );
  }

  Future<void> deletePilha(int id) async {
    final db = await _dbHelper.database;
    await db.delete(DbPilhasMadeira.tableName,
        where: '${DbPilhasMadeira.id} = ?', whereArgs: [id]);
  }

  Future<List<PilhaMadeira>> getPilhasDoDiaPorTalhao({
    required String nomeLider,
    required DateTime dataSelecionada,
    required int talhaoId,
  }) async {
    final db = await _dbHelper.database;
    final m = dataSelecionada.month.toString().padLeft(2, '0');
    final d = dataSelecionada.day.toString().padLeft(2, '0');
    final dateStr = '${dataSelecionada.year}-$m-$d';
    final maps = await db.rawQuery(
      'SELECT * FROM ${DbPilhasMadeira.tableName} '
      'WHERE LOWER(${DbPilhasMadeira.nomeLider}) = LOWER(?) '
      'AND ${DbPilhasMadeira.talhaoId} = ? '
      'AND ${DbPilhasMadeira.dataColeta} LIKE ?',
      [nomeLider, talhaoId, '$dateStr%'],
    );
    return maps.map((m) => PilhaMadeira.fromMap(m)).toList();
  }

  Future<List<String>> getLideresNoDia({
    required DateTime data,
    required int talhaoId,
  }) async {
    final db = await _dbHelper.database;
    final m = data.month.toString().padLeft(2, '0');
    final d = data.day.toString().padLeft(2, '0');
    final dateStr = '${data.year}-$m-$d';
    final maps = await db.rawQuery(
      'SELECT DISTINCT ${DbPilhasMadeira.nomeLider} FROM ${DbPilhasMadeira.tableName} '
      'WHERE ${DbPilhasMadeira.talhaoId} = ? AND ${DbPilhasMadeira.dataColeta} LIKE ?',
      [talhaoId, '$dateStr%'],
    );
    return maps
        .map((r) => r[DbPilhasMadeira.nomeLider] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
  }

  Future<List<int>> getTalhaoIdsNaData(String nomeLider, DateTime data) async {
    final db = await _dbHelper.database;
    final m = data.month.toString().padLeft(2, '0');
    final d = data.day.toString().padLeft(2, '0');
    final dateStr = '${data.year}-$m-$d';
    final maps = await db.rawQuery(
      'SELECT DISTINCT ${DbPilhasMadeira.talhaoId} FROM ${DbPilhasMadeira.tableName} '
      'WHERE LOWER(${DbPilhasMadeira.nomeLider}) = LOWER(?) AND ${DbPilhasMadeira.dataColeta} LIKE ?',
      [nomeLider, '$dateStr%'],
    );
    return maps
        .map((r) => r[DbPilhasMadeira.talhaoId] as int?)
        .whereType<int>()
        .toList();
  }
}

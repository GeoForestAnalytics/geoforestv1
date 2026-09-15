import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/silvi_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SilviRepository {
  final _db = DatabaseHelper.instance;

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<List<String>?> _getLiderNames() async {
    final prefs = await SharedPreferences.getInstance();
    final lideres = prefs.getStringList('equipeAtual');
    return (lideres != null && lideres.isNotEmpty) ? lideres : null;
  }

  // ── Centroides ────────────────────────────────────────────────────────────

  Future<List<CentroideSilvi>> getCentroidesParaAtividade(int atividadeId) async {
    final db = await _db.database;
    final maps = await db.rawQuery('''
      SELECT c.* FROM ${DbCentroidesSilvi.tableName} c
      JOIN ${DbTalhoes.tableName} t ON c.${DbCentroidesSilvi.talhaoId} = t.${DbTalhoes.id}
      JOIN ${DbFazendas.tableName} f ON t.${DbTalhoes.fazendaId} = f.${DbFazendas.id}
        AND t.${DbTalhoes.fazendaAtividadeId} = f.${DbFazendas.atividadeId}
      WHERE f.${DbFazendas.atividadeId} = ?
    ''', [atividadeId]);
    return maps.map(CentroideSilvi.fromMap).toList();
  }

  Future<List<CentroideSilvi>> getTodosCentroides() async {
    final db = await _db.database;
    final maps = await db.query(DbCentroidesSilvi.tableName);
    return maps.map(CentroideSilvi.fromMap).toList();
  }

  Future<CentroideSilvi?> getCentroideParaTalhao(int talhaoId) async {
    final db = await _db.database;
    final maps = await db.query(
      DbCentroidesSilvi.tableName,
      where: '${DbCentroidesSilvi.talhaoId} = ?',
      whereArgs: [talhaoId],
    );
    if (maps.isEmpty) return null;
    return CentroideSilvi.fromMap(maps.first);
  }

  Future<int> inserirCentroide(CentroideSilvi c) async {
    final db = await _db.database;
    return await db.insert(DbCentroidesSilvi.tableName, c.toMap());
  }

  Future<void> atualizarCentroide(CentroideSilvi c) async {
    final db = await _db.database;
    await db.update(
      DbCentroidesSilvi.tableName,
      c.toMap(),
      where: '${DbCentroidesSilvi.id} = ?',
      whereArgs: [c.id],
    );
  }

  Future<void> deletarCentroide(int id) async {
    final db = await _db.database;
    await db.delete(
      DbCentroidesSilvi.tableName,
      where: '${DbCentroidesSilvi.id} = ?',
      whereArgs: [id],
    );
  }

  // ── Operações ─────────────────────────────────────────────────────────────

  Future<List<OperacaoSilvi>> getOperacoesDoTalhao(int talhaoId) async {
    final db = await _db.database;
    final maps = await db.query(
      DbOperacoesSilvi.tableName,
      where: '${DbOperacoesSilvi.talhaoId} = ?',
      whereArgs: [talhaoId],
      orderBy: '${DbOperacoesSilvi.dataExecucao} DESC',
    );
    return maps.map(OperacaoSilvi.fromMap).toList();
  }

  Future<List<OperacaoSilvi>> getTodasOperacoes({
    bool apenasNaoExportadas = false,
  }) async {
    final db = await _db.database;
    final where = apenasNaoExportadas ? '${DbOperacoesSilvi.exportada} = 0' : null;
    final maps = await db.query(
      DbOperacoesSilvi.tableName,
      where: where,
      orderBy: '${DbOperacoesSilvi.dataExecucao} DESC',
    );
    return maps.map(OperacaoSilvi.fromMap).toList();
  }

  /// Retorna operações filtradas pelos líderes da equipe atual (SharedPreferences).
  /// Se não houver equipe configurada, retorna todas.
  Future<List<OperacaoSilvi>> getOperacoesPorLideres({
    bool apenasNaoExportadas = false,
  }) async {
    final db = await _db.database;
    final lideres = await _getLiderNames();

    String? where;
    List<Object>? whereArgs;

    if (lideres != null) {
      final placeholders = List.filled(lideres.length, '?').join(', ');
      final liderClause = '${DbOperacoesSilvi.nomeLider} IN ($placeholders)';
      where = apenasNaoExportadas
          ? '$liderClause AND ${DbOperacoesSilvi.exportada} = 0'
          : liderClause;
      whereArgs = lideres;
    } else if (apenasNaoExportadas) {
      where = '${DbOperacoesSilvi.exportada} = 0';
    }

    final maps = await db.query(
      DbOperacoesSilvi.tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: '${DbOperacoesSilvi.dataExecucao} DESC',
    );
    return maps.map(OperacaoSilvi.fromMap).toList();
  }

  Future<int> inserirOperacao(OperacaoSilvi op) async {
    final db = await _db.database;
    return await db.insert(DbOperacoesSilvi.tableName, op.toMap());
  }

  Future<void> atualizarOperacao(OperacaoSilvi op) async {
    final db = await _db.database;
    await db.update(
      DbOperacoesSilvi.tableName,
      op.toMap(),
      where: '${DbOperacoesSilvi.id} = ?',
      whereArgs: [op.id],
    );
  }

  Future<void> deletarOperacao(int id) async {
    final db = await _db.database;
    await db.delete(
      DbOperacoesSilvi.tableName,
      where: '${DbOperacoesSilvi.id} = ?',
      whereArgs: [id],
    );
  }

  Future<void> marcarComoExportadas(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _db.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE ${DbOperacoesSilvi.tableName} SET ${DbOperacoesSilvi.exportada} = 1 WHERE ${DbOperacoesSilvi.id} IN ($placeholders)',
      ids,
    );
  }

  Future<int> getUnsyncedOperacoesCount() async {
    final db = await _db.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM ${DbOperacoesSilvi.tableName} WHERE ${DbOperacoesSilvi.isSynced} = 0');
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<OperacaoSilvi?> getOneUnsyncedOperacao() async {
    final db = await _db.database;
    final rows = await db.query(DbOperacoesSilvi.tableName,
        where: '${DbOperacoesSilvi.isSynced} = 0', limit: 1);
    if (rows.isEmpty) return null;
    return OperacaoSilvi.fromMap(rows.first);
  }

  Future<void> markOperacaoAsSynced(int id) async {
    final db = await _db.database;
    await db.update(DbOperacoesSilvi.tableName, {DbOperacoesSilvi.isSynced: 1},
        where: '${DbOperacoesSilvi.id} = ?', whereArgs: [id]);
  }

  Future<void> marcarComoSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _db.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE ${DbOperacoesSilvi.tableName} SET ${DbOperacoesSilvi.isSynced} = 1 WHERE ${DbOperacoesSilvi.id} IN ($placeholders)',
      ids,
    );
  }

  Future<List<OperacaoSilvi>> getOperacoesDoDiaPorTalhao({
    required String nomeLider,
    required DateTime dataSelecionada,
    required int talhaoId,
  }) async {
    final db = await _db.database;
    final m = dataSelecionada.month.toString().padLeft(2, '0');
    final d = dataSelecionada.day.toString().padLeft(2, '0');
    final dateStr = '${dataSelecionada.year}-$m-$d';
    final maps = await db.rawQuery(
      'SELECT * FROM ${DbOperacoesSilvi.tableName} '
      'WHERE LOWER(${DbOperacoesSilvi.nomeLider}) = LOWER(?) '
      'AND ${DbOperacoesSilvi.talhaoId} = ? '
      'AND ${DbOperacoesSilvi.dataExecucao} LIKE ?',
      [nomeLider, talhaoId, '$dateStr%'],
    );
    return maps.map(OperacaoSilvi.fromMap).toList();
  }

  Future<List<String>> getLideresNoDia({
    required DateTime data,
    required int talhaoId,
  }) async {
    final db = await _db.database;
    final m = data.month.toString().padLeft(2, '0');
    final d = data.day.toString().padLeft(2, '0');
    final dateStr = '${data.year}-$m-$d';
    final maps = await db.rawQuery(
      'SELECT DISTINCT ${DbOperacoesSilvi.nomeLider} FROM ${DbOperacoesSilvi.tableName} '
      'WHERE ${DbOperacoesSilvi.talhaoId} = ? AND ${DbOperacoesSilvi.dataExecucao} LIKE ?',
      [talhaoId, '$dateStr%'],
    );
    return maps
        .map((r) => r[DbOperacoesSilvi.nomeLider] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
  }

  Future<List<int>> getTalhaoIdsNaData(String nomeLider, DateTime data) async {
    final db = await _db.database;
    final m = data.month.toString().padLeft(2, '0');
    final d = data.day.toString().padLeft(2, '0');
    final dateStr = '${data.year}-$m-$d';
    final maps = await db.rawQuery(
      'SELECT DISTINCT ${DbOperacoesSilvi.talhaoId} FROM ${DbOperacoesSilvi.tableName} '
      'WHERE LOWER(${DbOperacoesSilvi.nomeLider}) = LOWER(?) AND ${DbOperacoesSilvi.dataExecucao} LIKE ?',
      [nomeLider, '$dateStr%'],
    );
    return maps
        .map((r) => r[DbOperacoesSilvi.talhaoId] as int?)
        .whereType<int>()
        .toList();
  }

  Future<List<String>> getDistinctLideres() async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      'SELECT DISTINCT ${DbOperacoesSilvi.nomeLider} FROM ${DbOperacoesSilvi.tableName} '
      'WHERE ${DbOperacoesSilvi.nomeLider} IS NOT NULL AND ${DbOperacoesSilvi.nomeLider} != \'\'',
    );
    return maps
        .map((r) => r[DbOperacoesSilvi.nomeLider] as String)
        .toList()..sort();
  }

  /// Totais agregados por talhão para uso no mapa e dashboard.
  Future<Map<int, TalhaoResumoSilvi>> getResumosPorTalhao() async {
    final db = await _db.database;

    final operacoes = await db.query(DbOperacoesSilvi.tableName);
    final centroides = await db.query(DbCentroidesSilvi.tableName);

    final resumos = <int, TalhaoResumoSilvi>{};

    for (final c in centroides) {
      final id = c[DbCentroidesSilvi.talhaoId] as int?;
      if (id == null) continue;
      resumos[id] = TalhaoResumoSilvi.fromCentroide(CentroideSilvi.fromMap(c));
    }

    for (final o in operacoes) {
      final id = o[DbOperacoesSilvi.talhaoId] as int?;
      if (id == null) continue;
      resumos.putIfAbsent(id, () => TalhaoResumoSilvi(talhaoId: id));
      final area = (o[DbOperacoesSilvi.areaAplicadaHa] as num?)?.toDouble() ?? 0;
      final tipo = o[DbOperacoesSilvi.tipo] as String? ?? 'outro';
      resumos[id]!.adicionarOperacao(tipo, area);
    }

    return resumos;
  }
}

// ── Resumo agregado por talhão (uso interno do repositório) ─────────────────

class TalhaoResumoSilvi {
  final int talhaoId;
  String nomeFazenda;
  String nomeTalhao;
  double? areaTotalHa;
  final Map<String, double> areaPlaneadaPorTipo = {};  // tipo → ha planejado
  final Map<String, double> areaAplicadaPorTipo = {};  // tipo → ha executado

  TalhaoResumoSilvi({
    required this.talhaoId,
    this.nomeFazenda = '',
    this.nomeTalhao = '',
    this.areaTotalHa,
  });

  factory TalhaoResumoSilvi.fromCentroide(CentroideSilvi c) {
    final r = TalhaoResumoSilvi(
      talhaoId: c.talhaoId ?? 0,
      nomeFazenda: c.nomeFazenda,
      nomeTalhao: c.nomeTalhao,
      areaTotalHa: c.areaTotalHa,
    );
    for (final op in c.operacoesPlanejadas) {
      if (op.areaHa != null && op.areaHa! > 0) {
        r.areaPlaneadaPorTipo[op.tipo] = op.areaHa!;
      }
    }
    return r;
  }

  void adicionarOperacao(String tipo, double areaHa) {
    areaAplicadaPorTipo[tipo] = (areaAplicadaPorTipo[tipo] ?? 0) + areaHa;
  }

  double get totalPlaneado =>
      areaPlaneadaPorTipo.values.fold(0, (s, v) => s + v);

  double get totalAplicado =>
      areaAplicadaPorTipo.values.fold(0, (s, v) => s + v);

  double progressoPorTipo(String tipo) {
    final plan = areaPlaneadaPorTipo[tipo];
    if (plan == null || plan == 0) return 0;
    return ((areaAplicadaPorTipo[tipo] ?? 0) / plan).clamp(0.0, 1.0);
  }
}

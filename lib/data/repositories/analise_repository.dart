// lib/data/repositories/analise_repository.dart (VERSÃO REFATORADA)

import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';

class AnaliseRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ParcelaRepository _parcelaRepository = ParcelaRepository();

  Future<Map<String, double>> getDistribuicaoPorCodigo(int parcelaId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT ${DbArvores.codigo}, COUNT(*) as total FROM ${DbArvores.tableName} WHERE ${DbArvores.parcelaId} = ? GROUP BY ${DbArvores.codigo}',
      [parcelaId],
    );
    if (result.isEmpty) return {};
    return {
      for (var row in result)
        (row[DbArvores.codigo] as String): (row['total'] as int).toDouble()
    };
  }

  Future<List<Map<String, dynamic>>> getValoresCAP(int parcelaId) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      DbArvores.tableName,
      columns: [DbArvores.cap, DbArvores.codigo],
      where: '${DbArvores.parcelaId} = ?',
      whereArgs: [parcelaId],
    );
    if (result.isEmpty) return [];
    return result.map((row) => {
      'cap': row[DbArvores.cap] as double,
      'codigo': row[DbArvores.codigo] as String,
    }).toList();
  }

  Future<Map<String, dynamic>> getDadosAgregadosDoTalhao(int talhaoId) async {
    final parcelas = await _parcelaRepository.getParcelasDoTalhao(talhaoId);
    final concluidas = parcelas.where((p) => p.status == StatusParcela.concluida).toList();
    final arvores = <Arvore>[];
    for (final p in concluidas) {
      if (p.dbId != null) {
        arvores.addAll(await _parcelaRepository.getArvoresDaParcela(p.dbId!));
      }
    }
    return {'parcelas': concluidas, 'arvores': arvores};
  }
}
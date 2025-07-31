// lib/data/repositories/analise_repository.dart
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart'; // Importa o novo repositório
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';

class AnaliseRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  // O repositório de análise pode usar outros repositórios para compor os dados.
  final ParcelaRepository _parcelaRepository = ParcelaRepository();

  Future<Map<String, double>> getDistribuicaoPorCodigo(int parcelaId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT codigo, COUNT(*) as total FROM arvores WHERE parcelaId = ? GROUP BY codigo', [parcelaId]);
    if (result.isEmpty) return {};
    return { for (var row in result) (row['codigo'] as String): (row['total'] as int).toDouble() };
  }

  Future<List<Map<String, dynamic>>> getValoresCAP(int parcelaId) async {
    final db = await _dbHelper.database;
    final result = await db.query('arvores', columns: ['cap', 'codigo'], where: 'parcelaId = ?', whereArgs: [parcelaId]);
    if (result.isEmpty) return [];
    return result.map((row) => {'cap': row['cap'] as double, 'codigo': row['codigo'] as String}).toList();
  }

  /// Método que busca dados agregados de um talhão, agora usando o ParcelaRepository.
  Future<Map<String, dynamic>> getDadosAgregadosDoTalhao(int talhaoId) async {
    // Usa os métodos já refatorados do ParcelaRepository
    final parcelas = await _parcelaRepository.getParcelasDoTalhao(talhaoId);
    final concluidas = parcelas.where((p) => p.status == StatusParcela.concluida).toList();
    final arvores = <Arvore>[];
    for (final p in concluidas) {
      if (p.dbId != null) arvores.addAll(await _parcelaRepository.getArvoresDaParcela(p.dbId!));
    }
    return {'parcelas': concluidas, 'arvores': arvores};
  }
}
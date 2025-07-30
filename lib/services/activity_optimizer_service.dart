// lib/services/activity_optimizer_service.dart (NOVO ARQUIVO)

import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class ActivityOptimizerService {
  final DatabaseHelper _dbHelper;

  // O serviço recebe uma instância do DatabaseHelper para poder interagir com o banco.
  ActivityOptimizerService({required DatabaseHelper dbHelper}) : _dbHelper = dbHelper;

  /// Encontra e remove talhões de uma atividade específica que não possuem nenhuma parcela associada.
  /// Retorna o número de talhões que foram removidos.
  Future<int> otimizarAtividade(int atividadeId) async {
    final db = await _dbHelper.database;
    int talhoesRemovidos = 0;

    // 1. Busca todos os talhões da atividade específica.
    // Esta consulta é segura e apenas lê dados.
    final List<Map<String, dynamic>> todosOsTalhoes = await db.rawQuery('''
      SELECT T.id FROM talhoes T
      INNER JOIN fazendas F ON T.fazendaId = F.id AND T.fazendaAtividadeId = F.atividadeId
      WHERE F.atividadeId = ?
    ''', [atividadeId]);

    if (todosOsTalhoes.isEmpty) {
      return 0; // Nenhum talhão na atividade, nada a fazer.
    }

    final List<int> idsParaRemover = [];

    // 2. Itera sobre cada talhão para verificar se ele tem parcelas.
    for (final talhaoMap in todosOsTalhoes) {
      final talhaoId = talhaoMap['id'] as int;
      
      // Usa uma consulta COUNT, que é muito eficiente para verificar a existência de registros.
      final resultado = await db.rawQuery(
        'SELECT COUNT(*) as total FROM parcelas WHERE talhaoId = ?',
        [talhaoId],
      );

      final contagem = Sqflite.firstIntValue(resultado) ?? 0;
      
      // 3. Se a contagem de parcelas for zero, marca o talhão para remoção.
      if (contagem == 0) {
        idsParaRemover.add(talhaoId);
      }
    }

    // 4. Se houver talhões para remover, executa a exclusão em lote.
    // Este comando DELETE é padrão e seguro.
    if (idsParaRemover.isNotEmpty) {
      await db.delete(
        'talhoes',
        where: 'id IN (${List.filled(idsParaRemover.length, '?').join(',')})',
        whereArgs: idsParaRemover,
      );
      talhoesRemovidos = idsParaRemover.length;
      debugPrint("$talhoesRemovidos talhões vazios foram removidos da atividade $atividadeId.");
    }
    
    return talhoesRemovidos;
  }
}
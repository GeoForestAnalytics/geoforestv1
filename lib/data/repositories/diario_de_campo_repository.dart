// Crie o arquivo: lib/data/repositories/diario_de_campo_repository.dart

import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:sqflite/sqflite.dart';

class DiarioDeCampoRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // Salva um novo diário ou atualiza um existente se a chave única (data, lider, talhao) for a mesma.
  Future<void> insertOrUpdateDiario(DiarioDeCampo diario) async {
    final db = await _dbHelper.database;
    await db.insert(
      'diario_de_campo',
      diario.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace, // Isso faz o "update" caso já exista
    );
  }

  // Busca um diário específico para pré-preencher o formulário
  Future<DiarioDeCampo?> getDiario(String data, String lider, int talhaoId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'diario_de_campo',
      where: 'data_relatorio = ? AND nome_lider = ? AND talhao_id = ?',
      whereArgs: [data, lider, talhaoId],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return DiarioDeCampo.fromMap(maps.first);
    }
    return null;
  }
}
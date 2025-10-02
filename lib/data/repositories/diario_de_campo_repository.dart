// lib/data/repositories/diario_de_campo_repository.dart (VERSÃO REFATORADA)

import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:sqflite/sqflite.dart';

class DiarioDeCampoRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> insertOrUpdateDiario(DiarioDeCampo diario) async {
    final db = await _dbHelper.database;
    await db.insert(
      DbDiarioDeCampo.tableName,
      diario.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DiarioDeCampo?> getDiario(String data, String lider) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbDiarioDeCampo.tableName,
      where: '${DbDiarioDeCampo.dataRelatorio} = ? AND ${DbDiarioDeCampo.nomeLider} = ?',
      whereArgs: [data, lider],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return DiarioDeCampo.fromMap(maps.first);
    }
    return null;
  }
}
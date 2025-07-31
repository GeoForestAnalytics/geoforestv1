// lib/data/repositories/sortimento_repository.dart

import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/sortimento_model.dart';
import 'package:sqflite/sqflite.dart';

class SortimentoRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// Insere um novo sortimento no banco de dados.
  /// Se um sortimento com o mesmo ID já existir, ele será substituído.
  Future<int> insertSortimento(SortimentoModel s) async {
    final db = await _dbHelper.database;
    return await db.insert('sortimentos', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Retorna uma lista com todos os sortimentos cadastrados, ordenados por nome.
  Future<List<SortimentoModel>> getTodosSortimentos() async {
    final db = await _dbHelper.database;
    final maps = await db.query('sortimentos', orderBy: 'nome ASC');
    if (maps.isEmpty) {
      return [];
    }
    return List.generate(maps.length, (i) => SortimentoModel.fromMap(maps[i]));
  }

  /// Deleta um sortimento do banco de dados com base no seu ID.
  Future<void> deleteSortimento(int id) async {
    final db = await _dbHelper.database;
    await db.delete('sortimentos', where: 'id = ?', whereArgs: [id]);
  }
}
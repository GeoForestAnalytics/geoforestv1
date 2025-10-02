// lib/data/repositories/sortimento_repository.dart (VERSÃO REFATORADA)

import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/models/sortimento_model.dart';
import 'package:sqflite/sqflite.dart';

class SortimentoRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> insertSortimento(SortimentoModel s) async {
    final db = await _dbHelper.database;
    return await db.insert(
      DbSortimentos.tableName,
      s.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SortimentoModel>> getTodosSortimentos() async {
    final db = await _dbHelper.database;
    final maps = await db.query(DbSortimentos.tableName, orderBy: '${DbSortimentos.nome} ASC');
    if (maps.isEmpty) {
      return [];
    }
    return List.generate(maps.length, (i) => SortimentoModel.fromMap(maps[i]));
  }

  Future<void> deleteSortimento(int id) async {
    final db = await _dbHelper.database;
    await db.delete(DbSortimentos.tableName, where: '${DbSortimentos.id} = ?', whereArgs: [id]);
  }
}
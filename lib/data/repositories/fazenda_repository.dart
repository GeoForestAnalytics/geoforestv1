// lib/data/repositories/fazenda_repository.dart (VERSÃO REFATORADA)

import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:sqflite/sqflite.dart';

class FazendaRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> insertFazenda(Fazenda f) async {
    final db = await _dbHelper.database;
    final map = f.toMap();
    map[DbFazendas.lastModified] = DateTime.now().toIso8601String();
    await db.insert(DbFazendas.tableName, map, conflictAlgorithm: ConflictAlgorithm.fail);
  }

  Future<int> updateFazenda(Fazenda f) async {
    final db = await _dbHelper.database;
    final map = f.toMap();
    map[DbFazendas.lastModified] = DateTime.now().toIso8601String();
    return await db.update(
      DbFazendas.tableName, 
      map, 
      where: '${DbFazendas.id} = ? AND ${DbFazendas.atividadeId} = ?', 
      whereArgs: [f.id, f.atividadeId]
    );
  }

  Future<List<Fazenda>> getFazendasDaAtividade(int atividadeId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbFazendas.tableName,
      where: '${DbFazendas.atividadeId} = ?',
      whereArgs: [atividadeId],
      orderBy: DbFazendas.nome,
    );
    return List.generate(maps.length, (i) => Fazenda.fromMap(maps[i]));
  }

  Future<void> deleteFazenda(String id, int atividadeId) async {
    final db = await _dbHelper.database;
    await db.delete(
      DbFazendas.tableName,
      where: '${DbFazendas.id} = ? AND ${DbFazendas.atividadeId} = ?',
      whereArgs: [id, atividadeId],
    );
  }
}
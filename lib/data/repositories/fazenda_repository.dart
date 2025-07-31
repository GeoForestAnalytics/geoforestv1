// lib/data/repositories/fazenda_repository.dart
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:sqflite/sqflite.dart';

class FazendaRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> insertFazenda(Fazenda f) async {
    final db = await _dbHelper.database;
    await db.insert('fazendas', f.toMap(), conflictAlgorithm: ConflictAlgorithm.fail);
  }

  Future<List<Fazenda>> getFazendasDaAtividade(int atividadeId) async {
    final db = await _dbHelper.database;
    final maps = await db.query('fazendas', where: 'atividadeId = ?', whereArgs: [atividadeId], orderBy: 'nome');
    return List.generate(maps.length, (i) => Fazenda.fromMap(maps[i]));
  }

  Future<void> deleteFazenda(String id, int atividadeId) async {
    final db = await _dbHelper.database;
    await db.delete('fazendas', where: 'id = ? AND atividadeId = ?', whereArgs: [id, atividadeId]);
  }
}
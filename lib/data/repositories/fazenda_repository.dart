// lib/data/repositories/fazenda_repository.dart

import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:sqflite/sqflite.dart';

class FazendaRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> insertFazenda(Fazenda f) async {
    final db = await _dbHelper.database;
    final map = f.toMap();
    // <<< ADICIONA O CARIMBO DE TEMPO ANTES DE INSERIR >>>
    map['lastModified'] = DateTime.now().toIso8601String();
    await db.insert('fazendas', map, conflictAlgorithm: ConflictAlgorithm.fail);
  }

  Future<int> updateFazenda(Fazenda f) async {
    final db = await _dbHelper.database;
    final map = f.toMap();
    // <<< ADICIONA O CARIMBO DE TEMPO ANTES DE ATUALIZAR >>>
    map['lastModified'] = DateTime.now().toIso8601String();
    return await db.update(
      'fazendas', 
      map, 
      where: 'id = ? AND atividadeId = ?', 
      whereArgs: [f.id, f.atividadeId]
    );
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
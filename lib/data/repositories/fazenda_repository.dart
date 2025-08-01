// lib/data/repositories/fazenda_repository.dart (VERSÃO CORRIGIDA)

import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:sqflite/sqflite.dart';

class FazendaRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<void> insertFazenda(Fazenda f) async {
    final db = await _dbHelper.database;
    await db.insert('fazendas', f.toMap(), conflictAlgorithm: ConflictAlgorithm.fail);
  }

  // <<< NOVO MÉTODO DE UPDATE >>>
  Future<int> updateFazenda(Fazenda f) async {
    final db = await _dbHelper.database;
    // A chave primária da tabela 'fazendas' é composta (id, atividadeId).
    // Por isso, a cláusula WHERE precisa usar ambos os campos para identificar a linha correta.
    return await db.update(
      'fazendas', 
      f.toMap(), 
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
// lib/data/repositories/projeto_repository.dart (VERSÃO ATUALIZADA)

import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:sqflite/sqflite.dart'; 

class ProjetoRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> insertProjeto(Projeto p) async {
    final db = await _dbHelper.database;
    final map = p.toMap();
    map[DbProjetos.lastModified] = DateTime.now().toIso8601String();
    return await db.insert(DbProjetos.tableName, map, conflictAlgorithm: ConflictAlgorithm.fail);
  }
  
  Future<int> updateProjeto(Projeto p) async {
    final db = await _dbHelper.database;
    final map = p.toMap();
    map[DbProjetos.lastModified] = DateTime.now().toIso8601String();
    return await db.update(
      DbProjetos.tableName,
      map,
      where: '${DbProjetos.id} = ?',
      whereArgs: [p.id],
    );
  }

  Future<List<Projeto>> getTodosProjetos(String licenseId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbProjetos.tableName,
      where: '${DbProjetos.status} = ? AND ${DbProjetos.licenseId} = ?',
      whereArgs: ['ativo', licenseId],
      orderBy: '${DbProjetos.dataCriacao} DESC',
    );
    return List.generate(maps.length, (i) => Projeto.fromMap(maps[i]));
  }

  // <<< MÉTODO CORRIGIDO >>>
  Future<List<Projeto>> getTodosOsProjetosParaGerente() async {
    final db = await _dbHelper.database;
    // Adiciona o filtro para buscar apenas projetos com status 'ativo'
    final maps = await db.query(
      DbProjetos.tableName,
      where: '${DbProjetos.status} = ?',
      whereArgs: ['ativo'],
      orderBy: '${DbProjetos.dataCriacao} DESC',
    );
    return List.generate(maps.length, (i) => Projeto.fromMap(maps[i]));
  }

  Future<Projeto?> getProjetoById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(DbProjetos.tableName, where: '${DbProjetos.id} = ?', whereArgs: [id]);
    if (maps.isNotEmpty) return Projeto.fromMap(maps.first);
    return null;
  }

  Future<void> deleteProjeto(int id) async {
    final db = await _dbHelper.database;
    await db.delete(DbProjetos.tableName, where: '${DbProjetos.id} = ?', whereArgs: [id]);
  }

  Future<Projeto?> getProjetoPelaAtividade(int atividadeId) async {
    final db = await _dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT P.* FROM ${DbProjetos.tableName} P
      JOIN ${DbAtividades.tableName} A ON P.${DbProjetos.id} = A.${DbAtividades.projetoId}
      WHERE A.${DbAtividades.id} = ?
    ''', [atividadeId]);
    if (maps.isNotEmpty) return Projeto.fromMap(maps.first);
    return null;
  }

  Future<Projeto?> getProjetoPelaCubagem(CubagemArvore cubagem) async {
    if (cubagem.talhaoId == null) return null;
    final db = await _dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT P.* FROM ${DbProjetos.tableName} P
      JOIN ${DbAtividades.tableName} A ON P.${DbProjetos.id} = A.${DbAtividades.projetoId}
      JOIN ${DbFazendas.tableName} F ON A.${DbAtividades.id} = F.${DbFazendas.atividadeId}
      JOIN ${DbTalhoes.tableName} T ON F.${DbFazendas.id} = T.${DbTalhoes.fazendaId} AND F.${DbFazendas.atividadeId} = T.${DbTalhoes.fazendaAtividadeId}
      WHERE T.${DbTalhoes.id} = ?
    ''', [cubagem.talhaoId]);
    if (maps.isNotEmpty) return Projeto.fromMap(maps.first);
    return null;
  }

  Future<Projeto?> getProjetoPelaParcela(Parcela parcela) async {
    if (parcela.talhaoId == null) return null;
    final db = await _dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT P.* FROM ${DbProjetos.tableName} P
      JOIN ${DbAtividades.tableName} A ON P.${DbProjetos.id} = A.${DbAtividades.projetoId}
      JOIN ${DbFazendas.tableName} F ON A.${DbAtividades.id} = F.${DbFazendas.atividadeId}
      JOIN ${DbTalhoes.tableName} T ON F.${DbFazendas.id} = T.${DbTalhoes.fazendaId} AND F.${DbFazendas.atividadeId} = T.${DbTalhoes.fazendaAtividadeId}
      WHERE T.${DbTalhoes.id} = ?
    ''', [parcela.talhaoId]);
    if (maps.isNotEmpty) return Projeto.fromMap(maps.first);
    return null;
  }
}
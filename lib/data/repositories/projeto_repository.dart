// lib/data/repositories/projeto_repository.dart (VERSÃO FINAL E LIMPA)

import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:sqflite/sqflite.dart'; 

class ProjetoRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // AJUSTE 1: Insert agora apenas insere.
  Future<int> insertProjeto(Projeto p) async {
    final db = await _dbHelper.database;
    return await db.insert('projetos', p.toMap(), conflictAlgorithm: ConflictAlgorithm.fail);
  }

  

  Future<List<Projeto>> getTodosProjetos(String licenseId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'projetos',
      where: 'status = ? AND licenseId = ?',
      whereArgs: ['ativo', licenseId],
      orderBy: 'dataCriacao DESC',
    );
    return List.generate(maps.length, (i) => Projeto.fromMap(maps[i]));
  }

  Future<List<Projeto>> getTodosOsProjetosParaGerente() async {
    final db = await _dbHelper.database;
    final maps = await db.query('projetos', orderBy: 'dataCriacao DESC');
    return List.generate(maps.length, (i) => Projeto.fromMap(maps[i]));
  }

  Future<Projeto?> getProjetoById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query('projetos', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) return Projeto.fromMap(maps.first);
    return null;
  }

  Future<void> deleteProjeto(int id) async {
    final db = await _dbHelper.database;
    await db.delete('projetos', where: 'id = ?', whereArgs: [id]);
  }

  Future<Projeto?> getProjetoPelaAtividade(int atividadeId) async {
    final db = await _dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT P.* FROM projetos P
      JOIN atividades A ON P.id = A.projetoId
      WHERE A.id = ?
    ''', [atividadeId]);
    if (maps.isNotEmpty) return Projeto.fromMap(maps.first);
    return null;
  }

  Future<Projeto?> getProjetoPelaCubagem(CubagemArvore cubagem) async {
    if (cubagem.talhaoId == null) return null;
    final db = await _dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT P.* FROM projetos P
      JOIN atividades A ON P.id = A.projetoId
      JOIN fazendas F ON A.id = F.atividadeId
      JOIN talhoes T ON F.id = T.fazendaId AND F.atividadeId = T.fazendaAtividadeId
      WHERE T.id = ?
    ''', [cubagem.talhaoId]);
    if (maps.isNotEmpty) return Projeto.fromMap(maps.first);
    return null;
  }

  Future<Projeto?> getProjetoPelaParcela(Parcela parcela) async {
    if (parcela.talhaoId == null) return null;
    final db = await _dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT P.* FROM projetos P
      JOIN atividades A ON P.id = A.projetoId
      JOIN fazendas F ON A.id = F.atividadeId
      JOIN talhoes T ON F.id = T.fazendaId AND F.atividadeId = T.fazendaAtividadeId
      WHERE T.id = ?
    ''', [parcela.talhaoId]);
    if (maps.isNotEmpty) return Projeto.fromMap(maps.first);
    return null;
  }

   Future<int> updateProjeto(Projeto p) async {
    final db = await _dbHelper.database;
    return await db.update(
      'projetos',
      p.toMap(),
      where: 'id = ?',
      whereArgs: [p.id],
    );
  }
}

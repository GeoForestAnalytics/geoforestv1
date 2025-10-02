// lib/data/repositories/atividade_repository.dart (VERSÃO REFATORADA)

import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:sqflite/sqflite.dart';

class AtividadeRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> insertAtividade(Atividade a) async {
    final db = await _dbHelper.database;
    final map = a.toMap();
    map[DbAtividades.lastModified] = DateTime.now().toIso8601String();
    return await db.insert(DbAtividades.tableName, map, conflictAlgorithm: ConflictAlgorithm.fail);
  }

  Future<int> updateAtividade(Atividade a) async {
    final db = await _dbHelper.database;
    final map = a.toMap();
    map[DbAtividades.lastModified] = DateTime.now().toIso8601String();
    return await db.update(DbAtividades.tableName, map, where: '${DbAtividades.id} = ?', whereArgs: [a.id]);
  }

  Future<List<Atividade>> getAtividadesDoProjeto(int projetoId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbAtividades.tableName,
      where: '${DbAtividades.projetoId} = ?',
      whereArgs: [projetoId],
      orderBy: '${DbAtividades.dataCriacao} DESC',
    );
    return List.generate(maps.length, (i) => Atividade.fromMap(maps[i]));
  }

  Future<List<Atividade>> getTodasAsAtividades() async {
    final db = await _dbHelper.database;
    final maps = await db.query(DbAtividades.tableName, orderBy: '${DbAtividades.dataCriacao} DESC');
    return List.generate(maps.length, (i) => Atividade.fromMap(maps[i]));
  }

  Future<Atividade?> getAtividadeById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbAtividades.tableName,
      where: '${DbAtividades.id} = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Atividade.fromMap(maps.first);
    }
    return null;
  }

  Future<void> deleteAtividade(int id) async {
    final db = await _dbHelper.database;
    await db.delete(DbAtividades.tableName, where: '${DbAtividades.id} = ?', whereArgs: [id]);
  }

  Future<void> criarAtividadeComPlanoDeCubagem(Atividade novaAtividade, List<CubagemArvore> placeholders) async {
    if (placeholders.isEmpty) {
      throw Exception("A lista de árvores para cubagem (placeholders) não pode estar vazia.");
    }
    final db = await _dbHelper.database;

    await db.transaction((txn) async {
      final atividadeMap = novaAtividade.toMap();
      atividadeMap[DbAtividades.lastModified] = DateTime.now().toIso8601String();
      
      final atividadeId = await txn.insert(DbAtividades.tableName, atividadeMap);
      
      final firstPlaceholder = placeholders.first;
      final fazendaDoPlano = Fazenda(
        id: firstPlaceholder.idFazenda!,
        atividadeId: atividadeId,
        nome: firstPlaceholder.nomeFazenda,
        municipio: 'N/I',
        estado: 'N/I',
      );
      
      final fazendaMap = fazendaDoPlano.toMap();
      fazendaMap[DbFazendas.lastModified] = DateTime.now().toIso8601String();
      await txn.insert(DbFazendas.tableName, fazendaMap, conflictAlgorithm: ConflictAlgorithm.replace);
      
      final talhaoOriginal = await txn.query(
        DbTalhoes.tableName,
        where: '${DbTalhoes.nome} = ? AND ${DbTalhoes.fazendaId} = ?',
        whereArgs: [firstPlaceholder.nomeTalhao, firstPlaceholder.idFazenda],
        limit: 1,
      ).then((maps) => maps.isNotEmpty ? Talhao.fromMap(maps.first) : null);
      
      final talhaoDoPlano = Talhao(
        fazendaId: fazendaDoPlano.id,
        fazendaAtividadeId: atividadeId,
        nome: firstPlaceholder.nomeTalhao,
        areaHa: talhaoOriginal?.areaHa,
        especie: talhaoOriginal?.especie,
        espacamento: talhaoOriginal?.espacamento,
        idadeAnos: talhaoOriginal?.idadeAnos,
        bloco: talhaoOriginal?.bloco,
        up: talhaoOriginal?.up,
        materialGenetico: talhaoOriginal?.materialGenetico,
        dataPlantio: talhaoOriginal?.dataPlantio,
      );

      final talhaoMap = talhaoDoPlano.toMap();
      talhaoMap[DbTalhoes.lastModified] = DateTime.now().toIso8601String();
      final talhaoId = await txn.insert(DbTalhoes.tableName, talhaoMap);

      for (final placeholder in placeholders) {
        final map = placeholder.toMap();
        map[DbCubagensArvores.talhaoId] = talhaoId;
        map.remove(DbCubagensArvores.id);
        map[DbCubagensArvores.lastModified] = DateTime.now().toIso8601String();
        await txn.insert(DbCubagensArvores.tableName, map);
      }
    });
    debugPrint('Atividade de cubagem e ${placeholders.length} placeholders criados com sucesso!');
  }
}
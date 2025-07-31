// lib/data/repositories/atividade_repository.dart
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:sqflite/sqflite.dart';

class AtividadeRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> insertAtividade(Atividade a) async {
  final db = await _dbHelper.database;
  // Adiciona o ConflictAlgorithm.replace para que ele funcione como um "upsert" (update or insert)
  return await db.insert('atividades', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
}

  Future<List<Atividade>> getAtividadesDoProjeto(int projetoId) async {
    final db = await _dbHelper.database;
    final maps = await db.query('atividades', where: 'projetoId = ?', whereArgs: [projetoId], orderBy: 'dataCriacao DESC');
    return List.generate(maps.length, (i) => Atividade.fromMap(maps[i]));
  }

  Future<List<Atividade>> getTodasAsAtividades() async {
    final db = await _dbHelper.database;
    final maps = await db.query('atividades', orderBy: 'dataCriacao DESC');
    return List.generate(maps.length, (i) => Atividade.fromMap(maps[i]));
  }

  Future<void> deleteAtividade(int id) async {
    final db = await _dbHelper.database;
    await db.delete('atividades', where: 'id = ?', whereArgs: [id]);
  }
  
  Future<void> criarAtividadeComPlanoDeCubagem(Atividade novaAtividade, List<CubagemArvore> placeholders) async {
    if (placeholders.isEmpty) {
      throw Exception("A lista de árvores para cubagem (placeholders) não pode estar vazia.");
    }
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final atividadeId = await txn.insert('atividades', novaAtividade.toMap());
      final firstPlaceholder = placeholders.first;
      final fazendaDoPlano = Fazenda(id: firstPlaceholder.idFazenda!, atividadeId: atividadeId, nome: firstPlaceholder.nomeFazenda, municipio: 'N/I', estado: 'N/I');
      await txn.insert('fazendas', fazendaDoPlano.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      final talhaoDoPlano = Talhao(fazendaId: fazendaDoPlano.id, fazendaAtividadeId: fazendaDoPlano.atividadeId, nome: firstPlaceholder.nomeTalhao);
      final talhaoId = await txn.insert('talhoes', talhaoDoPlano.toMap());
      for (final placeholder in placeholders) {
        final map = placeholder.toMap();
        map['talhaoId'] = talhaoId;
        map.remove('id');
        await txn.insert('cubagens_arvores', map);
      }
    });
    debugPrint('Atividade de cubagem e ${placeholders.length} placeholders criados com sucesso!');
  }
}
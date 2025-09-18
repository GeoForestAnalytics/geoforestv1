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
    final map = a.toMap();
    // <<< ADICIONA O CARIMBO DE TEMPO ANTES DE INSERIR >>>
    map['lastModified'] = DateTime.now().toIso8601String();
    return await db.insert('atividades', map, conflictAlgorithm: ConflictAlgorithm.fail);
  }

  Future<int> updateAtividade(Atividade a) async {
    final db = await _dbHelper.database;
    final map = a.toMap();
    // <<< ADICIONA O CARIMBO DE TEMPO ANTES DE ATUALIZAR >>>
    map['lastModified'] = DateTime.now().toIso8601String();
    return await db.update('atividades', map, where: 'id = ?', whereArgs: [a.id]);
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

  Future<Atividade?> getAtividadeById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'atividades',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Atividade.fromMap(maps.first);
    }
    return null;
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
    final atividadeMap = novaAtividade.toMap();
    atividadeMap['lastModified'] = DateTime.now().toIso8601String();
    
    final atividadeId = await txn.insert('atividades', atividadeMap);
    
    final firstPlaceholder = placeholders.first;
    final fazendaDoPlano = Fazenda(
      id: firstPlaceholder.idFazenda!, 
      atividadeId: atividadeId, 
      nome: firstPlaceholder.nomeFazenda, 
      municipio: 'N/I', 
      estado: 'N/I'
    );
    
    final fazendaMap = fazendaDoPlano.toMap();
    fazendaMap['lastModified'] = DateTime.now().toIso8601String();
    await txn.insert('fazendas', fazendaMap, conflictAlgorithm: ConflictAlgorithm.replace);
    
    // <<< INÍCIO DA MELHORIA >>>
    // 1. Busca o talhão original (da atividade de inventário) para obter todos os seus dados.
    // Usamos o nome e o ID da fazenda (da atividade original) para encontrá-lo.
    final talhaoOriginal = await txn.query(
      'talhoes', 
      where: 'nome = ? AND fazendaId = ?', 
      whereArgs: [firstPlaceholder.nomeTalhao, firstPlaceholder.idFazenda],
      limit: 1
    ).then((maps) => maps.isNotEmpty ? Talhao.fromMap(maps.first) : null);
    
    // 2. Cria o novo talhão para a atividade de cubagem,
    // copiando os dados do talhão original.
    final talhaoDoPlano = Talhao(
      fazendaId: fazendaDoPlano.id, 
      fazendaAtividadeId: atividadeId, // USA O ID DA NOVA ATIVIDADE
      nome: firstPlaceholder.nomeTalhao,
      // Copia os dados do talhão original, se ele foi encontrado
      areaHa: talhaoOriginal?.areaHa,
      especie: talhaoOriginal?.especie,
      espacamento: talhaoOriginal?.espacamento,
      idadeAnos: talhaoOriginal?.idadeAnos,
      bloco: talhaoOriginal?.bloco,
      up: talhaoOriginal?.up,
      materialGenetico: talhaoOriginal?.materialGenetico,
      dataPlantio: talhaoOriginal?.dataPlantio,
    );
    // <<< FIM DA MELHORIA >>>

    final talhaoMap = talhaoDoPlano.toMap();
    talhaoMap['lastModified'] = DateTime.now().toIso8601String();
    final talhaoId = await txn.insert('talhoes', talhaoMap);

    for (final placeholder in placeholders) {
      final map = placeholder.toMap();
      map['talhaoId'] = talhaoId; // Vincula ao NOVO talhão de cubagem
      map.remove('id');
      map['lastModified'] = DateTime.now().toIso8601String();
      await txn.insert('cubagens_arvores', map);
    }
  });
  debugPrint('Atividade de cubagem e ${placeholders.length} placeholders criados com sucesso!');
}
}
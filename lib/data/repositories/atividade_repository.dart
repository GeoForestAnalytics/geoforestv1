// lib/data/repositories/atividade_repository.dart (VERSÃO COMPLETA E AJUSTADA)

import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:sqflite/sqflite.dart';
import 'package:collection/collection.dart'; // Import necessário para o groupBy

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

  /// ✅ FUNÇÃO ANTIGA (mantida para compatibilidade, mas não será usada neste fluxo)
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

  /// ✅ NOVA FUNÇÃO: Cria uma única atividade e, dentro dela, a hierarquia de fazendas e talhões com seus planos.
  Future<void> criarAtividadeUnicaComMultiplosPlanos(Atividade novaAtividade, Map<Talhao, List<CubagemArvore>> planosPorTalhao) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      // 1. Cria a atividade "mãe" única para a cubagem
      final atividadeMap = novaAtividade.toMap();
      atividadeMap[DbAtividades.lastModified] = now;
      final newAtividadeId = await txn.insert(DbAtividades.tableName, atividadeMap);
      
      // 2. Agrupa os talhões por sua fazenda de origem
      final talhoesAgrupadosPorFazenda = groupBy(planosPorTalhao.keys, (Talhao t) => t.fazendaId);
      
      // 3. Itera sobre cada fazenda para recriar a hierarquia
      for (var fazendaIdOrigem in talhoesAgrupadosPorFazenda.keys) {
        final talhoesDestaFazenda = talhoesAgrupadosPorFazenda[fazendaIdOrigem]!;
        final primeiroTalhao = talhoesDestaFazenda.first;

        // 4. Cria a Fazenda correspondente dentro da nova atividade
        final novaFazenda = Fazenda(
          id: primeiroTalhao.fazendaId,
          atividadeId: newAtividadeId,
          nome: primeiroTalhao.fazendaNome ?? 'Fazenda Desconhecida',
          municipio: primeiroTalhao.municipio ?? 'N/I',
          estado: primeiroTalhao.estado ?? 'N/I',
        );
        final fazendaMap = novaFazenda.toMap();
        fazendaMap[DbFazendas.lastModified] = now;
        await txn.insert(DbFazendas.tableName, fazendaMap, conflictAlgorithm: ConflictAlgorithm.replace);

        // 5. Itera sobre cada talhão desta fazenda para criar os planos
        for (final talhaoOriginal in talhoesDestaFazenda) {
          final placeholders = planosPorTalhao[talhaoOriginal]!;
          if (placeholders.isEmpty) continue;

          // 6. Cria o Talhão correspondente dentro da nova fazenda/atividade
          final novoTalhao = Talhao(
            fazendaId: novaFazenda.id,
            fazendaAtividadeId: newAtividadeId,
            nome: talhaoOriginal.nome,
            projetoId: novaAtividade.projetoId,
            // Copia os outros dados do talhão original
            areaHa: talhaoOriginal.areaHa,
            especie: talhaoOriginal.especie,
            espacamento: talhaoOriginal.espacamento,
            idadeAnos: talhaoOriginal.idadeAnos,
            bloco: talhaoOriginal.bloco,
            up: talhaoOriginal.up,
            materialGenetico: talhaoOriginal.materialGenetico,
            dataPlantio: talhaoOriginal.dataPlantio,
          );

          final talhaoMap = novoTalhao.toMap();
          talhaoMap[DbTalhoes.lastModified] = now;
          final newTalhaoId = await txn.insert(DbTalhoes.tableName, talhaoMap);

          // 7. Insere os placeholders (árvores de cubagem) vinculados ao novo talhão
          for (final placeholder in placeholders) {
            final map = placeholder.toMap();
            map[DbCubagensArvores.talhaoId] = newTalhaoId;
            map.remove(DbCubagensArvores.id);
            map[DbCubagensArvores.lastModified] = now;
            await txn.insert(DbCubagensArvores.tableName, map);
          }
        }
      }
    });
    debugPrint("Atividade de cubagem única criada com sucesso com múltiplos planos.");
  }
}
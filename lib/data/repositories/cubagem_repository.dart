// lib/data/repositories/cubagem_repository.dart (VERSÃO REFATORADA)

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/data/repositories/analise_repository.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/cubagem_secao_model.dart';
import 'package:geoforestv1/models/enums.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/services/analysis_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';

class CubagemRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final AnaliseRepository _analiseRepository = AnaliseRepository();

  Future<void> limparTodasAsCubagens() async {
    final db = await _dbHelper.database;
    await db.delete(DbCubagensArvores.tableName);
    debugPrint('Tabela de cubagens e seções limpa.');
  }

  Future<void> salvarCubagemCompleta(
      CubagemArvore arvore, List<CubagemSecao> secoes) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final nowAsString = now.toIso8601String();

    await db.transaction((txn) async {
      int id;

      final arvoreParaSalvar = arvore.copyWith(
        isSynced: false,
        // Garante que a dataColeta seja salva. Se vier nula (não deveria), usa 'now'.
        dataColeta: arvore.dataColeta ?? now,
      );

      final map = arvoreParaSalvar.toMap();
      map[DbCubagensArvores.lastModified] = nowAsString;

      final prefs = await SharedPreferences.getInstance();
      String? nomeDoResponsavel = prefs.getString('nome_lider');
      if (nomeDoResponsavel == null || nomeDoResponsavel.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          nomeDoResponsavel = user.displayName ?? user.email;
        }
      }
      if (nomeDoResponsavel != null) {
        map[DbCubagensArvores.nomeLider] = nomeDoResponsavel;
      }

      if (arvoreParaSalvar.id == null) {
        id = await txn.insert(DbCubagensArvores.tableName, map,
            conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        id = arvoreParaSalvar.id!;
        await txn.update(DbCubagensArvores.tableName, map,
            where: '${DbCubagensArvores.id} = ?', whereArgs: [id]);
      }
      await txn.delete(DbCubagensSecoes.tableName, where: '${DbCubagensSecoes.cubagemArvoreId} = ?', whereArgs: [id]);
      for (var s in secoes) {
        s.cubagemArvoreId = id;
        final secaoMap = s.toMap();
        secaoMap[DbCubagensSecoes.lastModified] = nowAsString;
        await txn.insert(DbCubagensSecoes.tableName, secaoMap);
      }
    });
  }

  Future<void> gerarPlanoDeCubagemNoBanco(Talhao talhao, int totalParaCubar,
      int novaAtividadeId, AnalysisService analysisService) async {
    final dadosAgregados =
        await _analiseRepository.getDadosAgregadosDoTalhao(talhao.id!);

    final parcelas = dadosAgregados['parcelas'] as List<Parcela>;
    final arvores = dadosAgregados['arvores'] as List<Arvore>;
    if (parcelas.isEmpty || arvores.isEmpty) {
      throw Exception('Não há árvores suficientes neste talhão para gerar um plano.');
    }

    final analise = analysisService.getTalhaoInsights(talhao, parcelas, arvores);

    final plano = analysisService.gerarPlanoDeCubagem(
      distribuicaoAmostrada: analise.distribuicaoDiametrica,
      totalArvoresAmostradas: analise.totalArvoresAmostradas,
      totalArvoresParaCubar: totalParaCubar,
      metrica: MetricaDistribuicao.dap,
    );

    if (plano.isEmpty) {
      throw Exception(
          'Não foi possível gerar o plano de cubagem. Verifique os dados das parcelas.');
    }

    final db = await _dbHelper.database;
    final now = DateTime.now();
    final nowAsString = now.toIso8601String();

    await db.transaction((txn) async {
      for (final entry in plano.entries) {
        final classe = entry.key;
        final quantidade = entry.value;
        for (int i = 1; i <= quantidade; i++) {
          final arvoreCubagem = CubagemArvore(
            talhaoId: talhao.id!,
            idFazenda: talhao.fazendaId,
            nomeFazenda: talhao.fazendaNome ?? 'N/A',
            nomeTalhao: talhao.nome,
            identificador: '${talhao.nome} - Árvore ${i.toString().padLeft(2, '0')}',
            classe: classe,
            isSynced: false,
            dataColeta: now,
          );

          final map = arvoreCubagem.toMap();
          map[DbCubagensArvores.lastModified] = nowAsString;
          await txn.insert(DbCubagensArvores.tableName, map);
        }
      }
    });
  }

  Future<List<CubagemArvore>> getTodasCubagensDoTalhao(int talhaoId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(DbCubagensArvores.tableName,
        where: '${DbCubagensArvores.talhaoId} = ?', whereArgs: [talhaoId], orderBy: '${DbCubagensArvores.id} ASC');
    return List.generate(maps.length, (i) => CubagemArvore.fromMap(maps[i]));
  }

  Future<List<CubagemArvore>> getCubagensDoDiaPorEquipe({
    required String nomeLider,
    required DateTime dataSelecionada,
    required int talhaoId,
  }) async {
    final db = await _dbHelper.database;

    // Formata a data para YYYY-MM-DD para comparar com a função DATE do SQL
    final dataFormatadaParaQuery = DateFormat('yyyy-MM-dd').format(dataSelecionada);

    // A query verifica se a parte da DATA do campo dataColeta (que é ISO8601 com hora) bate com a data selecionada
    String whereClause = '${DbCubagensArvores.nomeLider} = ? AND ${DbCubagensArvores.talhaoId} = ? AND DATE(${DbCubagensArvores.dataColeta}) = ?';
    List<dynamic> whereArgs = [nomeLider, talhaoId, dataFormatadaParaQuery];

    final List<Map<String, dynamic>> maps = await db.query(
      DbCubagensArvores.tableName,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: '${DbCubagensArvores.lastModified} DESC',
    );

    if (maps.isNotEmpty) {
      return List.generate(maps.length, (i) => CubagemArvore.fromMap(maps[i]));
    }
    return [];
  }

  Future<List<CubagemArvore>> getTodasCubagens() async {
    final db = await _dbHelper.database;
    final maps = await db.query(DbCubagensArvores.tableName, orderBy: '${DbCubagensArvores.id} DESC');
    return List.generate(maps.length, (i) => CubagemArvore.fromMap(maps[i]));
  }

  Future<List<CubagemSecao>> getSecoesPorArvoreId(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(DbCubagensSecoes.tableName,
        where: '${DbCubagensSecoes.cubagemArvoreId} = ?',
        whereArgs: [id],
        orderBy: '${DbCubagensSecoes.alturaMedicao} ASC');
    return List.generate(maps.length, (i) => CubagemSecao.fromMap(maps[i]));
  }

  Future<void> deletarCubagem(int id) async {
    final db = await _dbHelper.database;
    await db.delete(DbCubagensArvores.tableName, where: '${DbCubagensArvores.id} = ?', whereArgs: [id]);
  }

  Future<void> deletarMultiplasCubagens(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.delete(DbCubagensArvores.tableName,
        where: '${DbCubagensArvores.id} IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids);
  }

  Future<List<CubagemArvore>> getUnsyncedCubagens() async {
    final db = await _dbHelper.database;
    final maps =
        await db.query(DbCubagensArvores.tableName, where: '${DbCubagensArvores.isSynced} = ?', whereArgs: [0]);
    return List.generate(maps.length, (i) => CubagemArvore.fromMap(maps[i]));
  }

  Future<CubagemArvore?> getOneUnsyncedCubagem() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbCubagensArvores.tableName,
      where: '${DbCubagensArvores.isSynced} = ?',
      whereArgs: [0],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return CubagemArvore.fromMap(maps.first);
    }
    return null;
  }

  Future<List<CubagemArvore>> getUnexportedCubagens() async {
    final db = await _dbHelper.database;
    final maps =
        await db.query(DbCubagensArvores.tableName, where: '${DbCubagensArvores.exportada} = ?', whereArgs: [0]);
    return List.generate(maps.length, (i) => CubagemArvore.fromMap(maps[i]));
  }

  Future<List<CubagemArvore>> getTodasCubagensParaBackup() async {
    final db = await _dbHelper.database;
    final maps = await db.query(DbCubagensArvores.tableName);
    return List.generate(maps.length, (i) => CubagemArvore.fromMap(maps[i]));
  }

  Future<void> markCubagemAsSynced(int id) async {
    final db = await _dbHelper.database;
    await db.update(DbCubagensArvores.tableName, {DbCubagensArvores.isSynced: 1},
        where: '${DbCubagensArvores.id} = ?', whereArgs: [id]);
  }

  Future<void> marcarCubagensComoExportadas(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.update(DbCubagensArvores.tableName, {DbCubagensArvores.exportada: 1},
        where: '${DbCubagensArvores.id} IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids);
  }

  Future<List<CubagemArvore>> getPlanoDeCubagemPorAtividade(
      int atividadeId) async {
    final db = await _dbHelper.database;

    final List<Map<String, dynamic>> talhoesMaps = await db.query(
      DbTalhoes.tableName,
      columns: [DbTalhoes.id],
      where: '${DbTalhoes.fazendaAtividadeId} = ?',
      whereArgs: [atividadeId],
    );

    if (talhoesMaps.isEmpty) {
      return [];
    }

    final List<int> talhaoIds =
        talhoesMaps.map((map) => map[DbTalhoes.id] as int).toList();

    final List<Map<String, dynamic>> cubagensMaps = await db.query(
      DbCubagensArvores.tableName,
      where: '${DbCubagensArvores.talhaoId} IN (${List.filled(talhaoIds.length, '?').join(',')})',
      whereArgs: talhaoIds,
    );

    return List.generate(
        cubagensMaps.length, (i) => CubagemArvore.fromMap(cubagensMaps[i]));
  }

  Future<Set<String>> getDistinctLideres() async {
    final db = await _dbHelper.database;
    final maps = await db.query(DbCubagensArvores.tableName,
        distinct: true,
        columns: [DbCubagensArvores.nomeLider],
        where: '${DbCubagensArvores.nomeLider} IS NOT NULL AND ${DbCubagensArvores.nomeLider} != ? AND ${DbCubagensArvores.alturaTotal} > 0',
        whereArgs: ['']);
    return maps.map((map) => map[DbCubagensArvores.nomeLider] as String).toSet();
  }

  Future<List<CubagemArvore>> getConcludedCubagensFiltrado(
      {Set<int>? projetoIds, Set<String>? lideresNomes}) async {
    final db = await _dbHelper.database;

    String query = '''
      SELECT C.*, A.${DbAtividades.projetoId} FROM ${DbCubagensArvores.tableName} C
      INNER JOIN ${DbTalhoes.tableName} T ON C.${DbCubagensArvores.talhaoId} = T.${DbTalhoes.id}
      INNER JOIN ${DbAtividades.tableName} A ON T.${DbTalhoes.fazendaAtividadeId} = A.${DbAtividades.id}
      WHERE C.${DbCubagensArvores.alturaTotal} > 0
    ''';

    List<dynamic> whereArgs = [];

    if (projetoIds != null && projetoIds.isNotEmpty) {
      query +=
          ' AND A.${DbAtividades.projetoId} IN (${List.filled(projetoIds.length, '?').join(',')})';
      whereArgs.addAll(projetoIds);
    }
    if (lideresNomes != null && lideresNomes.isNotEmpty) {
      query +=
          ' AND C.${DbCubagensArvores.nomeLider} IN (${List.filled(lideresNomes.length, '?').join(',')})';
      whereArgs.addAll(lideresNomes);
    }

    final maps = await db.rawQuery(query, whereArgs);
    return List.generate(maps.length, (i) => CubagemArvore.fromMap(maps[i]));
  }
}
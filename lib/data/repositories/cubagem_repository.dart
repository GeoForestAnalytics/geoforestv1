// lib/data/repositories/cubagem_repository.dart (VERSÃO ATUALIZADA)
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/repositories/analise_repository.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/cubagem_secao_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/services/analysis_service.dart';
import 'package:sqflite/sqflite.dart';

class CubagemRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final AnaliseRepository _analiseRepository = AnaliseRepository();

  Future<void> limparTodasAsCubagens() async {
    final db = await _dbHelper.database;
    await db.delete('cubagens_arvores');
    debugPrint('Tabela de cubagens e seções limpa.');
  }

  // ===================================================================
  // ============ MÉTODO salvarCubagemCompleta ATUALIZADO =============
  // ===================================================================
  Future<void> salvarCubagemCompleta(CubagemArvore arvore, List<CubagemSecao> secoes) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      int id;
      arvore.isSynced = false;
      final map = arvore.toMap();

      // --- INÍCIO DA LÓGICA ADICIONADA ---
      final prefs = await SharedPreferences.getInstance();
      String? nomeDoResponsavel = prefs.getString('nome_lider');
      if (nomeDoResponsavel == null || nomeDoResponsavel.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          nomeDoResponsavel = user.displayName ?? user.email;
        }
      }
      if (nomeDoResponsavel != null) {
        map['nomeLider'] = nomeDoResponsavel;
      }
      // --- FIM DA LÓGICA ADICIONADA ---

      if (arvore.id == null) {
        id = await txn.insert('cubagens_arvores', map, conflictAlgorithm: ConflictAlgorithm.replace);
        arvore.id = id;
      } else {
        id = arvore.id!;
        await txn.update('cubagens_arvores', map, where: 'id = ?', whereArgs: [id]);
      }
      await txn.delete('cubagens_secoes', where: 'cubagemArvoreId = ?', whereArgs: [id]);
      for (var s in secoes) {
        s.cubagemArvoreId = id;
        await txn.insert('cubagens_secoes', s.toMap());
      }
    });
  }
  // ===================================================================
  // ===================== FIM DA ATUALIZAÇÃO ==========================
  // ===================================================================

  Future<List<CubagemArvore>> getTodasCubagensDoTalhao(int talhaoId) async {
    final db = await _dbHelper.database;
    final maps = await db.query('cubagens_arvores', where: 'talhaoId = ?', whereArgs: [talhaoId], orderBy: 'id ASC');
    return List.generate(maps.length, (i) => CubagemArvore.fromMap(maps[i]));
  }

  Future<List<CubagemArvore>> getTodasCubagens() async {
    final db = await _dbHelper.database;
    final maps = await db.query('cubagens_arvores', orderBy: 'id DESC');
    return List.generate(maps.length, (i) => CubagemArvore.fromMap(maps[i]));
  }

  Future<List<CubagemSecao>> getSecoesPorArvoreId(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query('cubagens_secoes', where: 'cubagemArvoreId = ?', whereArgs: [id], orderBy: 'alturaMedicao ASC');
    return List.generate(maps.length, (i) => CubagemSecao.fromMap(maps[i]));
  }

  Future<void> deletarCubagem(int id) async {
    final db = await _dbHelper.database;
    await db.delete('cubagens_arvores', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletarMultiplasCubagens(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.delete('cubagens_arvores', where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
  }

  Future<void> gerarPlanoDeCubagemNoBanco(Talhao talhao, int totalParaCubar, int novaAtividadeId, AnalysisService analysisService) async {
    final dadosAgregados = await _analiseRepository.getDadosAgregadosDoTalhao(talhao.id!);

    final parcelas = dadosAgregados['parcelas'] as List<Parcela>;
    final arvores = dadosAgregados['arvores'] as List<Arvore>;
    if (parcelas.isEmpty || arvores.isEmpty) throw Exception('Não há árvores suficientes neste talhão para gerar um plano.');

    final analise = analysisService.getTalhaoInsights(parcelas, arvores);
    final plano = analysisService.gerarPlanoDeCubagem(analise.distribuicaoDiametrica, analise.totalArvoresAmostradas, totalParaCubar);

    if (plano.isEmpty) throw Exception('Não foi possível gerar o plano de cubagem. Verifique os dados das parcelas.');

    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (final entry in plano.entries) {
        final classe = entry.key;
        final quantidade = entry.value;
        for (int i = 1; i <= quantidade; i++) {
          final arvoreCubagem = CubagemArvore(talhaoId: talhao.id!, idFazenda: talhao.fazendaId, nomeFazenda: talhao.fazendaNome ?? 'N/A', nomeTalhao: talhao.nome, identificador: '${talhao.nome} - Árvore ${i.toString().padLeft(2, '0')}', classe: classe, isSynced: false);
          await txn.insert('cubagens_arvores', arvoreCubagem.toMap());
        }
      }
    });
  }

  Future<List<CubagemArvore>> getUnsyncedCubagens() async {
    final db = await _dbHelper.database;
    final maps = await db.query('cubagens_arvores', where: 'isSynced = ?', whereArgs: [0]);
    return List.generate(maps.length, (i) => CubagemArvore.fromMap(maps[i]));
  }

  Future<List<CubagemArvore>> getUnexportedCubagens() async {
    final db = await _dbHelper.database;
    final maps = await db.query('cubagens_arvores', where: 'exportada = ?', whereArgs: [0]);
    return List.generate(maps.length, (i) => CubagemArvore.fromMap(maps[i]));
  }

  Future<List<CubagemArvore>> getTodasCubagensParaBackup() async {
    final db = await _dbHelper.database;
    final maps = await db.query('cubagens_arvores');
    return List.generate(maps.length, (i) => CubagemArvore.fromMap(maps[i]));
  }

  Future<void> markCubagemAsSynced(int id) async {
    final db = await _dbHelper.database;
    await db.update('cubagens_arvores', {'isSynced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> marcarCubagensComoExportadas(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.update('cubagens_arvores', {'exportada': 1}, where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
  }
}
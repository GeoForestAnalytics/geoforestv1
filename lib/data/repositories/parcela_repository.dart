// lib/data/repositories/parcela_repository.dart (VERSÃO CORRIGIDA E COMPLETA)
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class ParcelaRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // --- MÉTODOS DE SALVAMENTO E ATUALIZAÇÃO ---

  Future<Parcela> saveFullColeta(Parcela p, List<Arvore> arvores) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      int pId;
      p.isSynced = false;
      final pMap = p.toMap();
      final d = p.dataColeta ?? DateTime.now();
      pMap['dataColeta'] = d.toIso8601String();

      // Lógica robusta para identificar o responsável pela coleta
      final prefs = await SharedPreferences.getInstance();
      String? nomeDoResponsavel = prefs.getString('nome_lider');
      if (nomeDoResponsavel == null || nomeDoResponsavel.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          nomeDoResponsavel = user.displayName ?? user.email;
        }
      }
      if (nomeDoResponsavel != null) {
        pMap['nomeLider'] = nomeDoResponsavel;
      }

      if (p.dbId == null) {
        pMap.remove('id');
        pId = await txn.insert('parcelas', pMap);
        p.dbId = pId;
        p.dataColeta = d;
      } else {
        pId = p.dbId!;
        await txn.update('parcelas', pMap, where: 'id = ?', whereArgs: [pId]);
      }
      await txn.delete('arvores', where: 'parcelaId = ?', whereArgs: [pId]);
      for (final a in arvores) {
        final aMap = a.toMap();
        aMap['parcelaId'] = pId;
        await txn.insert('arvores', aMap);
      }
    });
    return p;
  }
  
  Future<void> saveBatchParcelas(List<Parcela> parcelas) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final p in parcelas) {
      batch.insert('parcelas', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<int> updateParcela(Parcela p) async {
    final db = await _dbHelper.database;
    return await db.update('parcelas', p.toMap(), where: 'id = ?', whereArgs: [p.dbId]);
  }
  
  Future<void> updateParcelaStatus(int parcelaId, StatusParcela novoStatus) async {
    final db = await _dbHelper.database;
    await db.update('parcelas', {'status': novoStatus.name}, where: 'id = ?', whereArgs: [parcelaId]);
  }

  // --- MÉTODOS DE CONSULTA (GET) ---

  Future<Parcela?> getParcelaById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) return Parcela.fromMap(maps.first);
    return null;
  }
  
  // <<< MÉTODO QUE FALTAVA ADICIONADO AQUI >>>
  /// Busca uma parcela específica pelo seu ID textual (ex: 'P01') dentro de um talhão.
  /// Retorna a [Parcela] se encontrada, caso contrário retorna null.
  Future<Parcela?> getParcelaPorIdParcela(int talhaoId, String idParcela) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'parcelas',
      where: 'talhaoId = ? AND idParcela = ?',
      whereArgs: [talhaoId, idParcela.trim()], // Adicionado .trim() por segurança
    );

    if (maps.isNotEmpty) {
      return Parcela.fromMap(maps.first);
    }
    return null;
  }
  
  Future<List<Parcela>> getParcelasDoTalhao(int talhaoId) async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas', where: 'talhaoId = ?', whereArgs: [talhaoId], orderBy: 'dataColeta DESC');
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<List<Arvore>> getArvoresDaParcela(int parcelaId) async {
    final db = await _dbHelper.database;
    final maps = await db.query('arvores', where: 'parcelaId = ?', whereArgs: [parcelaId], orderBy: 'linha, posicaoNaLinha, id');
    return List.generate(maps.length, (i) => Arvore.fromMap(maps[i]));
  }

  // --- MÉTODOS PARA SINCRONIZAÇÃO ---

  Future<List<Parcela>> getUnsyncedParcelas() async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas', where: 'isSynced = ?', whereArgs: [0]);
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<void> markParcelaAsSynced(int id) async {
    final db = await _dbHelper.database;
    await db.update('parcelas', {'isSynced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // --- MÉTODOS PARA EXPORTAÇÃO ---

  Future<List<Parcela>> getUnexportedConcludedParcelasByLider(String nomeLider) async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas', where: 'status = ? AND exportada = ? AND nomeLider = ?', whereArgs: [StatusParcela.concluida.name, 0, nomeLider]);
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }
  
  Future<List<Parcela>> getConcludedParcelasByLiderParaBackup(String nomeLider) async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas', where: 'status = ? AND nomeLider = ?', whereArgs: [StatusParcela.concluida.name, nomeLider]);
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<List<Parcela>> getUnexportedConcludedParcelasFiltrado({Set<int>? projetoIds, Set<String>? lideresNomes}) async {
    final db = await _dbHelper.database;
    String whereClause = 'status = ? AND exportada = ?';
    List<dynamic> whereArgs = [StatusParcela.concluida.name, 0];

    if (projetoIds != null && projetoIds.isNotEmpty) {
      whereClause += ' AND projetoId IN (${List.filled(projetoIds.length, '?').join(',')})';
      whereArgs.addAll(projetoIds);
    }
    if (lideresNomes != null && lideresNomes.isNotEmpty) {
      whereClause += ' AND nomeLider IN (${List.filled(lideresNomes.length, '?').join(',')})';
      whereArgs.addAll(lideresNomes);
    }

    final maps = await db.query('parcelas', where: whereClause, whereArgs: whereArgs);
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }

  Future<List<Parcela>> getTodasConcluidasParcelasFiltrado({Set<int>? projetoIds, Set<String>? lideresNomes}) async {
    final db = await _dbHelper.database;
    String whereClause = 'status = ?';
    List<dynamic> whereArgs = [StatusParcela.concluida.name];

    if (projetoIds != null && projetoIds.isNotEmpty) {
        whereClause += ' AND projetoId IN (${List.filled(projetoIds.length, '?').join(',')})';
        whereArgs.addAll(projetoIds);
    }
    if (lideresNomes != null && lideresNomes.isNotEmpty) {
        whereClause += ' AND nomeLider IN (${List.filled(lideresNomes.length, '?').join(',')})';
        whereArgs.addAll(lideresNomes);
    }

    final maps = await db.query('parcelas', where: whereClause, whereArgs: whereArgs);
    return List.generate(maps.length, (i) => Parcela.fromMap(maps[i]));
  }
  
  Future<void> marcarParcelasComoExportadas(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.update('parcelas', {'exportada': 1}, where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
  }

  Future<Set<String>> getDistinctLideres() async {
    final db = await _dbHelper.database;
    final maps = await db.query('parcelas', distinct: true, columns: ['nomeLider']);
    // Filtra nulos e converte para um Set para ter apenas valores únicos
    return maps.map((map) => map['nomeLider'] as String?).whereType<String>().toSet();
  }

  // --- MÉTODOS DE LIMPEZA ---

  Future<void> deletarMultiplasParcelas(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbHelper.database;
    await db.delete('parcelas', where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
  }

  Future<int> limparParcelasExportadas() async {
    final db = await _dbHelper.database;
    final count = await db.delete('parcelas', where: 'exportada = ?', whereArgs: [1]);
    debugPrint('$count parcelas exportadas foram apagadas.');
    return count;
  }
  
  Future<void> limparTodasAsParcelas() async {
    final db = await _dbHelper.database;
    await db.delete('parcelas');
    debugPrint('Tabela de parcelas e árvores limpa.');
  }
}
// lib/data/repositories/diario_de_campo_repository.dart (VERSÃO ATUALIZADA)

// Adicione estes imports no início do arquivo
import 'package:cloud_firestore/cloud_firestore.dart';

// -------------------------------------------
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:sqflite/sqflite.dart';

class DiarioDeCampoRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  
  // <<< INÍCIO DAS ADIÇÕES >>>
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // <<< FIM DAS ADIÇÕES >>>

  Future<void> insertOrUpdateDiario(DiarioDeCampo diario) async {
    final db = await _dbHelper.database;
    await db.insert(
      DbDiarioDeCampo.tableName,
      diario.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DiarioDeCampo?> getDiario(String data, String lider) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbDiarioDeCampo.tableName,
      where: '${DbDiarioDeCampo.dataRelatorio} = ? AND ${DbDiarioDeCampo.nomeLider} = ?',
      whereArgs: [data, lider],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return DiarioDeCampo.fromMap(maps.first);
    }
    return null;
  }

  // <<< NOVO MÉTODO 1: BUSCAR DIÁRIOS POR LÍDER >>>
  /// Busca todos os diários de um líder específico no banco de dados local, ordenados por data.
  Future<List<DiarioDeCampo>> getDiariosPorLider(String nomeLider) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      DbDiarioDeCampo.tableName,
      where: '${DbDiarioDeCampo.nomeLider} = ?',
      whereArgs: [nomeLider],
      orderBy: '${DbDiarioDeCampo.dataRelatorio} DESC', // Mais recentes primeiro
    );

    return List.generate(maps.length, (i) => DiarioDeCampo.fromMap(maps[i]));
  }

  // <<< NOVO MÉTODO 2: APAGAR DIÁRIO >>>
  /// Apaga um diário de campo do banco local (SQLite) e da nuvem (Firestore).
  Future<void> deleteDiario(DiarioDeCampo diario, String licenseId) async {
    final db = await _dbHelper.database;

    // Etapa 1: Apagar do banco de dados local
    await db.delete(
      DbDiarioDeCampo.tableName,
      where: '${DbDiarioDeCampo.id} = ?',
      whereArgs: [diario.id],
    );

    // Etapa 2: Apagar do Firestore
    final docId = '${diario.dataRelatorio}_${diario.nomeLider.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-')}';
    final docRef = _firestore.collection('clientes').doc(licenseId).collection('diarios_de_campo').doc(docId);
    
    // Verifica se o documento existe antes de tentar apagar
    if ((await docRef.get()).exists) {
      await docRef.delete();
    }
  }
}
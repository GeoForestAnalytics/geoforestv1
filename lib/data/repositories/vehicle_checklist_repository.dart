import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/vehicle_checklist_model.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

class VehicleChecklistRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> insertChecklist(VehicleChecklist checklist) async {
    final db = await _dbHelper.database;
    return await db.insert('checklist_veicular', checklist.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Verifica se já existe um checklist para a data de hoje feito por este usuário (ou geral do dia)
  Future<bool> hasChecklistForToday() async {
    final db = await _dbHelper.database;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    // A query verifica se existe algum registro que começa com a data de hoje (ignorando hora)
    final result = await db.query(
      'checklist_veicular',
      where: 'data_registro LIKE ?',
      whereArgs: ['$today%'],
      limit: 1
    );

    return result.isNotEmpty;
  }

  // Adicione este método:
  Future<VehicleChecklist?> getChecklistForToday() async {
    final db = await _dbHelper.database;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    final result = await db.query(
      'checklist_veicular',
      where: 'data_registro LIKE ?',
      whereArgs: ['$today%'],
      limit: 1
    );

    if (result.isNotEmpty) {
      return VehicleChecklist.fromMap(result.first);
    }
    return null;
  }
}
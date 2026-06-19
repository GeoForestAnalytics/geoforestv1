import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/especie_model.dart';

class EspecieRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<List<Especie>> buscarPorNome(String query) async {
    if (query.trim().isEmpty) return [];
    
    final db = await _dbHelper.database;
    final resultado = await db.query(
      'especies',
      where: 'nome_comum LIKE ? OR nome_cientifico LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      limit: 10, // Traz apenas 10 sugestões para ser rápido
    );

    return resultado.map((map) => Especie.fromMap(map)).toList();
  }
}
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

  /// Busca o nome comum em português já cadastrado na base interna a partir
  /// de um nome científico vindo de uma API externa (ex.: Pl@ntNet) — essas
  /// retornam em inglês/latim, então isso traduz pro nome que a equipe usa.
  ///
  /// Tenta match exato primeiro; se não achar, tenta só o binômio (gênero +
  /// epíteto), já que a API pode vir com variação de autoria/subespécie que
  /// a base interna não tem.
  Future<Especie?> buscarPorNomeCientifico(String nomeCientifico) async {
    final nome = nomeCientifico.trim();
    if (nome.isEmpty) return null;

    final db = await _dbHelper.database;

    final exato = await db.query(
      'especies',
      where: 'nome_cientifico = ?',
      whereArgs: [nome],
      limit: 1,
    );
    if (exato.isNotEmpty) return Especie.fromMap(exato.first);

    final partes = nome.split(' ');
    if (partes.length >= 2) {
      final binomio = '${partes[0]} ${partes[1]}';
      final aproximado = await db.query(
        'especies',
        where: 'nome_cientifico LIKE ?',
        whereArgs: ['$binomio%'],
        limit: 1,
      );
      if (aproximado.isNotEmpty) return Especie.fromMap(aproximado.first);
    }

    return null;
  }
}
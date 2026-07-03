// lib/services/import/planejamento_cubagem_import_strategy.dart (VERSÃO CORRIGIDA)

import 'package:geoforestv1/data/datasources/local/database_helper.dart'; // Para proj4
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'csv_import_strategy.dart'; // Importa a base

class PlanejamentoCubagemImportStrategy extends BaseImportStrategy {
  PlanejamentoCubagemImportStrategy({required super.txn, required super.projeto, super.nomeDoResponsavel});

  @override
  Future<ImportResult> processar(List<Map<String, dynamic>> dataRows) async {
    final result = ImportResult();
    
    // <<< CORREÇÃO APLICADA AQUI >>>
    final now = DateTime.now().toIso8601String(); // Era "toIso86o1String"

    for (final row in dataRows) {
      result.linhasProcessadas++;
      
      final talhao = await getOrCreateHierarchy(row, result);
      if (talhao == null) continue;

      final medir = BaseImportStrategy.getValue(row, ['medir ?', 'medir'])?.toUpperCase();
      if (medir != 'SIM') {
        result.parcelasIgnoradas++;
        continue;
      }
      
      final idArvore = BaseImportStrategy.getValue(row, ['identificador_arvore']);
      if (idArvore == null) continue;

      final arvoreExistente = await txn.query('cubagens_arvores', where: 'talhaoId = ? AND identificador = ?', whereArgs: [talhao.id!, idArvore]);
      if (arvoreExistente.isNotEmpty) continue;

      double? latitudeFinal, longitudeFinal;
      final eastingStr = BaseImportStrategy.getValue(row, ['long (x)']);
      final northingStr = BaseImportStrategy.getValue(row, ['lat (y)']);
      final zonaStr = BaseImportStrategy.getValue(row, ['zonautm']);

      if (eastingStr != null && northingStr != null && zonaStr != null) {
          final easting = double.tryParse(eastingStr.replaceAll(',', '.'));
          final northing = double.tryParse(northingStr.replaceAll(',', '.'));
          final zonaNum = int.tryParse(zonaStr.replaceAll(RegExp(r'[^0-9]'), ''));

          if (easting != null && northing != null && zonaNum != null) {
              final epsg = 31978 + (zonaNum - 18);
              if (proj4Definitions.containsKey(epsg)) {
                  final projUTM = proj4.Projection.get('EPSG:$epsg') ?? proj4.Projection.parse(proj4Definitions[epsg]!);
                  final projWGS84 = proj4.Projection.get('EPSG:4326')!;
                  var pontoWGS84 = projUTM.transform(projWGS84, proj4.Point(x: easting, y: northing));
                  latitudeFinal = pontoWGS84.y;
                  longitudeFinal = pontoWGS84.x;
              }
          }
      }

      // Coluna O (classe): se for um número → passo fixo de seções; classe vem sempre de classe_A/classe_B
      final classeRaw = BaseImportStrategy.getValue(row, ['classe']);
      final passoFixo = double.tryParse(classeRaw?.replaceAll(',', '.') ?? '');

      String? classeFinal;
      final classeAStr = BaseImportStrategy.getValue(row, ['classe_a']);
      final classeBStr = BaseImportStrategy.getValue(row, ['classe_b']);
      if (classeAStr != null && classeBStr != null) {
        classeFinal = '${classeAStr.replaceAll(',', '.')} - ${classeBStr.replaceAll(',', '.')}';
      } else if (classeRaw != null && classeRaw.trim() != '.' && passoFixo == null) {
        classeFinal = classeRaw;
      }

      final novaArvoreCubagem = CubagemArvore(
        talhaoId: talhao.id,
        idFazenda: talhao.fazendaId,
        nomeFazenda: talhao.fazendaNome ?? 'N/A',
        nomeTalhao: talhao.nome,
        identificador: idArvore,
        classe: classeFinal,
        tipoMedidaCAP: BaseImportStrategy.getValue(row, ['tipo']) ?? 'fita',
        observacao: BaseImportStrategy.getValue(row, ['observa o', 'observacao']),
        latitude: latitudeFinal,
        longitude: longitudeFinal,
        metodoCubagem: BaseImportStrategy.getValue(row, ['metodo']),
        rf: BaseImportStrategy.getValue(row, ['rf']),
        passoFixo: passoFixo ?? 2.0,
        alturaTotal: 0,
        valorCAP: 0,
        alturaBase: 0,
        isSynced: false,
        exportada: false,
      );
      
      final map = novaArvoreCubagem.toMap();
      map['lastModified'] = now;
      await txn.insert('cubagens_arvores', map);
      result.cubagensCriadas++;
    }
    return result;
  }
}
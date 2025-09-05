// lib/services/import/planejamento_import_strategy.dart

import 'package:geoforestv1/models/parcela_model.dart';
import 'csv_import_strategy.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:geoforestv1/data/datasources/local/database_helper.dart';


class PlanejamentoImportStrategy extends BaseImportStrategy {
  PlanejamentoImportStrategy({required super.txn, required super.projeto, super.nomeDoResponsavel});

  @override
  Future<ImportResult> processar(List<Map<String, dynamic>> dataRows) async {
    final result = ImportResult();
    final now = DateTime.now().toIso8601String();

    for (final row in dataRows) {
      result.linhasProcessadas++;
      
      final talhao = await getOrCreateHierarchy(row, result);
      if (talhao == null) continue;

      final medir = BaseImportStrategy.getValue(row, ['medir ?', 'medir'])?.toUpperCase();
      if (medir != 'SIM') {
        result.parcelasIgnoradas++;
        continue;
      }

      final idParcelaColeta = BaseImportStrategy.getValue(row, ['parcela']);
      if (idParcelaColeta == null) continue;

      final parcelaExistente = await txn.query('parcelas', where: 'idParcela = ? AND talhaoId = ?', whereArgs: [idParcelaColeta, talhao.id!]);
      if (parcelaExistente.isNotEmpty) continue;

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

      // --- LÓGICA INTELIGENTE DE ÁREA E FORMA ---
      final lado1 = double.tryParse(BaseImportStrategy.getValue(row, ['lado 1', 'lado1'])?.replaceAll(',', '.') ?? '');
      final lado2 = double.tryParse(BaseImportStrategy.getValue(row, ['lado 2', 'lado2'])?.replaceAll(',', '.') ?? '');
      final areaDoCsv = double.tryParse(BaseImportStrategy.getValue(row, ['áreaparcela', 'areaparcela'])?.replaceAll(',', '.') ?? '0.0') ?? 0.0;
      
      String formaFinal = 'Retangular';
      double areaFinal = areaDoCsv;

      if (areaDoCsv > 0 && (lado1 == null || lado1 <= 0) && (lado2 == null || lado2 <= 0)) {
        formaFinal = 'Circular';
      } else if (lado1 != null && lado2 != null && lado1 > 0 && lado2 > 0) {
        areaFinal = lado1 * lado2; // Calcula a área se os lados forem fornecidos
      }
      // --- FIM DA LÓGICA ---

      final novaParcela = Parcela(
        talhaoId: talhao.id!, 
        idParcela: idParcelaColeta,
        status: StatusParcela.pendente,
        dataColeta: DateTime.now(),
        areaMetrosQuadrados: areaFinal, // <-- Usa a área final
        formaParcela: formaFinal,       // <-- Usa a forma final
        idFazenda: talhao.fazendaId,
        nomeFazenda: talhao.fazendaNome, 
        nomeTalhao: talhao.nome,
        up: BaseImportStrategy.getValue(row, ['rf']),
        referenciaRf: BaseImportStrategy.getValue(row, ['rf']),
        ciclo: BaseImportStrategy.getValue(row, ['ciclo']),
        rotacao: int.tryParse(BaseImportStrategy.getValue(row, ['rotação', 'rotacao']) ?? ''),
        tipoParcela: BaseImportStrategy.getValue(row, ['tipo']),
        lado1: lado1,
        lado2: lado2,
        declividade: double.tryParse(BaseImportStrategy.getValue(row, ['declividade', 'declividade_%'])?.replaceAll(',', '.') ?? ''),
        latitude: latitudeFinal,
        longitude: longitudeFinal,
        projetoId: projeto.id,
      );
      
      final map = novaParcela.toMap();
      map['lastModified'] = now;
      await txn.insert('parcelas', map);
      result.parcelasCriadas++;
    }
    return result;
  }
}
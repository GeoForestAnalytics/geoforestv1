import 'dart:convert';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/pilha_madeira_model.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'csv_import_strategy.dart';

class PilhaOsImportStrategy extends BaseImportStrategy {
  PilhaOsImportStrategy({required super.txn, required super.projeto, super.nomeDoResponsavel});

  @override
  Future<ImportResult> processar(List<Map<String, dynamic>> dataRows) async {
    final result = ImportResult();
    final now = DateTime.now().toIso8601String();

    // Cache: talhaoId → CentroidePilha id  (para atualizar sortimentos acumulados)
    final Map<int, int> centroideIdCache = {};
    final Map<int, List<SortimentoConfig>> sortimentosCache = {};

    for (final row in dataRows) {
      result.linhasProcessadas++;

      // Respeita o filtro Medir? = SIM (igual às outras OS)
      final medir = BaseImportStrategy.getValue(row, ['medir ?', 'medir'])?.toUpperCase();
      if (medir != null && medir != 'SIM') {
        result.parcelasIgnoradas++;
        continue;
      }

      final talhao = await getOrCreateHierarchy(row, result);
      if (talhao == null) continue;

      // --- Coordenadas do centróide ---
      double? latFinal, lonFinal;
      final eastingStr = BaseImportStrategy.getValue(row, ['long (x)', 'longitude', 'lon', 'x']);
      final northingStr = BaseImportStrategy.getValue(row, ['lat (y)', 'latitude', 'lat', 'y']);
      final zonaStr = BaseImportStrategy.getValue(row, ['zonautm', 'zona_utm', 'zona']);

      if (eastingStr != null && northingStr != null) {
        final easting = double.tryParse(eastingStr.replaceAll(',', '.'));
        final northing = double.tryParse(northingStr.replaceAll(',', '.'));

        if (easting != null && northing != null) {
          if (zonaStr != null && (northing > 1000 || easting > 180)) {
            final zonaNum = int.tryParse(zonaStr.replaceAll(RegExp(r'[^0-9]'), ''));
            if (zonaNum != null) {
              final epsg = 31978 + (zonaNum - 18);
              if (proj4Definitions.containsKey(epsg)) {
                final projUTM = proj4.Projection.get('EPSG:$epsg') ??
                    proj4.Projection.parse(proj4Definitions[epsg]!);
                final projWGS84 = proj4.Projection.get('EPSG:4326')!;
                final pt = projUTM.transform(projWGS84, proj4.Point(x: easting, y: northing));
                latFinal = pt.y;
                lonFinal = pt.x;
              }
            }
          } else {
            latFinal = northing;
            lonFinal = easting;
          }
        }
      }

      if (latFinal == null || lonFinal == null) continue;

      // --- Sortimento desta linha ---
      // identificador_pilha = classe de sortimento (ex: "18-25", ">32", "8-18")
      final nomeSortimento = BaseImportStrategy.getValue(row, ['identificador_pilha', 'sortimento', 'nome_sortimento']) ?? 'Padrão';
      final dapMinStr = BaseImportStrategy.getValue(row, ['classe_a', 'dap_min', 'diametro_min']);
      final dapMaxStr = BaseImportStrategy.getValue(row, ['classe_b', 'dap_max', 'diametro_max']);
      final comprToraStr = BaseImportStrategy.getValue(row, ['tamanho_tora', 'comprimento_tora', 'comp_tora']);
      final volEsperadoStr = BaseImportStrategy.getValue(row, [
        'volume_esperado_m3', 'vol_esperado', 'volume_m3',
        'volume_esperado', 'm3_esperado', 'm_esperado', 'classe',
      ]);

      final sortimentoConfig = SortimentoConfig(
        nome: nomeSortimento,
        dapMin: double.tryParse(dapMinStr?.replaceAll(',', '.') ?? ''),
        dapMax: double.tryParse(dapMaxStr?.replaceAll(',', '.') ?? ''),
        comprimentoTora: double.tryParse(comprToraStr?.replaceAll(',', '.') ?? '') ?? 2.4,
        volumeEsperadoM3: double.tryParse(volEsperadoStr?.replaceAll(',', '.') ?? ''),
      );

      final talhaoId = talhao.id!;

      // --- Acumula sortimentos por talhão ---
      sortimentosCache.putIfAbsent(talhaoId, () => []);
      final existeNome = sortimentosCache[talhaoId]!.any((s) => s.nome == nomeSortimento);
      if (!existeNome) sortimentosCache[talhaoId]!.add(sortimentoConfig);

      // --- Cria ou atualiza centróide para este talhão ---
      if (!centroideIdCache.containsKey(talhaoId)) {
        final existing = await txn.query(
          DbCentroidesPilha.tableName,
          where: '${DbCentroidesPilha.talhaoId} = ?',
          whereArgs: [talhaoId],
        );
        if (existing.isNotEmpty) {
          centroideIdCache[talhaoId] = existing.first[DbCentroidesPilha.id] as int;
        } else {
          final centroide = CentroidePilha(
            talhaoId: talhaoId,
            fazendaId: talhao.fazendaId,
            nomeFazenda: talhao.fazendaNome ?? '',
            nomeTalhao: talhao.nome,
            latitude: latFinal,
            longitude: lonFinal,
            sortimentos: [],
          );
          final map = centroide.toMap();
          map[DbCentroidesPilha.lastModified] = now;
          final newId = await txn.insert(DbCentroidesPilha.tableName, map);
          centroideIdCache[talhaoId] = newId;
          result.centroidesCriados++;
        }
      }
    }

    // --- Persiste os sortimentos acumulados ---
    for (final entry in sortimentosCache.entries) {
      final centroideId = centroideIdCache[entry.key];
      if (centroideId == null) continue;
      await txn.update(
        DbCentroidesPilha.tableName,
        {
          DbCentroidesPilha.sortimentos: jsonEncode(entry.value.map((s) => s.toMap()).toList()),
          DbCentroidesPilha.lastModified: DateTime.now().toIso8601String(),
        },
        where: '${DbCentroidesPilha.id} = ?',
        whereArgs: [centroideId],
      );
    }

    return result;
  }
}

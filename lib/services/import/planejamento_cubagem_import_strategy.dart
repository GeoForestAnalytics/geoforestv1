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

    const aceitas = {'CUB', 'CUBAGEM'};

    for (final row in dataRows) {
      result.linhasProcessadas++;

      // Filtra apenas linhas de cubagem
      if (!BaseImportStrategy.passaFiltroAtividade(row, aceitas)) {
        result.parcelasIgnoradas++;
        continue;
      }

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
      // Já existe um registro pra esse identificador (ex.: planilha com mais de
      // uma linha pro mesmo ponto). Se o registro salvo já tem coordenada, não
      // há nada a fazer. Mas se ele ficou sem coordenada (a primeira linha
      // processada veio com a célula de Long/Lat em branco) e ESTA linha trouxe
      // uma coordenada válida, completa o registro em vez de descartar a
      // informação — antes isso era perdido silenciosamente.
      if (arvoreExistente.isNotEmpty) {
        final jaTemCoordenada = arvoreExistente.first['latitude'] != null
            && arvoreExistente.first['longitude'] != null;
        if (jaTemCoordenada) continue;
        final coordenadaDaLinha = _extrairCoordenada(row);
        if (coordenadaDaLinha == null) continue;
        await txn.update(
          'cubagens_arvores',
          {
            'latitude': coordenadaDaLinha.$1,
            'longitude': coordenadaDaLinha.$2,
            'lastModified': now,
          },
          where: 'id = ?',
          whereArgs: [arvoreExistente.first['id']],
        );
        continue;
      }

      final coordenada = _extrairCoordenada(row);
      final latitudeFinal = coordenada?.$1;
      final longitudeFinal = coordenada?.$2;

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
      if (latitudeFinal != null && longitudeFinal != null) {
        result.cubagensComCoordenada++;
      } else {
        result.cubagensSemCoordenada++;
      }
    }
    return result;
  }

  /// Lê Long(X)/Lat(Y)/ZonaUTM da linha e converte UTM -> WGS84.
  /// Retorna null se a linha não tiver uma coordenada completa/válida.
  (double, double)? _extrairCoordenada(Map<String, dynamic> row) {
    final eastingStr = BaseImportStrategy.getValue(row, ['long (x)']);
    final northingStr = BaseImportStrategy.getValue(row, ['lat (y)']);
    final zonaStr = BaseImportStrategy.getValue(row, ['zonautm']);
    if (eastingStr == null || northingStr == null || zonaStr == null) return null;

    final easting = double.tryParse(eastingStr.replaceAll(',', '.'));
    final northing = double.tryParse(northingStr.replaceAll(',', '.'));
    final zonaNum = int.tryParse(zonaStr.replaceAll(RegExp(r'[^0-9]'), ''));
    if (easting == null || northing == null || zonaNum == null) return null;

    final epsg = 31978 + (zonaNum - 18);
    if (!proj4Definitions.containsKey(epsg)) return null;

    final projUTM = proj4.Projection.get('EPSG:$epsg') ?? proj4.Projection.parse(proj4Definitions[epsg]!);
    final projWGS84 = proj4.Projection.get('EPSG:4326')!;
    final pontoWGS84 = projUTM.transform(projWGS84, proj4.Point(x: easting, y: northing));
    return (pontoWGS84.y, pontoWGS84.x); // (latitude, longitude)
  }
}
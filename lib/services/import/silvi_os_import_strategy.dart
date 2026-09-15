import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/silvi_model.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'csv_import_strategy.dart';

/// Importa uma OS de Silvicultura.
///
/// Colunas esperadas (nomes flexíveis — getValue sanitiza):
///   Atividade, Fazenda, Talhão, Operação (tipo), Área Ha (areaHa),
///   Data Prevista, Long (X), Lat (Y), Zona UTM
///
/// Cria um CentroideSilvi por talhão, acumulando as OperacoesPlanejadas.
class SilviOsImportStrategy extends BaseImportStrategy {
  SilviOsImportStrategy({
    required super.txn,
    required super.projeto,
    super.nomeDoResponsavel,
  });

  @override
  Future<ImportResult> processar(List<Map<String, dynamic>> dataRows) async {
    final result = ImportResult();
    final now = DateTime.now().toIso8601String();

    // talhaoId → centroideId (cache para não duplicar)
    final centroideIdCache = <int, int>{};
    // talhaoId → List<OperacaoPlanejada> (acumula antes de persistir)
    final operacoesCache = <int, List<OperacaoPlanejada>>{};
    // talhaoId → lat/lon/areaTotalHa (primeira ocorrência define a posição)
    final posCache = <int, (double lat, double lon, double? area)>{};

    for (final row in dataRows) {
      result.linhasProcessadas++;

      // Filtra apenas linhas de silvicultura — coluna Atividade = "SILVI"
      if (!BaseImportStrategy.passaFiltroAtividade(row, {'SILVI', 'SILVICULTURA'})) {
        result.parcelasIgnoradas++;
        continue;
      }

      // Respeita o filtro Medir? = SIM se a coluna existir
      final medir = BaseImportStrategy.getValue(row, ['medir ?', 'medir'])?.toUpperCase();
      if (medir != null && medir != 'SIM') {
        result.parcelasIgnoradas++;
        continue;
      }

      // Se não há coluna 'atividade' (detecção por cabeçalho XLSX), injeta 'SILVI'
      // para que getOrCreateHierarchy consiga criar a hierarquia de atividade.
      final effectiveRow = BaseImportStrategy.getValue(row, ['atividade']) != null
          ? row
          : {...row, 'atividade': 'SILVI'};

      final talhao = await getOrCreateHierarchy(effectiveRow, result);
      if (talhao == null) continue;
      final talhaoId = talhao.id!;

      // ── Coordenadas ────────────────────────────────────────────────────────
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

      // ── Operação planejada desta linha ────────────────────────────────────
      // Nota: 'tipo' é ignorado pois nesta OS representa tipo de medição (FITA, etc.),
      // não o tipo de operação silvicultural.
      var tipoRaw = BaseImportStrategy.getValue(row, [
        'operacao', 'operação', 'tipo_operacao', 'atividade_silvi', 'identificador_atividade',
      ]);
      // Fallback para 'material', exceto '.' (placeholder de vazio nesta OS)
      if (tipoRaw == null) {
        final mat = BaseImportStrategy.getValue(row, ['material']);
        if (mat != null && mat.trim() != '.') tipoRaw = mat;
      }
      tipoRaw ??= 'outro';
      final tipoNorm = _normalizarTipo(tipoRaw);

      final areaTotalHaStr = BaseImportStrategy.getValue(row, [
        'area_total_ha', 'area total ha', 'area_talhao_ha', 'area_talh',
      ]);
      final areaTotalHa = double.tryParse(areaTotalHaStr?.replaceAll(',', '.') ?? '');

      final areaHaStr = BaseImportStrategy.getValue(row, [
        'area_ha', 'areaha', 'area ha', 'area_aplicada', 'ha',
      ]);
      // Fallback: se não houver coluna de área por operação, usa a área total do talhão
      final areaHa = double.tryParse(areaHaStr?.replaceAll(',', '.') ?? '') ?? areaTotalHa;

      final dataPrevista = BaseImportStrategy.getValue(row, [
        'data_prevista', 'data prevista', 'dataprevista', 'previsao',
      ]);

      // ── Colunas coringa (espécie, produto, etc.) ──────────────────────────
      final extras = _extrairExtras(row);

      // Acumula operações por talhão (evita duplicar o mesmo tipo)
      operacoesCache.putIfAbsent(talhaoId, () => []);
      final jaTemTipo = operacoesCache[talhaoId]!.any((o) => o.tipo == tipoNorm);
      if (!jaTemTipo) {
        operacoesCache[talhaoId]!.add(OperacaoPlanejada(
          tipo: tipoNorm,
          areaHa: areaHa,
          dataPrevista: dataPrevista,
          extras: extras,
        ));
      }

      // Salva posição e área total da primeira linha deste talhão
      if (!posCache.containsKey(talhaoId) && latFinal != null && lonFinal != null) {
        posCache[talhaoId] = (latFinal, lonFinal, areaTotalHa);
      }

      // ── Cria ou encontra centróide ─────────────────────────────────────────
      debugPrint('[Silvi] talhaoId=$talhaoId lat=$latFinal lon=$lonFinal tipo=$tipoNorm');
      if (!centroideIdCache.containsKey(talhaoId)) {
        final existing = await txn.query(
          DbCentroidesSilvi.tableName,
          where: '${DbCentroidesSilvi.talhaoId} = ?',
          whereArgs: [talhaoId],
        );
        if (existing.isNotEmpty) {
          centroideIdCache[talhaoId] = existing.first[DbCentroidesSilvi.id] as int;
          debugPrint('[Silvi] centroide já existe id=${centroideIdCache[talhaoId]}');
        } else {
          if (latFinal == null || lonFinal == null) {
            debugPrint('[Silvi] SKIP: lat/lon nulos para talhaoId=$talhaoId');
            continue;
          }
          try {
            final map = {
              DbCentroidesSilvi.talhaoId: talhaoId,
              DbCentroidesSilvi.fazendaId: talhao.fazendaId,
              DbCentroidesSilvi.nomeFazenda: talhao.fazendaNome ?? '',
              DbCentroidesSilvi.nomeTalhao: talhao.nome,
              DbCentroidesSilvi.latitude: latFinal,
              DbCentroidesSilvi.longitude: lonFinal,
              DbCentroidesSilvi.areaTotalHa: areaTotalHa,
              DbCentroidesSilvi.operacoesPlanejadas: '[]',
              DbCentroidesSilvi.lastModified: now,
            };
            final newId = await txn.insert(DbCentroidesSilvi.tableName, map);
            centroideIdCache[talhaoId] = newId;
            result.centroidesCriados++;
            debugPrint('[Silvi] centroide criado id=$newId');
          } catch (e) {
            debugPrint('[Silvi] ERRO ao inserir centroide talhaoId=$talhaoId: $e');
            rethrow;
          }
        }
      }
    }

    // ── Persiste as operações planejadas acumuladas ────────────────────────
    for (final entry in operacoesCache.entries) {
      final centroideId = centroideIdCache[entry.key];
      if (centroideId == null) continue;
      await txn.update(
        DbCentroidesSilvi.tableName,
        {
          DbCentroidesSilvi.operacoesPlanejadas:
              jsonEncode(entry.value.map((o) => o.toMap()).toList()),
          DbCentroidesSilvi.lastModified: DateTime.now().toIso8601String(),
        },
        where: '${DbCentroidesSilvi.id} = ?',
        whereArgs: [centroideId],
      );
    }

    return result;
  }

  // Extrai colunas desconhecidas da linha como extras (espécie, produto, etc.)
  static const _keysConhecidas = {
    'atividade', 'fazenda', 'talhao', 'talhão', 'uf', 'municipio', 'município',
    'projeto', 'equipe', 'up', 'sub_up', 'subup',
    'operacao', 'operação', 'tipo_operacao', 'atividade_silvi', 'identificador_atividade',
    // 'material' é intencionalmente excluído para ser capturado como extra (produto)
    'area_ha', 'areaha', 'area ha', 'area_aplicada', 'ha', 'area',
    'data_prevista', 'data prevista', 'dataprevista', 'previsao',
    'area_total_ha', 'area total ha', 'area_talhao_ha', 'area_talh',
    'long (x)', 'longitude', 'lon', 'x',
    'lat (y)', 'latitude', 'lat', 'y',
    'zonautm', 'zona_utm', 'zona',
    'medir ?', 'medir',
  };

  static Map<String, String> _extrairExtras(Map<String, dynamic> row) {
    final extras = <String, String>{};
    for (final entry in row.entries) {
      final keyNorm = entry.key.toLowerCase().trim()
          .replaceAll(RegExp(r'\s+'), ' ');
      if (_keysConhecidas.contains(keyNorm)) continue;
      final val = entry.value?.toString().trim() ?? '';
      if (val.isEmpty || val == '.' || val == '-') continue;
      // Usa a chave original (capitalizada) como rótulo no export
      extras[entry.key.trim()] = val;
    }
    return extras;
  }

  // Normaliza o nome da operação para o enum OperacaoSilviTipo.name
  String _normalizarTipo(String raw) {
    // Normaliza acentos antes de remover não-ASCII (ç→c, ã→a, etc.)
    final s = raw.toLowerCase()
        .replaceAll('ç', 'c')
        .replaceAll('ã', 'a')
        .replaceAll('á', 'a')
        .replaceAll('â', 'a')
        .replaceAll('à', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ú', 'u')
        .replaceAll(RegExp(r'[^a-z]'), '');
    // Replantio antes de plantio (mais específico)
    if (s.contains('replan') || s.contains('replant')) return 'replantio';
    if (s.contains('plan') || s == 'plantio') return 'plantio';
    if (s.contains('irrig')) return 'irrigacao';
    if (s.contains('adub') || s.contains('fertil')) return 'adubacao';
    // 'rocada' cobre 'roçada' após normalização ç→c
    if (s.contains('roc')) return 'rocada';
    if (s.contains('coroam') || s.contains('coroamento')) return 'coroamento';
    if (s.contains('herbic') || s.contains('veneno') || s.contains('venen')) return 'herbicida';
    // 'formi' cobre tanto 'formicida' quanto 'formiga'
    if (s.contains('formi') || s.contains('isca')) return 'formicida';
    if (s.contains('capina')) return 'capina';
    if (s.contains('desbrot') || s.contains('poda')) return 'desbrota';
    // Tenta match direto com enum
    try {
      OperacaoSilviTipo.fromString(s);
      return s;
    } catch (_) {}
    return 'outro';
  }
}

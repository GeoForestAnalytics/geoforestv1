// lib/utils/utm_converter.dart
//
// Conversão WGS84 -> UTM (SIRGAS2000), extraída pra cá pra ser testável
// isoladamente (antes vivia presa dentro de um State privado do Flutter).
//
// Contém o próprio conserto do bug encontrado em 2026-09: Projection.get()
// não lança exceção pra projeção não registrada, só retorna null — então
// qualquer chamador precisa checar null e registrar via Projection.add()
// antes de usar, nunca confiar só no registro global feito em main.dart.

import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:geoforestv1/data/datasources/local/database_helper.dart' show proj4Definitions;
import 'package:geoforestv1/utils/constants.dart';

const String zonaUtmPadrao = 'SIRGAS 2000 / UTM Zona 22S';

/// Garante que a projeção EPSG:4326 (WGS84) e a zona UTM pedida estão
/// registradas no proj4dart, registrando na hora se ainda não estiverem.
void garantirProjecoesRegistradas(int codigoEpsg) {
  if (proj4.Projection.get('EPSG:4326') == null) {
    proj4.Projection.add('EPSG:4326', '+proj=longlat +datum=WGS84 +no_defs');
  }
  if (proj4.Projection.get('EPSG:$codigoEpsg') == null) {
    final def = proj4Definitions[codigoEpsg];
    if (def != null) proj4.Projection.add('EPSG:$codigoEpsg', def);
  }
}

/// Converte latitude/longitude (WGS84) pra string UTM no formato
/// `E:x N:y <nome da zona>`. Retorna "UTM N/A" se faltar coordenada
/// ou a conversão falhar por qualquer motivo — nunca lança exceção.
///
/// Sem "|" no resultado de propósito: é o separador usado no comentário EXIF
/// que carrega esse texto (ver arvore_dialog.dart), então um "|" aqui dentro
/// quebraria o parser do script de marca d'água.
String converterParaUtm({
  required double? latitude,
  required double? longitude,
  String nomeZona = zonaUtmPadrao,
}) {
  if (latitude == null || longitude == null) return "UTM N/A";
  try {
    final codigoEpsg = zonasUtmSirgas2000[nomeZona] ?? 31982;
    garantirProjecoesRegistradas(codigoEpsg);

    final projWGS84 = proj4.Projection.get('EPSG:4326');
    final projUTM = proj4.Projection.get('EPSG:$codigoEpsg');
    if (projWGS84 == null || projUTM == null) return "UTM N/A";

    final pUtm = projWGS84.transform(projUTM, proj4.Point(x: longitude, y: latitude));
    return "E:${pUtm.x.toInt()} N:${pUtm.y.toInt()} ${nomeZona.split('/').last.trim()}";
  } catch (e) {
    return "UTM N/A";
  }
}

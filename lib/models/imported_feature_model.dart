// lib/models/imported_feature_model.dart (NOVO ARQUIVO)

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// Modelo para polígonos importados
class ImportedPolygonFeature {
  final Polygon polygon;
  final Map<String, dynamic> properties;

  ImportedPolygonFeature({required this.polygon, required this.properties});
}

// Modelo para pontos importados
class ImportedPointFeature {
  final LatLng position;
  final Map<String, dynamic> properties;

  ImportedPointFeature({required this.position, required this.properties});
}
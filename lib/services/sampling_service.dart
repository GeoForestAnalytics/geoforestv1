// lib/services/sampling_service.dart (VERSÃO CORRIGIDA)

import 'dart:math';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// <<< 1. IMPORTA O NOVO MODELO CENTRALIZADO EM VEZ DO 'geojson_service' >>>
import 'package:geoforestv1/models/imported_feature_model.dart';

// Classe auxiliar para transportar o ponto gerado e as propriedades do talhão.
class GeneratedPoint {
  final LatLng position;
  final Map<String, dynamic> properties;

  GeneratedPoint({required this.position, required this.properties});
}

class SamplingService {
  
  // Método principal refatorado para o novo fluxo de múltiplos talhões.
  List<GeneratedPoint> generateMultiTalhaoSamplePoints({
    required List<ImportedPolygonFeature> importedFeatures,
    required double hectaresPerSample,
  }) {
    if (hectaresPerSample <= 0 || importedFeatures.isEmpty) return [];

    final allPoints = importedFeatures.expand((f) => f.polygon.points).toList();
    if (allPoints.isEmpty) return [];
    
    final bounds = LatLngBounds.fromPoints(allPoints);
    final double minLat = bounds.south;
    final double maxLat = bounds.north;
    final double minLon = bounds.west;
    final double maxLon = bounds.east;

    final double centerLatRad = ((minLat + maxLat) / 2) * (pi / 180.0);
    
    final double spacingInMeters = sqrt(hectaresPerSample * 10000);
    final double latStep = spacingInMeters / 111132.0;
    final double lonStep = spacingInMeters / (111320.0 * cos(centerLatRad));

    final List<GeneratedPoint> validSamplePoints = [];

    for (double lat = minLat; lat <= maxLat; lat += latStep) {
      for (double lon = minLon; lon <= maxLon; lon += lonStep) {
        final gridPoint = LatLng(lat, lon);
        
        for (final feature in importedFeatures) {
          if (_isPointInPolygon(gridPoint, feature.polygon.points)) {
            validSamplePoints.add(GeneratedPoint(
              position: gridPoint,
              properties: feature.properties,
            ));
            break; 
          }
        }
      }
    }

    return validSamplePoints;
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygonVertices) {
    if (polygonVertices.isEmpty) return false;
    
    int intersections = 0;
    for (int i = 0; i < polygonVertices.length; i++) {
      LatLng p1 = polygonVertices[i];
      LatLng p2 = polygonVertices[(i + 1) % polygonVertices.length];

      if ((p1.latitude > point.latitude) != (p2.latitude > point.latitude)) {
        double atX = (p2.longitude - p1.longitude) * (point.latitude - p1.latitude) / (p2.latitude - p1.latitude) + p1.longitude;
        if (point.longitude < atX) {
          intersections++;
        }
      }
    }
    return intersections % 2 == 1;
  }
}
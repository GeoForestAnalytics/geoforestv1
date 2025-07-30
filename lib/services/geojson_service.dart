// lib/services/geojson_service.dart (VERSÃO COMPLETA E CORRIGIDA)

import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // Import necessário para TextStyle
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geoforestv1/models/imported_feature_model.dart';

// Classe de exceção personalizada para nos dar erros claros.
class GeoJsonParseException implements Exception {
  final String message;
  GeoJsonParseException(this.message);

  @override
  String toString() => message;
}

class GeoJsonService {

  // Função para selecionar o arquivo, agora com permissões robustas.
  Future<File?> _pickFile() async {
    if (Platform.isAndroid) {
      // Para Android 11+, precisamos da permissão para gerenciar todos os arquivos.
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
      }
      if (!status.isGranted) {
        // Se a permissão for negada, lançamos um erro claro.
        throw GeoJsonParseException("Permissão de acesso aos arquivos foi negada. Por favor, conceda a permissão nas configurações do aplicativo.");
      }
    }

    // Usar FileType.any é mais confiável para evitar problemas com tipos customizados.
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);

    if (result == null || result.files.single.path == null) {
      debugPrint("Nenhum arquivo selecionado.");
      return null;
    }
    
    // Validação da extensão para garantir que o usuário selecionou o tipo correto.
    final filePath = result.files.single.path!;
    if (!filePath.toLowerCase().endsWith('.json') && !filePath.toLowerCase().endsWith('.geojson')) {
        throw GeoJsonParseException("Arquivo inválido. Por favor, selecione um arquivo .json ou .geojson.");
    }

    return File(filePath);
  }

  // Função para importar POLÍGONOS.
  Future<List<ImportedPolygonFeature>> importPolygons() async {
    final file = await _pickFile();
    if (file == null) return [];

    try {
      final fileContent = await file.readAsString();
      if (fileContent.isEmpty) return [];
      
      final geoJsonData = json.decode(fileContent);
      if (geoJsonData['features'] == null) {
          throw GeoJsonParseException("O arquivo não contém a chave 'features', verifique se é um GeoJSON válido.");
      }

      final List<ImportedPolygonFeature> importedPolygons = [];

      for (var feature in geoJsonData['features']) {
        final geometry = feature['geometry'];
        final properties = feature['properties'] as Map<String, dynamic>? ?? {};
        
        if (geometry != null && (geometry['type'] == 'Polygon' || geometry['type'] == 'MultiPolygon')) {
          
          void processPolygonCoordinates(List polygonCoords) {
              final List<LatLng> points = [];
              // Acessa o primeiro anel de coordenadas do polígono.
              for (var point in polygonCoords[0]) {
                if (point is List && point.length >= 2) {
                    points.add(LatLng(point[1].toDouble(), point[0].toDouble()));
                }
              }
              if (points.isNotEmpty) {
                importedPolygons.add(
                  ImportedPolygonFeature(
                    polygon: _createPolygon(points, properties),
                    properties: properties,
                  )
                );
              }
          }

          if (geometry['type'] == 'Polygon') {
             processPolygonCoordinates(geometry['coordinates']);
          } else if (geometry['type'] == 'MultiPolygon') {
            for (var singlePolygonCoords in geometry['coordinates']) {
              processPolygonCoordinates(singlePolygonCoords);
            }
          }
        }
      }
      return importedPolygons;
    } catch (e) {
      // Lança a exceção com detalhes, em vez de falhar silenciosamente.
      debugPrint("ERRO ao importar polígonos GeoJSON: $e");
      throw GeoJsonParseException('Falha ao processar o arquivo. Verifique o formato do GeoJSON. Detalhe: ${e.toString()}');
    }
  }
  
  // Função para importar PONTOS.
  Future<List<ImportedPointFeature>> importPoints() async {
    final file = await _pickFile();
    if (file == null) return [];

    try {
      final fileContent = await file.readAsString();
      if (fileContent.isEmpty) return [];
      
      final geoJsonData = json.decode(fileContent);
      if (geoJsonData['features'] == null) {
          throw GeoJsonParseException("O arquivo não contém a chave 'features', verifique se é um GeoJSON válido.");
      }

      final List<ImportedPointFeature> importedPoints = [];
      for (var feature in geoJsonData['features']) {
        final geometry = feature['geometry'];
        final properties = feature['properties'] as Map<String, dynamic>? ?? {};

        if (geometry != null && geometry['type'] == 'Point' && geometry['coordinates'] != null) {
           if (geometry['coordinates'] is List && geometry['coordinates'].length >= 2) {
             final position = LatLng(geometry['coordinates'][1].toDouble(), geometry['coordinates'][0].toDouble());
             importedPoints.add(ImportedPointFeature(position: position, properties: properties));
           }
        }
      }
      return importedPoints;
    } catch (e) {
       // Lança a exceção com detalhes.
      debugPrint("ERRO ao importar pontos GeoJSON: $e");
      throw GeoJsonParseException('Falha ao processar o arquivo. Verifique o formato do GeoJSON. Detalhe: ${e.toString()}');
    }
  }

  // Função auxiliar para criar os polígonos no mapa.
    Polygon _createPolygon(List<LatLng> points, Map<String, dynamic> properties) {
    final label = (properties['talhao_nome'] ?? properties['talhao_id'] ?? properties['talhao'])?.toString();
    return Polygon(
      points: points,
      color: const Color(0xFF617359).withAlpha(100), // A presença desta cor já garante o preenchimento
      borderColor: const Color(0xFF1D4433),
      borderStrokeWidth: 1.5,
      // isFilled: true, // <<< ESTA LINHA FOI REMOVIDA
      label: label,
      labelStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10),
    );
  }
}
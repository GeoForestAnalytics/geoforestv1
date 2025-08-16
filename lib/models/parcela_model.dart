// lib/models/parcela_model.dart (VERSÃO ATUALIZADA E CORRIGIDA)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

enum StatusParcela {
  pendente(Icons.pending_outlined, Colors.grey),
  emAndamento(Icons.edit_note_outlined, Colors.orange),
  concluida(Icons.check_circle_outline, Colors.green),
  exportada(Icons.cloud_done_outlined, Colors.blue);

  final IconData icone;
  final Color cor;
  
  const StatusParcela(this.icone, this.cor);
}

class Parcela {
  int? dbId;
  String uuid;
  int? talhaoId; 
  DateTime? dataColeta;
  
  final String? idFazenda;
  final String? nomeFazenda;
  final String? nomeTalhao;
  final String? nomeLider;
  final int? projetoId;
  final String? municipio;
  final String? estado;
  final String? atividadeTipo;

  final String idParcela;
  final double areaMetrosQuadrados;
  final String? observacao;
  final double? latitude;
  final double? longitude;
  StatusParcela status;
  bool exportada;
  bool isSynced;
  final double? largura;
  final double? comprimento;
  final double? raio;
  
  List<String> photoPaths;
  List<Arvore> arvores;
  final DateTime? lastModified;

  Parcela({
    this.dbId,
    String? uuid,
    required this.talhaoId,
    required this.idParcela,
    required this.areaMetrosQuadrados,
    this.idFazenda,
    this.nomeFazenda,
    this.nomeTalhao,
    this.observacao,
    this.latitude,
    this.longitude,
    this.dataColeta,
    this.status = StatusParcela.pendente,
    this.exportada = false,
    this.isSynced = false,
    this.largura,
    this.comprimento,
    this.raio,
    this.nomeLider,
    this.projetoId,
    this.municipio,
    this.estado,
    this.atividadeTipo,
    this.photoPaths = const [],
    this.arvores = const [],
    this.lastModified,
  }) : uuid = uuid ?? const Uuid().v4();

  Parcela copyWith({
    int? dbId,
    String? uuid,
    int? talhaoId,
    String? idFazenda,
    String? nomeFazenda,
    String? nomeTalhao,
    String? idParcela,
    double? areaMetrosQuadrados,
    String? observacao,
    double? latitude,
    double? longitude,
    DateTime? dataColeta,
    StatusParcela? status,
    bool? exportada,
    bool? isSynced,
    double? largura,
    double? comprimento,
    double? raio,
    String? nomeLider,
    int? projetoId,
    String? municipio,
    String? estado,
    String? atividadeTipo,
    List<String>? photoPaths,
    List<Arvore>? arvores,
    DateTime? lastModified,
  }) {
    return Parcela(
      dbId: dbId ?? this.dbId,
      uuid: uuid ?? this.uuid,
      talhaoId: talhaoId ?? this.talhaoId,
      idFazenda: idFazenda ?? this.idFazenda,
      nomeFazenda: nomeFazenda ?? this.nomeFazenda,
      nomeTalhao: nomeTalhao ?? this.nomeTalhao,
      idParcela: idParcela ?? this.idParcela,
      areaMetrosQuadrados: areaMetrosQuadrados ?? this.areaMetrosQuadrados,
      observacao: observacao ?? this.observacao,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      dataColeta: dataColeta ?? this.dataColeta,
      status: status ?? this.status,
      exportada: exportada ?? this.exportada,
      isSynced: isSynced ?? this.isSynced,
      largura: largura ?? this.largura,
      comprimento: comprimento ?? this.comprimento,
      raio: raio ?? this.raio,
      nomeLider: nomeLider ?? this.nomeLider,
      projetoId: projetoId ?? this.projetoId,
      municipio: municipio ?? this.municipio,
      estado: estado ?? this.estado,
      atividadeTipo: atividadeTipo ?? this.atividadeTipo,
      photoPaths: photoPaths ?? this.photoPaths,
      arvores: arvores ?? this.arvores,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': dbId,
      'uuid': uuid,
      'talhaoId': talhaoId,
      'idFazenda': idFazenda,
      'nomeFazenda': nomeFazenda,
      'nomeTalhao': nomeTalhao,
      'idParcela': idParcela,
      'areaMetrosQuadrados': areaMetrosQuadrados,
      'observacao': observacao,
      'latitude': latitude,
      'longitude': longitude,
      'dataColeta': dataColeta?.toIso8601String(),
      'status': status.name,
      'exportada': exportada ? 1 : 0,
      'isSynced': isSynced ? 1 : 0,
      'largura': largura,
      'comprimento': comprimento,
      'raio': raio,
      'nomeLider': nomeLider,
      'projetoId': projetoId,
      'municipio': municipio,
      'estado': estado,
      'photoPaths': jsonEncode(photoPaths),
      'lastModified': lastModified?.toIso8601String()
    };
  }

  factory Parcela.fromMap(Map<String, dynamic> map) {
    // <<< CORREÇÃO APLICADA AQUI >>>
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    List<String> paths = [];
    if (map['photoPaths'] != null) {
      try {
        paths = List<String>.from(jsonDecode(map['photoPaths']));
      } catch (e) {
        debugPrint("Erro ao decodificar photoPaths: $e");
      }
    }

    return Parcela(
      dbId: map['id'],
      uuid: map['uuid'] ?? const Uuid().v4(),
      talhaoId: map['talhaoId'],
      idFazenda: map['idFazenda'],
      nomeFazenda: map['nomeFazenda'],
      nomeTalhao: map['nomeTalhao'],
      idParcela: map['idParcela'] ?? 'ID_N/A',
      areaMetrosQuadrados: (map['areaMetrosQuadrados'] as num?)?.toDouble() ?? 0.0,
      observacao: map['observacao'],
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      dataColeta: parseDate(map['dataColeta']),
      status: StatusParcela.values.firstWhere(
            (e) => e.name == map['status'],
        orElse: () => StatusParcela.pendente,
      ),
      exportada: map['exportada'] == 1,
      isSynced: map['isSynced'] == 1,
      largura: (map['largura'] as num?)?.toDouble(),
      comprimento: (map['comprimento'] as num?)?.toDouble(),
      raio: (map['raio'] as num?)?.toDouble(),
      nomeLider: map['nomeLider'],
      projetoId: map['projetoId'],
      atividadeTipo: map['atividadeTipo'],
      photoPaths: paths,
      lastModified: parseDate(map['lastModified']),
    );
  }
}
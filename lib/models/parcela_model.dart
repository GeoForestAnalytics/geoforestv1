// lib/models/parcela_model.dart (VERSÃO CORRIGIDA E COMPLETA)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geoforestv1/models/arvore_model.dart';
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
  final int? projetoId;    // <<< CAMPO ADICIONADO PARA CORRIGIR O FILTRO

  // Campos principais
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
    this.projetoId, // <<< ADICIONADO AO CONSTRUTOR
    this.photoPaths = const [],
    this.arvores = const [],
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
    int? projetoId, // <<< ADICIONADO AO COPYWITH
    List<String>? photoPaths,
    List<Arvore>? arvores,
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
      projetoId: projetoId ?? this.projetoId, // <<< ADICIONADO AO COPYWITH
      photoPaths: photoPaths ?? this.photoPaths,
      arvores: arvores ?? this.arvores,
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
      'projetoId': projetoId, // <<< ADICIONADO AO MAP
      'photoPaths': jsonEncode(photoPaths),
    };
  }

  factory Parcela.fromMap(Map<String, dynamic> map) {
    List<String> paths = [];
    if (map['photoPaths'] != null) {
      try {
        paths = List<String>.from(jsonDecode(map['photoPaths']));
      } catch (e) {
        print("Erro ao decodificar photoPaths: $e");
      }
    }

    return Parcela(
      dbId: map['id'],
      uuid: map['uuid'],
      talhaoId: map['talhaoId'],
      idFazenda: map['idFazenda'],
      nomeFazenda: map['nomeFazenda'],
      nomeTalhao: map['nomeTalhao'],
      idParcela: map['idParcela'],
      areaMetrosQuadrados: map['areaMetrosQuadrados'],
      observacao: map['observacao'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      dataColeta: map['dataColeta'] != null ? DateTime.parse(map['dataColeta']) : null,
      status: StatusParcela.values.firstWhere(
            (e) => e.name == map['status'],
        orElse: () => StatusParcela.pendente,
      ),
      exportada: map['exportada'] == 1,
      isSynced: map['isSynced'] == 1,
      largura: map['largura'],
      comprimento: map['comprimento'],
      raio: map['raio'],
      nomeLider: map['nomeLider'],
      projetoId: map['projetoId'], // <<< LÊ O ID DO PROJETO DO MAPA
      photoPaths: paths,
    );
  }
}
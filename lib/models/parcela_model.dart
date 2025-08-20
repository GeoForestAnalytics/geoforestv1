// lib/models/parcela_model.dart (VERSÃO ATUALIZADA PARA EXPORTAÇÃO)

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
  final String? up;
  
  // <<< CAMPOS NOVOS PARA EXPORTAÇÃO >>>
  final String? referenciaRf;
  final String? ciclo;
  final int? rotacao;
  final String? tipoParcela; // Ex: "Instalação"
  final String? formaParcela; // Ex: "Retangular"
  final double? lado1; // Largura ou Raio
  final double? lado2; // Comprimento

  final String idParcela;
  final double areaMetrosQuadrados;
  final String? observacao;
  final double? latitude;
  final double? longitude;
  StatusParcela status;
  bool exportada;
  bool isSynced;
  
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
    this.nomeLider,
    this.projetoId,
    this.municipio,
    this.estado,
    this.atividadeTipo,
    this.up,
    this.referenciaRf,
    this.ciclo,
    this.rotacao,
    this.tipoParcela,
    this.formaParcela,
    this.lado1,
    this.lado2,
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
    String? nomeLider,
    int? projetoId,
    String? municipio,
    String? estado,
    String? atividadeTipo,
    String? up,
    String? referenciaRf,
    String? ciclo,
    int? rotacao,
    String? tipoParcela,
    String? formaParcela,
    double? lado1,
    double? lado2,
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
      nomeLider: nomeLider ?? this.nomeLider,
      projetoId: projetoId ?? this.projetoId,
      municipio: municipio ?? this.municipio,
      estado: estado ?? this.estado,
      atividadeTipo: atividadeTipo ?? this.atividadeTipo,
      up: up ?? this.up,
      referenciaRf: referenciaRf ?? this.referenciaRf,
      ciclo: ciclo ?? this.ciclo,
      rotacao: rotacao ?? this.rotacao,
      tipoParcela: tipoParcela ?? this.tipoParcela,
      formaParcela: formaParcela ?? this.formaParcela,
      lado1: lado1 ?? this.lado1,
      lado2: lado2 ?? this.lado2,
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
      'nomeLider': nomeLider,
      'projetoId': projetoId,
      'municipio': municipio,
      'estado': estado,
      'up': up,
      'referencia_rf': referenciaRf,
      'ciclo': ciclo,
      'rotacao': rotacao,
      'tipo_parcela': tipoParcela,
      'forma_parcela': formaParcela,
      'lado1': lado1,
      'lado2': lado2,
      'photoPaths': jsonEncode(photoPaths),
      'lastModified': lastModified?.toIso8601String()
    };
  }

  factory Parcela.fromMap(Map<String, dynamic> map) {
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
      nomeLider: map['nomeLider'],
      projetoId: map['projetoId'],
      atividadeTipo: map['atividadeTipo'],
      up: map['up'],
      referenciaRf: map['referencia_rf'],
      ciclo: map['ciclo'],
      rotacao: map['rotacao'],
      tipoParcela: map['tipo_parcela'],
      formaParcela: map['forma_parcela'],
      lado1: (map['lado1'] as num?)?.toDouble(),
      lado2: (map['lado2'] as num?)?.toDouble(),
      photoPaths: paths,
      lastModified: parseDate(map['lastModified']),
    );
  }
}
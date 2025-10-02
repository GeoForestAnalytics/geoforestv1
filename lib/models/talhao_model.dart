// lib/models/talhao_model.dart (VERSÃO REFATORADA)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';

class Talhao {
  final int? id;
  final String fazendaId; 
  final int fazendaAtividadeId;
  final int? projetoId;
  final String nome;
  final double? areaHa;
  final double? idadeAnos;
  final String? especie;
  final String? espacamento;
  final String? fazendaNome;
  final String? municipio;
  final String? estado;
  double? volumeTotalTalhao;
  final DateTime? lastModified;
  final String? bloco;
  final String? up;
  final String? materialGenetico;
  final String? dataPlantio;

  Talhao({
    this.id, required this.fazendaId, required this.fazendaAtividadeId,
    this.projetoId, required this.nome, this.areaHa, this.idadeAnos,
    this.especie, this.espacamento, this.fazendaNome, this.municipio,
    this.estado, this.volumeTotalTalhao, this.lastModified, this.bloco,
    this.up, this.materialGenetico, this.dataPlantio,
  });

  Talhao copyWith({
    int? id, String? fazendaId, int? fazendaAtividadeId, int? projetoId, String? nome,
    double? areaHa, double? idadeAnos, String? especie, String? espacamento, String? fazendaNome,
    String? municipio, String? estado, double? volumeTotalTalhao, DateTime? lastModified,
    String? bloco, String? up, String? materialGenetico, String? dataPlantio,
  }) {
    return Talhao(
      id: id ?? this.id, fazendaId: fazendaId ?? this.fazendaId,
      fazendaAtividadeId: fazendaAtividadeId ?? this.fazendaAtividadeId,
      projetoId: projetoId ?? this.projetoId, nome: nome ?? this.nome,
      areaHa: areaHa ?? this.areaHa, idadeAnos: idadeAnos ?? this.idadeAnos,
      especie: especie ?? this.especie, espacamento: espacamento ?? this.espacamento,
      fazendaNome: fazendaNome ?? this.fazendaNome, municipio: municipio ?? this.municipio,
      estado: estado ?? this.estado, volumeTotalTalhao: volumeTotalTalhao ?? this.volumeTotalTalhao,
      lastModified: lastModified ?? this.lastModified, bloco: bloco ?? this.bloco,
      up: up ?? this.up, materialGenetico: materialGenetico ?? this.materialGenetico,
      dataPlantio: dataPlantio ?? this.dataPlantio,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      DbTalhoes.id: id,
      DbTalhoes.fazendaId: fazendaId,
      DbTalhoes.fazendaAtividadeId: fazendaAtividadeId,
      DbTalhoes.projetoId: projetoId,
      DbTalhoes.nome: nome,
      DbTalhoes.areaHa: areaHa,
      DbTalhoes.idadeAnos: idadeAnos,
      DbTalhoes.especie: especie,
      DbTalhoes.espacamento: espacamento,
      DbTalhoes.bloco: bloco,
      DbTalhoes.up: up,
      DbTalhoes.materialGenetico: materialGenetico,
      DbTalhoes.dataPlantio: dataPlantio,
      DbTalhoes.lastModified: lastModified?.toIso8601String(), 
    };
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      DbTalhoes.id: id,
      DbTalhoes.fazendaId: fazendaId,
      DbTalhoes.fazendaAtividadeId: fazendaAtividadeId,
      DbTalhoes.nome: nome,
      DbTalhoes.areaHa: areaHa,
      DbTalhoes.idadeAnos: idadeAnos,
      DbTalhoes.especie: especie,
      DbTalhoes.espacamento: espacamento,
      DbTalhoes.bloco: bloco,
      DbTalhoes.up: up,
      DbTalhoes.materialGenetico: materialGenetico,
      DbTalhoes.dataPlantio: dataPlantio,
    };
  }
  
  factory Talhao.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return Talhao(
      id: map[DbTalhoes.id],
      fazendaId: map[DbTalhoes.fazendaId],
      fazendaAtividadeId: map[DbTalhoes.fazendaAtividadeId],
      projetoId: map[DbTalhoes.projetoId],
      nome: map[DbTalhoes.nome],
      areaHa: (map[DbTalhoes.areaHa] as num?)?.toDouble(),
      idadeAnos: (map[DbTalhoes.idadeAnos] as num?)?.toDouble(),
      especie: map[DbTalhoes.especie],
      espacamento: map[DbTalhoes.espacamento],
      fazendaNome: map['fazendaNome'], // Este vem de um JOIN, não tem constante
      municipio: map['municipio'],   // Este vem de um JOIN, não tem constante
      estado: map['estado'],         // Este vem de um JOIN, não tem constante
      bloco: map[DbTalhoes.bloco],
      up: map[DbTalhoes.up],
      materialGenetico: map[DbTalhoes.materialGenetico],
      dataPlantio: map[DbTalhoes.dataPlantio],
      lastModified: parseDate(map[DbTalhoes.lastModified]),
    );
  }
}
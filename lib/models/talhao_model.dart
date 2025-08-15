// lib/models/talhao_model.dart (VERSÃO CORRIGIDA E FINAL)
import 'package:cloud_firestore/cloud_firestore.dart';

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

  Talhao({
    this.id,
    required this.fazendaId,
    required this.fazendaAtividadeId,
    this.projetoId,
    required this.nome,
    this.areaHa,
    this.idadeAnos,
    this.especie,
    this.espacamento,
    this.fazendaNome,
    this.municipio,
    this.estado,
    this.volumeTotalTalhao,
    this.lastModified,
  });

  Talhao copyWith({
    int? id,
    String? fazendaId,
    int? fazendaAtividadeId,
    int? projetoId,
    String? nome,
    double? areaHa,
    double? idadeAnos,
    String? especie,
    String? espacamento,
    String? fazendaNome,
    String? municipio,
    String? estado,
    double? volumeTotalTalhao,
    DateTime? lastModified,
  }) {
    return Talhao(
      id: id ?? this.id,
      fazendaId: fazendaId ?? this.fazendaId,
      fazendaAtividadeId: fazendaAtividadeId ?? this.fazendaAtividadeId,
      projetoId: projetoId ?? this.projetoId,
      nome: nome ?? this.nome,
      areaHa: areaHa ?? this.areaHa,
      idadeAnos: idadeAnos ?? this.idadeAnos,
      especie: especie ?? this.especie,
      espacamento: espacamento ?? this.espacamento,
      fazendaNome: fazendaNome ?? this.fazendaNome,
      municipio: municipio ?? this.municipio,
      estado: estado ?? this.estado,
      volumeTotalTalhao: volumeTotalTalhao ?? this.volumeTotalTalhao,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  // toMap para o BANCO DE DADOS LOCAL. Ele precisa do projetoId.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fazendaId': fazendaId,
      'fazendaAtividadeId': fazendaAtividadeId,
      'projetoId': projetoId, // <<< CORREÇÃO CRÍTICA AQUI
      'nome': nome,
      'areaHa': areaHa,
      'idadeAnos': idadeAnos,
      'especie': especie,
      'espacamento': espacamento,
      'lastModified': lastModified?.toIso8601String(), 
    };
  }

  // toMap para o FIRESTORE. Não deve ter o projetoId.
  Map<String, dynamic> toFirestoreMap() {
    return {
      'id': id,
      'fazendaId': fazendaId,
      'fazendaAtividadeId': fazendaAtividadeId,
      'nome': nome,
      'areaHa': areaHa,
      'idadeAnos': idadeAnos,
      'especie': especie,
      'espacamento': espacamento,
    };
  }
  
  factory Talhao.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return Talhao(
      id: map['id'],
      fazendaId: map['fazendaId'],
      fazendaAtividadeId: map['fazendaAtividadeId'],
      projetoId: map['projetoId'],
      nome: map['nome'],
      areaHa: map['areaHa'],
      idadeAnos: map['idadeAnos'],
      especie: map['especie'],
      espacamento: map['espacamento'],
      fazendaNome: map['fazendaNome'],
      municipio: map['municipio'],
      estado: map['estado'],
      lastModified: parseDate(map['lastModified']),
    );
  }
}
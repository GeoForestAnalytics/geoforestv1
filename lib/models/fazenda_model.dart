// lib/models/fazenda_model.dart (VERSÃO FINAL E CORRIGIDA)
import 'package:cloud_firestore/cloud_firestore.dart';

class Fazenda {
  final String id; 
  final int atividadeId;
  final String nome;
  final String municipio;
  final String estado;
  final DateTime? lastModified;

  Fazenda({
    required this.id,
    required this.atividadeId,
    required this.nome,
    required this.municipio,
    required this.estado,
    this.lastModified,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'atividadeId': atividadeId,
      'nome': nome,
      'municipio': municipio,
      'estado': estado,
      'lastModified': lastModified?.toIso8601String(),
    };
  }

  factory Fazenda.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return Fazenda(
      id: map['id'],
      atividadeId: map['atividadeId'],
      nome: map['nome'],
      municipio: map['municipio'],
      estado: map['estado'],
      lastModified: parseDate(map['lastModified']),
    );
  }
}
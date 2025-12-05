// lib/models/fazenda_model.dart (VERSÃO REFATORADA)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';

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
      DbFazendas.id: id,
      DbFazendas.atividadeId: atividadeId,
      DbFazendas.nome: nome,
      DbFazendas.municipio: municipio,
      DbFazendas.estado: estado,
      DbFazendas.lastModified: lastModified?.toIso8601String(),
    };
  }

  factory Fazenda.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return Fazenda(
      id: map[DbFazendas.id],
      atividadeId: map[DbFazendas.atividadeId],
      // ⬇️ ALTERAÇÃO AQUI: Proteção contra NULL
      nome: map[DbFazendas.nome] ?? 'Fazenda Sem Nome',
      municipio: map[DbFazendas.municipio] ?? 'N/I', // N/I = Não Informado
      estado: map[DbFazendas.estado] ?? 'UF',
      lastModified: parseDate(map[DbFazendas.lastModified]),
    );
  }
}
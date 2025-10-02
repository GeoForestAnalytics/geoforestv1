// lib/models/atividade_model.dart (VERSÃO REFATORADA)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';

enum TipoAtividade {
  ipc("Inventário Pré-Corte"),
  ifc("Inventário Florestal Contínuo"),
  cub("Cubagem Rigorosa"),
  aud("Auditoria"),
  ifq6("IFQ - 6 Meses"),
  ifq12("IFQ - 12 Meses"),
  ifs("Inventário de Sobrevivência e Qualidade"),
  bio("Inventario Biomassa");
  const TipoAtividade(this.descricao);
  final String descricao;
}

class Atividade {
  final int? id;
  final int projetoId;
  final String tipo;
  final String descricao;
  final DateTime dataCriacao;
  final String? metodoCubagem;
  final DateTime? lastModified;

  Atividade({
    this.id, required this.projetoId, required this.tipo,
    required this.descricao, required this.dataCriacao,
    this.metodoCubagem, this.lastModified,
  });

  Atividade copyWith({
    int? id, int? projetoId, String? tipo, String? descricao,
    DateTime? dataCriacao, String? metodoCubagem, DateTime? lastModified,
  }) {
    return Atividade(
      id: id ?? this.id, projetoId: projetoId ?? this.projetoId,
      tipo: tipo ?? this.tipo, descricao: descricao ?? this.descricao,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      metodoCubagem: metodoCubagem ?? this.metodoCubagem,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      DbAtividades.id: id,
      DbAtividades.projetoId: projetoId,
      DbAtividades.tipo: tipo,
      DbAtividades.descricao: descricao,
      DbAtividades.dataCriacao: dataCriacao.toIso8601String(),
      DbAtividades.metodoCubagem: metodoCubagem,
      DbAtividades.lastModified: lastModified?.toIso8601String(),
    };
  }

  factory Atividade.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    final dataCriacao = parseDate(map[DbAtividades.dataCriacao]);
    if (dataCriacao == null) {
      throw FormatException("Formato de data inválido para 'dataCriacao' na Atividade ${map[DbAtividades.id]}");
    }

    return Atividade(
      id: map[DbAtividades.id],
      projetoId: map[DbAtividades.projetoId],
      tipo: map[DbAtividades.tipo],
      descricao: map[DbAtividades.descricao],
      dataCriacao: dataCriacao,
      metodoCubagem: map[DbAtividades.metodoCubagem],
      lastModified: parseDate(map[DbAtividades.lastModified]),
    );
  }
}
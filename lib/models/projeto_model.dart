// lib/models/projeto_model.dart (VERSÃO REFATORADA)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';

class Projeto {
  final String? licenseId;
  final int? id;
  final String nome;
  final String empresa;
  final String responsavel;
  final DateTime dataCriacao;
  final String status;
  final String? delegadoPorLicenseId;
  final DateTime? lastModified;

  Projeto({
    this.id, this.licenseId, required this.nome, required this.empresa,
    required this.responsavel, required this.dataCriacao,
    this.status = 'ativo', this.delegadoPorLicenseId, this.lastModified,
  });

  Projeto copyWith({
    int? id, String? licenseId, String? nome, String? empresa,
    String? responsavel, DateTime? dataCriacao, String? status,
    String? delegadoPorLicenseId, DateTime? lastModified,
  }) {
    return Projeto(
      id: id ?? this.id, licenseId: licenseId ?? this.licenseId,
      nome: nome ?? this.nome, empresa: empresa ?? this.empresa,
      responsavel: responsavel ?? this.responsavel,
      dataCriacao: dataCriacao ?? this.dataCriacao, status: status ?? this.status,
      delegadoPorLicenseId: delegadoPorLicenseId ?? this.delegadoPorLicenseId,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      DbProjetos.id: id,
      DbProjetos.licenseId: licenseId,
      DbProjetos.nome: nome,
      DbProjetos.empresa: empresa,
      DbProjetos.responsavel: responsavel,
      DbProjetos.dataCriacao: dataCriacao.toIso8601String(),
      DbProjetos.status: status,
      DbProjetos.delegadoPorLicenseId: delegadoPorLicenseId,
      DbProjetos.lastModified: lastModified?.toIso8601String(),
    };
  }

  factory Projeto.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    final dataCriacao = parseDate(map[DbProjetos.dataCriacao]);
    if (dataCriacao == null) {
      throw FormatException("Formato de data inválido para 'dataCriacao' no Projeto ${map[DbProjetos.id]}");
    }

    return Projeto(
      id: map[DbProjetos.id],
      licenseId: map[DbProjetos.licenseId],
      nome: map[DbProjetos.nome],
      empresa: map[DbProjetos.empresa],
      responsavel: map[DbProjetos.responsavel],
      dataCriacao: dataCriacao,
      status: map[DbProjetos.status] ?? 'ativo',
      delegadoPorLicenseId: map[DbProjetos.delegadoPorLicenseId],
      lastModified: parseDate(map[DbProjetos.lastModified]),
    );
  }
}
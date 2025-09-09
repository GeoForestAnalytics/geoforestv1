// lib/models/projeto_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Projeto {
  final String? licenseId;
  final int? id;
  final String nome;
  final String empresa;
  final String responsavel;
  final DateTime dataCriacao;
  final String status;
  final String? delegadoPorLicenseId; // <-- NOVO CAMPO
  final DateTime? lastModified;

  Projeto({
    this.id,
    this.licenseId,
    required this.nome,
    required this.empresa,
    required this.responsavel,
    required this.dataCriacao,
    this.status = 'ativo',
    this.delegadoPorLicenseId, // <-- NOVO CAMPO
    this.lastModified,
  });

  Projeto copyWith({
    int? id,
    String? licenseId,
    String? nome,
    String? empresa,
    String? responsavel,
    DateTime? dataCriacao,
    String? status,
    String? delegadoPorLicenseId, // <-- NOVO CAMPO
    DateTime? lastModified,
  }) {
    return Projeto(
      id: id ?? this.id,
      licenseId: licenseId ?? this.licenseId,
      nome: nome ?? this.nome,
      empresa: empresa ?? this.empresa,
      responsavel: responsavel ?? this.responsavel,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      status: status ?? this.status,
      delegadoPorLicenseId: delegadoPorLicenseId ?? this.delegadoPorLicenseId, // <-- NOVO CAMPO
      lastModified: lastModified ?? this.lastModified,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'licenseId': licenseId,
      'nome': nome,
      'empresa': empresa,
      'responsavel': responsavel,
      'dataCriacao': dataCriacao.toIso8601String(),
      'status': status,
      'delegado_por_license_id': delegadoPorLicenseId, // <-- NOVO CAMPO
      'lastModified': lastModified?.toIso8601String(),
    };
  }

  factory Projeto.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      } else if (value is String) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    final dataCriacao = parseDate(map['dataCriacao']);
    if (dataCriacao == null) {
      throw FormatException("Formato de data inválido para 'dataCriacao' no Projeto ${map['id']}");
    }

    return Projeto(
      id: map['id'],
      licenseId: map['licenseId'],
      nome: map['nome'],
      empresa: map['empresa'],
      responsavel: map['responsavel'],
      dataCriacao: dataCriacao,
      status: map['status'] ?? 'ativo',
      delegadoPorLicenseId: map['delegado_por_license_id'], // <-- NOVO CAMPO
      lastModified: parseDate(map['lastModified']),
    );
  }
}
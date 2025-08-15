// lib/models/projeto_model.dart (VERSÃO FINAL E CORRIGIDA)

import 'package:cloud_firestore/cloud_firestore.dart';

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
    this.id,
    this.licenseId,
    required this.nome,
    required this.empresa,
    required this.responsavel,
    required this.dataCriacao,
    this.status = 'ativo',
    this.delegadoPorLicenseId,
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
    String? delegadoPorLicenseId,
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
      delegadoPorLicenseId: delegadoPorLicenseId ?? this.delegadoPorLicenseId,
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
      'delegado_por_license_id': delegadoPorLicenseId,
      'lastModified': lastModified?.toIso8601String(),
    };
  }

  factory Projeto.fromMap(Map<String, dynamic> map) {
    // <<< INÍCIO DA CORREÇÃO >>>
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      } else if (value is String) {
        return DateTime.tryParse(value);
      }
      return null;
    }
    // <<< FIM DA CORREÇÃO >>>

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
      delegadoPorLicenseId: map['delegado_por_license_id'],
      lastModified: parseDate(map['lastModified']),
    );
  }
}
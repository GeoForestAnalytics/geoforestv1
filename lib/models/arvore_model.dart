// lib/models/arvore_model.dart (VERSÃO ATUALIZADA E CORRIGIDA)

import 'package:cloud_firestore/cloud_firestore.dart'; // <<< PASSO 1: IMPORTAR CLOUD_FIRESTORE

enum Codigo {
  normal, falha, bifurcada, multipla, quebrada, morta, caida,
  ataquemacaco, regenaracao, inclinada, fogo, formiga, outro
}

enum Codigo2 {
  bifurcada, multipla, quebrada, morta, caida, ataquemacaco,
  regenaracao, inclinada, fogo, formiga, outro
}

class Arvore {
  int? id;
  final double cap;
  final double? altura;
  final int linha;
  final int posicaoNaLinha;
  final bool fimDeLinha;
  bool dominante;
  final Codigo codigo;
  final Codigo2? codigo2;
  final double? capAuditoria;
  final double? alturaAuditoria;
  double? volume;
  final DateTime? lastModified;

  Arvore({
    this.id,
    required this.cap,
    this.altura,
    required this.linha,
    required this.posicaoNaLinha,
    this.fimDeLinha = false,
    this.dominante = false,
    required this.codigo,
    this.codigo2,
    this.capAuditoria,
    this.alturaAuditoria,
    this.volume,
    this.lastModified,
  });

  Arvore copyWith({
    int? id,
    double? cap,
    double? altura,
    int? linha,
    int? posicaoNaLinha,
    bool? fimDeLinha,
    bool? dominante,
    Codigo? codigo,
    Codigo2? codigo2,
    double? capAuditoria,
    double? alturaAuditoria,
    double? volume,
    DateTime? lastModified,
  }) {
    return Arvore(
      id: id ?? this.id,
      cap: cap ?? this.cap,
      altura: altura ?? this.altura,
      linha: linha ?? this.linha,
      posicaoNaLinha: posicaoNaLinha ?? this.posicaoNaLinha,
      fimDeLinha: fimDeLinha ?? this.fimDeLinha,
      dominante: dominante ?? this.dominante,
      codigo: codigo ?? this.codigo,
      codigo2: codigo2 ?? this.codigo2,
      capAuditoria: capAuditoria ?? this.capAuditoria,
      alturaAuditoria: alturaAuditoria ?? this.alturaAuditoria,
      volume: volume ?? this.volume,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cap': cap,
      'altura': altura,
      'linha': linha,
      'posicaoNaLinha': posicaoNaLinha,
      'fimDeLinha': fimDeLinha ? 1 : 0,
      'dominante': dominante ? 1 : 0,
      'codigo': codigo.name,
      'codigo2': codigo2?.name,
      'capAuditoria': capAuditoria,
      'alturaAuditoria': alturaAuditoria,
      'lastModified': lastModified?.toIso8601String(),
    };
  }

  factory Arvore.fromMap(Map<String, dynamic> map) {
    // <<< PASSO 2: ADICIONAR FUNÇÃO AUXILIAR PARA PARSE DE DATAS >>>
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      } else if (value is String) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    return Arvore(
      id: map['id'],
      cap: map['cap']?.toDouble() ?? 0.0,
      altura: map['altura']?.toDouble(),
      linha: map['linha'] ?? 0,
      posicaoNaLinha: map['posicaoNaLinha'] ?? 0,
      fimDeLinha: map['fimDeLinha'] == 1,
      dominante: map['dominante'] == 1,
      codigo: Codigo.values.firstWhere((e) => e.name == map['codigo'], orElse: () => Codigo.normal),
      codigo2: map['codigo2'] != null ? Codigo2.values.firstWhere((e) => e.name == map['codigo2']) : null,
      capAuditoria: map['capAuditoria']?.toDouble(),
      alturaAuditoria: map['alturaAuditoria']?.toDouble(),
      // <<< PASSO 3: USAR A FUNÇÃO AUXILIAR NO CAMPO 'lastModified' >>>
      lastModified: parseDate(map['lastModified']),
    );
  }
}
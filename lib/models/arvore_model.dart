// lib/models/arvore_model.dart (VERSÃO ATUALIZADA PARA EXPORTAÇÃO)

import 'package:cloud_firestore/cloud_firestore.dart';


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
  final String? codigo3; // <<< CAMPO NOVO
  final int? tora;       // <<< CAMPO NOVO
  final double? capAuditoria;
  final double? alturaAuditoria;
  double? volume;
  final DateTime? lastModified;
  final double? alturaDano;

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
    this.codigo3, // <<< CAMPO NOVO
    this.tora,    // <<< CAMPO NOVO
    this.capAuditoria,
    this.alturaAuditoria,
    this.volume,
    this.lastModified,
    this.alturaDano,
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
    String? codigo3, // <<< CAMPO NOVO
    int? tora,       // <<< CAMPO NOVO
    double? capAuditoria,
    double? alturaAuditoria,
    double? volume,
    DateTime? lastModified,
    double? alturaDano,
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
      codigo3: codigo3 ?? this.codigo3, // <<< CAMPO NOVO
      tora: tora ?? this.tora,          // <<< CAMPO NOVO
      capAuditoria: capAuditoria ?? this.capAuditoria,
      alturaAuditoria: alturaAuditoria ?? this.alturaAuditoria,
      volume: volume ?? this.volume,
      lastModified: lastModified ?? this.lastModified,
      alturaDano: alturaDano ?? this.alturaDano,
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
      'codigo3': codigo3, // <<< CAMPO NOVO
      'tora': tora,       // <<< CAMPO NOVO
      'capAuditoria': capAuditoria,
      'alturaAuditoria': alturaAuditoria,
      'alturaDano': alturaDano,
      'lastModified': lastModified?.toIso8601String(),
    };
  }

  factory Arvore.fromMap(Map<String, dynamic> map) {
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
      codigo2: Codigo2.values.asNameMap()[map['codigo2'] as String?],
      codigo3: map['codigo3'], // <<< CAMPO NOVO
      tora: map['tora'],       // <<< CAMPO NOVO
      capAuditoria: map['capAuditoria']?.toDouble(),
      alturaAuditoria: map['alturaAuditoria']?.toDouble(),
      alturaDano: map['alturaDano']?.toDouble(),
      lastModified: parseDate(map['lastModified']),
    );
  }
}
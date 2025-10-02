// lib/models/arvore_model.dart (VERSÃO REFATORADA)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';

enum Codigo {
  Normal, Falha, Bifurcada, Multipla, Quebrada, Caida, Dominada, Geada, Fogo,
  PragasOuDoencas, AtaqueMacaco, VespaMadeira, MortaOuSeca, PonteiraSeca,
  Rebrota, AtaqueFormiga, Torta, FoxTail, Inclinada, DeitadaVento, FeridaBase,
  CaidaRaizVento, Resinado, Outro
}

enum Codigo2 {
  Bifurcada, Multipla, Quebrada, Geada, Fogo, PragasOuDoencas, AtaqueMacaco,
  VespaMadeira, MortaOuSeca, PonteiraSeca, Rebrota, AtaqueFormiga, Torta,
  FoxTail, Inclinada, DeitadaVento, FeridaBase, Resinado, Outro
}

class Arvore {
  int? id;
  final double cap;
  final double? altura;
  final double? alturaDano;
  final int linha;
  final int posicaoNaLinha;
  final bool fimDeLinha;
  bool dominante;
  final Codigo codigo;
  final Codigo2? codigo2;
  final String? codigo3;
  final int? tora;
  final double? capAuditoria;
  final double? alturaAuditoria;
  double? volume;
  final DateTime? lastModified;

  Arvore({
    this.id, required this.cap, this.altura, this.alturaDano, required this.linha,
    required this.posicaoNaLinha, this.fimDeLinha = false, this.dominante = false,
    required this.codigo, this.codigo2, this.codigo3, this.tora,
    this.capAuditoria, this.alturaAuditoria, this.volume, this.lastModified,
  });

  Arvore copyWith({
    int? id, double? cap, double? altura, double? alturaDano, int? linha,
    int? posicaoNaLinha, bool? fimDeLinha, bool? dominante, Codigo? codigo,
    Codigo2? codigo2, String? codigo3, int? tora, double? capAuditoria,
    double? alturaAuditoria, double? volume, DateTime? lastModified,
  }) {
    return Arvore(
      id: id ?? this.id, cap: cap ?? this.cap, altura: altura ?? this.altura,
      alturaDano: alturaDano ?? this.alturaDano, linha: linha ?? this.linha,
      posicaoNaLinha: posicaoNaLinha ?? this.posicaoNaLinha,
      fimDeLinha: fimDeLinha ?? this.fimDeLinha, dominante: dominante ?? this.dominante,
      codigo: codigo ?? this.codigo, codigo2: codigo2 ?? this.codigo2,
      codigo3: codigo3 ?? this.codigo3, tora: tora ?? this.tora,
      capAuditoria: capAuditoria ?? this.capAuditoria,
      alturaAuditoria: alturaAuditoria ?? this.alturaAuditoria,
      volume: volume ?? this.volume, lastModified: lastModified ?? this.lastModified,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      DbArvores.id: id,
      DbArvores.cap: cap,
      DbArvores.altura: altura,
      DbArvores.alturaDano: alturaDano,
      DbArvores.linha: linha,
      DbArvores.posicaoNaLinha: posicaoNaLinha,
      DbArvores.fimDeLinha: fimDeLinha ? 1 : 0,
      DbArvores.dominante: dominante ? 1 : 0,
      DbArvores.codigo: codigo.name,
      DbArvores.codigo2: codigo2?.name,
      DbArvores.codigo3: codigo3,
      DbArvores.tora: tora,
      DbArvores.capAuditoria: capAuditoria,
      DbArvores.alturaAuditoria: alturaAuditoria,
      DbArvores.lastModified: lastModified?.toIso8601String(),
    };
  }

  factory Arvore.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return Arvore(
      id: map[DbArvores.id],
      cap: (map[DbArvores.cap] as num?)?.toDouble() ?? 0.0,
      altura: (map[DbArvores.altura] as num?)?.toDouble(),
      alturaDano: (map[DbArvores.alturaDano] as num?)?.toDouble(),
      linha: map[DbArvores.linha] ?? 0,
      posicaoNaLinha: map[DbArvores.posicaoNaLinha] ?? 0,
      fimDeLinha: map[DbArvores.fimDeLinha] == 1,
      dominante: map[DbArvores.dominante] == 1,
      codigo: Codigo.values.firstWhere((e) => e.name == map[DbArvores.codigo], orElse: () => Codigo.Normal),
      codigo2: map[DbArvores.codigo2] != null
          ? Codigo2.values.firstWhereOrNull((e) => e.name.toLowerCase() == map[DbArvores.codigo2].toString().toLowerCase())
          : null,
      codigo3: map[DbArvores.codigo3],
      tora: map[DbArvores.tora],
      capAuditoria: (map[DbArvores.capAuditoria] as num?)?.toDouble(),
      alturaAuditoria: (map[DbArvores.alturaAuditoria] as num?)?.toDouble(),
      lastModified: parseDate(map[DbArvores.lastModified]),
    );
  }
}
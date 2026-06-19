// Arquivo: lib/models/arvore_model.dart

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';


// ENUMS FORAM REMOVIDOS. TUDO AGORA É STRING DINÂMICA.

class Arvore {
  int? id;
  final double cap;
  final double? altura;
  final double? alturaDano;
  final int linha;
  final int posicaoNaLinha;
  final bool fimDeLinha;
  bool dominante;

  // Alterado para String
  final String codigo;
  final String? codigo2;

  final String? codigo3;
  final String? especie;
  final int? tora;
  final double? capAuditoria;
  final double? alturaAuditoria;
  double? volume;
  final List<String> photoPaths;
  final DateTime? lastModified;

  // Tipo de instrumento usado na medição do CAP: 'fita' (padrão) ou 'suta'.
  final String tipoMedidaCAP;
  // Medidas originais da suta (diâmetros perpendiculares), preservadas para auditoria/exportação.
  final double? medidaSuta1;
  final double? medidaSuta2;

  Arvore({
    this.id, required this.cap, this.altura, this.alturaDano, required this.linha,
    required this.posicaoNaLinha, this.fimDeLinha = false, this.dominante = false,

    required this.codigo, // Obrigatório (String)
    this.codigo2,         // Opcional (String)

    this.codigo3, this.especie, this.tora,
    this.capAuditoria, this.alturaAuditoria, this.volume,
    this.photoPaths = const [],
    this.lastModified,
    this.tipoMedidaCAP = 'fita',
    this.medidaSuta1,
    this.medidaSuta2,
  });

  Arvore copyWith({
    int? id, double? cap, double? altura, double? alturaDano, int? linha,
    int? posicaoNaLinha, bool? fimDeLinha, bool? dominante,
    String? codigo,
    String? codigo2,
    String? codigo3, String? especie, int? tora, double? capAuditoria,
    double? alturaAuditoria, double? volume, List<String>? photoPaths,
    DateTime? lastModified,
    String? tipoMedidaCAP, double? medidaSuta1, double? medidaSuta2,
  }) {
    return Arvore(
      id: id ?? this.id, cap: cap ?? this.cap, altura: altura ?? this.altura,
      alturaDano: alturaDano ?? this.alturaDano, linha: linha ?? this.linha,
      posicaoNaLinha: posicaoNaLinha ?? this.posicaoNaLinha,
      fimDeLinha: fimDeLinha ?? this.fimDeLinha, dominante: dominante ?? this.dominante,
      codigo: codigo ?? this.codigo,
      codigo2: codigo2 ?? this.codigo2,
      codigo3: codigo3 ?? this.codigo3, especie: especie ?? this.especie, tora: tora ?? this.tora,
      capAuditoria: capAuditoria ?? this.capAuditoria,
      alturaAuditoria: alturaAuditoria ?? this.alturaAuditoria,
      volume: volume ?? this.volume,
      photoPaths: photoPaths ?? this.photoPaths,
      lastModified: lastModified ?? this.lastModified,
      tipoMedidaCAP: tipoMedidaCAP ?? this.tipoMedidaCAP,
      medidaSuta1: medidaSuta1 ?? this.medidaSuta1,
      medidaSuta2: medidaSuta2 ?? this.medidaSuta2,
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
      
      DbArvores.codigo: codigo,    // Salva a String direta
      DbArvores.codigo2: codigo2,  // Salva a String direta
      
      DbArvores.codigo3: codigo3,
      'especie': especie,
      DbArvores.tora: tora,
      DbArvores.capAuditoria: capAuditoria,
      DbArvores.alturaAuditoria: alturaAuditoria,
      DbArvores.photoPaths: jsonEncode(photoPaths),
      DbArvores.lastModified: lastModified?.toIso8601String(),
      DbArvores.tipoMedidaCAP: tipoMedidaCAP,
      DbArvores.medidaSuta1: medidaSuta1,
      DbArvores.medidaSuta2: medidaSuta2,
    };
  }

  factory Arvore.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    // Lógica de recuperação de fotos
    List<String> paths = [];
    if (map[DbArvores.photoPaths] != null) {
        var rawPaths = map[DbArvores.photoPaths];
        if (rawPaths is String && rawPaths.isNotEmpty) {
           try {
             var decoded = jsonDecode(rawPaths);
             if (decoded is List) paths = List<String>.from(decoded);
           } catch (_) {}
        } else if (rawPaths is List) {
           paths = List<String>.from(rawPaths);
        }
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
      
      // Recuperação das Strings (Fallback para "N" se nulo)
      codigo: map[DbArvores.codigo]?.toString() ?? "N",
      codigo2: map[DbArvores.codigo2]?.toString(),
      
      codigo3: map[DbArvores.codigo3],
      especie: map['especie'],
      tora: map[DbArvores.tora],
      capAuditoria: (map[DbArvores.capAuditoria] as num?)?.toDouble(),
      alturaAuditoria: (map[DbArvores.alturaAuditoria] as num?)?.toDouble(),
      photoPaths: paths,
      lastModified: parseDate(map[DbArvores.lastModified]),
      tipoMedidaCAP: map[DbArvores.tipoMedidaCAP]?.toString() ?? 'fita',
      medidaSuta1: (map[DbArvores.medidaSuta1] as num?)?.toDouble(),
      medidaSuta2: (map[DbArvores.medidaSuta2] as num?)?.toDouble(),
    );
  }
}
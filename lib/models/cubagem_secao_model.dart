// lib/models/cubagem_secao_model.dart (VERSÃO REFATORADA)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';

class CubagemSecao {
  int? id;
  int? cubagemArvoreId;
  double alturaMedicao;
  double circunferencia;
  double casca1_mm;
  double casca2_mm;
  final DateTime? lastModified;

  double get diametroComCasca => circunferencia / 3.14159;
  double get espessuraMediaCasca_cm => ((casca1_mm + casca2_mm) / 2) / 10;
  double get diametroSemCasca => diametroComCasca - (2 * espessuraMediaCasca_cm);

  CubagemSecao({
    this.id,
    this.cubagemArvoreId = 0,
    required this.alturaMedicao,
    this.circunferencia = 0,
    this.casca1_mm = 0,
    this.casca2_mm = 0,
    this.lastModified,
  });

  Map<String, dynamic> toMap() {
    return {
      DbCubagensSecoes.id: id,
      DbCubagensSecoes.cubagemArvoreId: cubagemArvoreId,
      DbCubagensSecoes.alturaMedicao: alturaMedicao,
      DbCubagensSecoes.circunferencia: circunferencia,
      DbCubagensSecoes.casca1Mm: casca1_mm,
      DbCubagensSecoes.casca2Mm: casca2_mm,
      DbCubagensSecoes.lastModified: lastModified?.toIso8601String(),
    };
  }

  factory CubagemSecao.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return CubagemSecao(
      id: map[DbCubagensSecoes.id],
      cubagemArvoreId: map[DbCubagensSecoes.cubagemArvoreId],
      alturaMedicao: (map[DbCubagensSecoes.alturaMedicao] as num?)?.toDouble() ?? 0.0,
      circunferencia: (map[DbCubagensSecoes.circunferencia] as num?)?.toDouble() ?? 0,
      casca1_mm: (map[DbCubagensSecoes.casca1Mm] as num?)?.toDouble() ?? 0,
      casca2_mm: (map[DbCubagensSecoes.casca2Mm] as num?)?.toDouble() ?? 0,
      lastModified: parseDate(map[DbCubagensSecoes.lastModified]),
    );
  }
}
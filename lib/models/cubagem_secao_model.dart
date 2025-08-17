// lib/models/cubagem_secao_model.dart (VERSÃO CORRIGIDA)
import 'package:cloud_firestore/cloud_firestore.dart';

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
      'id': id,
      'cubagemArvoreId': cubagemArvoreId,
      'alturaMedicao': alturaMedicao,
      'circunferencia': circunferencia,
      'casca1_mm': casca1_mm,
      'casca2_mm': casca2_mm,
      'lastModified': lastModified?.toIso8601String(),
    };
  }

  factory CubagemSecao.fromMap(Map<String, dynamic> map) {
    // <<< INÍCIO DA CORREÇÃO >>>
    // Esta função auxiliar agora consegue interpretar tanto o Timestamp do Firebase
    // quanto a String do banco de dados local.
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      } else if (value is String) {
        return DateTime.tryParse(value);
      }
      return null;
    }
    // <<< FIM DA CORREÇÃO >>>

    return CubagemSecao(
      id: map['id'],
      cubagemArvoreId: map['cubagemArvoreId'],
      alturaMedicao: map['alturaMedicao'],
      circunferencia: map['circunferencia'] ?? 0,
      casca1_mm: map['casca1_mm'] ?? 0,
      casca2_mm: map['casca2_mm'] ?? 0,
      // Agora usamos a função auxiliar segura.
      lastModified: parseDate(map['lastModified']),
    );
  }
}
// lib/models/cubagem_secao_model.dart (VERSÃO ATUALIZADA COM lastModified)

class CubagemSecao {
  int? id;
  int? cubagemArvoreId;
  double alturaMedicao;
  double circunferencia;
  double casca1_mm;
  double casca2_mm;
  final DateTime? lastModified; // <<< ADICIONADO

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
    this.lastModified, // <<< ADICIONADO
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cubagemArvoreId': cubagemArvoreId,
      'alturaMedicao': alturaMedicao,
      'circunferencia': circunferencia,
      'casca1_mm': casca1_mm,
      'casca2_mm': casca2_mm,
      'lastModified': lastModified?.toIso8601String(), // <<< ADICIONADO
    };
  }

  factory CubagemSecao.fromMap(Map<String, dynamic> map) {
    return CubagemSecao(
      id: map['id'],
      cubagemArvoreId: map['cubagemArvoreId'],
      alturaMedicao: map['alturaMedicao'],
      circunferencia: map['circunferencia'] ?? 0,
      casca1_mm: map['casca1_mm'] ?? 0,
      casca2_mm: map['casca2_mm'] ?? 0,
      lastModified: map['lastModified'] != null ? DateTime.tryParse(map['lastModified']) : null, // <<< ADICIONADO
    );
  }
}
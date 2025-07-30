// lib/models/cubagem_secao_model.dart

class CubagemSecao {
  int? id;
  int? cubagemArvoreId; // Chave estrangeira
  double alturaMedicao;  // A altura no fuste onde a medição foi feita
  
  // Dados de entrada do usuário
  double circunferencia; // cm
  double casca1_mm;      // mm
  double casca2_mm;

  // Dados calculados (para conveniência, não salvos no DB)
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
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cubagemArvoreId': cubagemArvoreId,
      'alturaMedicao': alturaMedicao,
      'circunferencia': circunferencia,
      'casca1_mm': casca1_mm,
      'casca2_mm': casca2_mm,
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
    );
  }
}
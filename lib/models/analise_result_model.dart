// lib/models/analise_result_model.dart (VERSÃO ATUALIZADA)

// Novo modelo para a distribuição de árvores por classe de diâmetro
class DapClassResult {
  final String classe;
  final int quantidade;
  final double porcentagemDoTotal;

  DapClassResult({
    required this.classe,
    required this.quantidade,
    required this.porcentagemDoTotal,
  });
}

// Novo modelo para guardar os detalhes estatísticos de um código
class CodeStatDetails {
  final double mediaCap;
  final double medianaCap;
  final double modaCap;
  final double desvioPadraoCap;
  final double mediaAltura;
  final double medianaAltura;
  final double modaAltura;
  final double desvioPadraoAltura;

  CodeStatDetails({
    this.mediaCap = 0,
    this.medianaCap = 0,
    this.modaCap = 0,
    this.desvioPadraoCap = 0,
    this.mediaAltura = 0,
    this.medianaAltura = 0,
    this.modaAltura = 0,
    this.desvioPadraoAltura = 0,
  });
}

// Novo modelo para encapsular todos os resultados da análise de códigos
class CodeAnalysisResult {
  final Map<String, int> contagemPorCodigo;
  final Map<String, CodeStatDetails> estatisticasPorCodigo;
  final int totalFustes;
  final int totalCovasOcupadas;
  final int totalCovasAmostradas;

  CodeAnalysisResult({
    this.contagemPorCodigo = const {},
    this.estatisticasPorCodigo = const {},
    this.totalFustes = 0,
    this.totalCovasOcupadas = 0,
    this.totalCovasAmostradas = 0,
  });
}


// O modelo principal, agora com a nova análise de códigos
class TalhaoAnalysisResult {
  final double areaTotalAmostradaHa;
  final int totalArvoresAmostradas;
  final int totalParcelasAmostradas;
  final double mediaCap;
  final double mediaAltura;
  final double areaBasalPorHectare;
  final double volumePorHectare;
  final int arvoresPorHectare;
  final Map<double, int> distribuicaoDiametrica;
  final CodeAnalysisResult? analiseDeCodigos; // <<< NOVO CAMPO
  final List<String> warnings;
  final List<String> insights;
  final List<String> recommendations;

  TalhaoAnalysisResult({
    this.areaTotalAmostradaHa = 0,
    this.totalArvoresAmostradas = 0,
    this.totalParcelasAmostradas = 0,
    this.mediaCap = 0,
    this.mediaAltura = 0,
    this.areaBasalPorHectare = 0,
    this.volumePorHectare = 0,
    this.arvoresPorHectare = 0,
    this.distribuicaoDiametrica = const {},
    this.analiseDeCodigos, // <<< NOVO CAMPO
    this.warnings = const [],
    this.insights = const [],
    this.recommendations = const [],
  });
}
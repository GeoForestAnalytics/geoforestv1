// lib/models/analise_result_model.dart (NOVO ARQUIVO)

class RendimentoDAP {
  final String classe; 
  final double volumePorHectare;
  final double porcentagemDoTotal;
  final int arvoresPorHectare;

  RendimentoDAP({
    required this.classe,
    required this.volumePorHectare,
    required this.porcentagemDoTotal,
    required this.arvoresPorHectare,
  });
}

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
    this.warnings = const [],
    this.insights = const [],
    this.recommendations = const [],
  });
}
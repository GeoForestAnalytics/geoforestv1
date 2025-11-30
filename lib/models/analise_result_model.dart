// lib/models/analise_result_model.dart (VERSÃO COM NOVOS MODELOS VOLUMÉTRICOS)

// --- Modelos para Análise de Inventário (TalhaoDashboardPage) ---

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
    this.mediaCap = 0, this.medianaCap = 0, this.modaCap = 0, this.desvioPadraoCap = 0,
    this.mediaAltura = 0, this.medianaAltura = 0, this.modaAltura = 0, this.desvioPadraoAltura = 0,
  });
}

class CodeAnalysisResult {
  final Map<String, int> contagemPorCodigo;
  final Map<String, CodeStatDetails> estatisticasPorCodigo;
  final int totalFustes;
  final int totalCovasOcupadas;
  final int totalCovasAmostradas;

  CodeAnalysisResult({
    this.contagemPorCodigo = const {}, this.estatisticasPorCodigo = const {},
    this.totalFustes = 0, this.totalCovasOcupadas = 0, this.totalCovasAmostradas = 0,
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
  final double alturaDominante;
  final double indiceDeSitio;
  final Map<double, int> distribuicaoDiametrica;
  final CodeAnalysisResult? analiseDeCodigos;
  final List<String> warnings;
  final List<String> insights;
  final List<String> recommendations;

  TalhaoAnalysisResult({
    this.areaTotalAmostradaHa = 0, this.totalArvoresAmostradas = 0, this.totalParcelasAmostradas = 0,
    this.mediaCap = 0, this.mediaAltura = 0, this.areaBasalPorHectare = 0, this.volumePorHectare = 0,
    this.arvoresPorHectare = 0, 
    this.alturaDominante = 0, this.indiceDeSitio = 0,
    this.distribuicaoDiametrica = const {}, this.analiseDeCodigos,
    this.warnings = const [], this.insights = const [], this.recommendations = const [],
  });
}

// --- NOVOS MODELOS PARA ANÁLISE VOLUMÉTRICA ---

class VolumePorSortimento {
  final String nome;
  final double volumeHa;
  final double porcentagem;

  VolumePorSortimento({required this.nome, required this.volumeHa, required this.porcentagem});
}

class VolumePorCodigo {
  final String codigo;
  final double volumeTotal;
  final double porcentagem;

  VolumePorCodigo({required this.codigo, required this.volumeTotal, required this.porcentagem});
}


class AnaliseVolumetricaCompletaResult {
  final Map<String, dynamic> resultadoRegressao;
  final Map<String, dynamic> diagnosticoRegressao;
  final Map<String, dynamic> totaisInventario;
  final List<VolumePorSortimento> producaoPorSortimento;
  final List<VolumePorCodigo> volumePorCodigo;

  AnaliseVolumetricaCompletaResult({
    required this.resultadoRegressao,
    required this.diagnosticoRegressao,
    required this.totaisInventario,
    required this.producaoPorSortimento,
    required this.volumePorCodigo,
  });
}
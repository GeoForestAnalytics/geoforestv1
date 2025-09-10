// lib/models/enums.dart

enum MetodoDistribuicaoCubagem {
  fixoPorTalhao,
  proporcionalPorArea,
}

// <<< ADICIONE ESTE NOVO ENUM >>>
enum MetricaDistribuicao {
  dap("DAP"),
  cap("CAP");

  const MetricaDistribuicao(this.descricao);
  final String descricao;
}
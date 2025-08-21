// lib/providers/operacoes_provider.dart (NOVO ARQUIVO)

import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';

// Classes de modelo para estruturar os dados calculados
class KpiData {
  final int coletasRealizadas;
  final double custoTotalCampo;
  final double kmRodados;
  final double custoPorColeta;

  KpiData({
    this.coletasRealizadas = 0,
    this.custoTotalCampo = 0.0,
    this.kmRodados = 0.0,
    this.custoPorColeta = 0.0,
  });
}

class CustoPorVeiculo {
  final String placa;
  final double kmRodados;
  final double custoAbastecimento;
  final double custoMedioPorKm;

  CustoPorVeiculo({
    required this.placa,
    required this.kmRodados,
    required this.custoAbastecimento,
    required this.custoMedioPorKm,
  });
}

/// Provider responsável por calcular as métricas do Dashboard de Operações.
class OperacoesProvider with ChangeNotifier {
  // --- DADOS FILTRADOS E CALCULADOS ---
  KpiData _kpis = KpiData();
  Map<String, double> _composicaoDespesas = {};
  Map<String, int> _coletasPorEquipe = {};
  List<CustoPorVeiculo> _custosPorVeiculo = [];
  List<DiarioDeCampo> _diariosFiltrados = [];

  // --- GETTERS PÚBLICOS ---
  KpiData get kpis => _kpis;
  Map<String, double> get composicaoDespesas => _composicaoDespesas;
  Map<String, int> get coletasPorEquipe => _coletasPorEquipe;
  List<CustoPorVeiculo> get custosPorVeiculo => _custosPorVeiculo;
  List<DiarioDeCampo> get diariosFiltrados => _diariosFiltrados;

  /// Método principal chamado pelo ProxyProvider para atualizar todos os cálculos.
  void update(GerenteProvider gerenteProvider) {
    // Aqui, futuramente, adicionaremos os filtros de data e equipe.
    // Por enquanto, vamos calcular com base em todos os dados disponíveis.
    final todosOsDiarios = gerenteProvider.diariosSincronizados;
    final todasAsParcelas = gerenteProvider.parcelasSincronizadas;
    final todasAsCubagens = gerenteProvider.cubagensSincronizadas;

    // TODO: Implementar a lógica de filtro por data e equipe aqui.
    _diariosFiltrados = todosOsDiarios;

    if (_diariosFiltrados.isEmpty) {
      _limparDados();
      return;
    }

    _calcularKPIs(todosOsDiarios, todasAsParcelas.length, todasAsCubagens.length);
    _calcularComposicaoDespesas(todosOsDiarios);
    _calcularColetasPorEquipe(todosOsDiarios, todasAsParcelas.length, todasAsCubagens.length);
    _calcularCustosPorVeiculo(todosOsDiarios);

    notifyListeners();
  }

  void _calcularKPIs(List<DiarioDeCampo> diarios, int totalParcelas, int totalCubagens) {
    final int coletas = totalParcelas + totalCubagens;
    
    final double custoTotal = diarios.fold(0.0, (prev, d) {
      return prev + (d.abastecimentoValor ?? 0) + (d.pedagioValor ?? 0) + (d.alimentacaoRefeicaoValor ?? 0);
    });

    final double kmTotal = diarios.fold(0.0, (prev, d) {
      if (d.kmFinal != null && d.kmInicial != null && d.kmFinal! > d.kmInicial!) {
        return prev + (d.kmFinal! - d.kmInicial!);
      }
      return prev;
    });

    _kpis = KpiData(
      coletasRealizadas: coletas,
      custoTotalCampo: custoTotal,
      kmRodados: kmTotal,
      custoPorColeta: coletas > 0 ? custoTotal / coletas : 0.0,
    );
  }

  void _calcularComposicaoDespesas(List<DiarioDeCampo> diarios) {
    double totalAbastecimento = diarios.fold(0.0, (prev, d) => prev + (d.abastecimentoValor ?? 0));
    double totalPedagio = diarios.fold(0.0, (prev, d) => prev + (d.pedagioValor ?? 0));
    double totalAlimentacao = diarios.fold(0.0, (prev, d) => prev + (d.alimentacaoRefeicaoValor ?? 0));

    _composicaoDespesas = {
      'Abastecimento': totalAbastecimento,
      'Alimentação': totalAlimentacao,
      'Pedágio': totalPedagio,
    };
  }
  
  void _calcularColetasPorEquipe(List<DiarioDeCampo> diarios, int totalParcelas, int totalCubagens) {
    // Esta é uma estimativa. Para dados precisos, precisaríamos vincular
    // cada coleta ao diário do dia. Por enquanto, agrupamos por líder.
    final grupo = groupBy(diarios, (DiarioDeCampo d) => d.nomeLider);
    _coletasPorEquipe = grupo.map((lider, listaDiarios) => MapEntry(lider, listaDiarios.length));
    // NOTE: Este cálculo assume "1 diário = 1 dia de coleta por equipe".
    // A métrica real de coletas por equipe já está no `DashboardMetricsProvider`.
    // Poderíamos refatorar para unificar isso no futuro.
  }

  void _calcularCustosPorVeiculo(List<DiarioDeCampo> diarios) {
    // Agrupa os diários por placa de veículo, filtrando os que não têm placa.
    final grupoPorPlaca = groupBy(
      diarios.where((d) => d.veiculoPlaca != null && d.veiculoPlaca!.isNotEmpty),
      (DiarioDeCampo d) => d.veiculoPlaca!,
    );
    
    _custosPorVeiculo = grupoPorPlaca.entries.map((entry) {
      final placa = entry.key;
      final diariosDoVeiculo = entry.value;
      
      final kmTotal = diariosDoVeiculo.fold(0.0, (prev, d) {
        if (d.kmFinal != null && d.kmInicial != null && d.kmFinal! > d.kmInicial!) {
          return prev + (d.kmFinal! - d.kmInicial!);
        }
        return prev;
      });
      
      final custoTotalAbastecimento = diariosDoVeiculo.fold(0.0, (prev, d) => prev + (d.abastecimentoValor ?? 0));

      return CustoPorVeiculo(
        placa: placa,
        kmRodados: kmTotal,
        custoAbastecimento: custoTotalAbastecimento,
        custoMedioPorKm: kmTotal > 0 ? custoTotalAbastecimento / kmTotal : 0.0,
      );
    }).toList();
  }

  /// Limpa todos os dados calculados quando não há filtros ou dados.
  void _limparDados() {
    _kpis = KpiData();
    _composicaoDespesas = {};
    _coletasPorEquipe = {};
    _custosPorVeiculo = [];
    _diariosFiltrados = [];
    notifyListeners();
  }
}
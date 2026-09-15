import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geoforestv1/providers/operacoes_filter_provider.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';

class KpiData {
  final String progressoAmostras;
  final String progressoCubagens;
  final int coletasRealizadas;
  final double custoTotalCampo;
  final double kmRodados;
  final double custoPorColeta;
  final double custoTotalAbastecimento;
  final double custoMedioKmGeral;
  // Colheita
  final double volumeTotalM3;
  final double custoPorM3;
  final int totalPilhas;
  // Silvicultura
  final double areaTotalHa;
  final double custoPorHa;
  final int totalOperacoesSilvi;

  KpiData({
    this.progressoAmostras = "0/0",
    this.progressoCubagens = "0/0",
    this.coletasRealizadas = 0,
    this.custoTotalCampo = 0.0,
    this.kmRodados = 0.0,
    this.custoPorColeta = 0.0,
    this.custoTotalAbastecimento = 0.0,
    this.custoMedioKmGeral = 0.0,
    this.volumeTotalM3 = 0.0,
    this.custoPorM3 = 0.0,
    this.totalPilhas = 0,
    this.areaTotalHa = 0.0,
    this.custoPorHa = 0.0,
    this.totalOperacoesSilvi = 0,
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

class OperacoesProvider with ChangeNotifier {
  KpiData _kpis = KpiData();
  Map<String, double> _composicaoDespesas = {};
  Map<String, int> _coletasPorEquipe = {};
  List<CustoPorVeiculo> _custosPorVeiculo = [];
  List<DiarioDeCampo> _diariosFiltrados = [];

  // produção por diário para a tabela (inventário = parcelas+cubagens, colheita = pilhas, silvi = operações)
  Map<int, int> _producaoPorDiario = {};
  // volume m³ por diário (colheita)
  Map<int, double> _producaoVolumePorDiario = {};
  // área ha por diário (silvicultura)
  Map<int, double> _producaoAreaPorDiario = {};

  KpiData get kpis => _kpis;
  Map<String, double> get composicaoDespesas => _composicaoDespesas;
  Map<String, int> get coletasPorEquipe => _coletasPorEquipe;
  List<CustoPorVeiculo> get custosPorVeiculo => _custosPorVeiculo;
  List<DiarioDeCampo> get diariosFiltrados => _diariosFiltrados;
  Map<int, int> get producaoPorDiario => _producaoPorDiario;
  Map<int, double> get producaoVolumePorDiario => _producaoVolumePorDiario;
  Map<int, double> get producaoAreaPorDiario => _producaoAreaPorDiario;

  String _normalizar(String? texto) => (texto ?? '').trim().toLowerCase();

  bool _isMesmoDia(DateTime d1, DateTime d2) =>
      d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;

  bool _liderMatch(String liderDiario, String? liderItem) {
    final l = _normalizar(liderItem);
    return l.isEmpty || l.contains(liderDiario) || liderDiario.contains(l);
  }

  void update(GerenteProvider gerenteProvider, OperacoesFilterProvider filterProvider) {
    final todosOsDiarios = gerenteProvider.diariosSincronizados;
    final todasAsParcelas = gerenteProvider.parcelasSincronizadas;
    final todasAsCubagens = gerenteProvider.cubagensSincronizadas;
    final todasAsPilhas = gerenteProvider.pilhasSincronizadas;
    final todasAsSilvis = gerenteProvider.silviSincronizadas;

    // 1. Filtra Diários
    _diariosFiltrados = _filtrarDiarios(todosOsDiarios, filterProvider);

    // 2. Prepara listas realizadas
    final parcelasRealizadas = todasAsParcelas
        .where((p) => p.dataColeta != null && (p.status == StatusParcela.concluida || p.status == StatusParcela.exportada))
        .toList();
    final cubagensRealizadas = todasAsCubagens.where((c) => c.dataColeta != null && c.alturaTotal > 0).toList();

    // 3. Produção por diário
    _producaoPorDiario = {};
    _producaoVolumePorDiario = {};
    _producaoAreaPorDiario = {};
    int totalProducaoVinculada = 0;
    double totalVolumeM3 = 0;
    double totalAreaHa = 0;
    int totalPilhasCount = 0;
    int totalSilviCount = 0;

    for (final diario in _diariosFiltrados) {
      if (diario.id == null) continue;
      DateTime? dataDiario;
      try { dataDiario = DateTime.parse(diario.dataRelatorio); } catch (_) {}
      if (dataDiario == null) continue;

      final liderDiario = _normalizar(diario.nomeLider);
      int qtdNoDia = 0;
      double volNoDia = 0;
      double areaNoDia = 0;

      // Inventário: parcelas + cubagens
      for (final p in parcelasRealizadas) {
        if (_isMesmoDia(p.dataColeta!, dataDiario) && _liderMatch(liderDiario, p.nomeLider)) {
          qtdNoDia++;
        }
      }
      for (final c in cubagensRealizadas) {
        if (_isMesmoDia(c.dataColeta!, dataDiario) && _liderMatch(liderDiario, c.nomeLider)) {
          qtdNoDia++;
        }
      }

      // Colheita: pilhas
      for (final pilha in todasAsPilhas) {
        if (pilha.dataColeta == null) continue;
        if (_isMesmoDia(pilha.dataColeta!, dataDiario) && _liderMatch(liderDiario, pilha.nomeLider)) {
          volNoDia += pilha.volumeBruto ?? 0;
          qtdNoDia++;
          totalPilhasCount++;
        }
      }

      // Silvicultura: operações
      for (final silvi in todasAsSilvis) {
        if (silvi.dataExecucao == null) continue;
        DateTime? dataSilvi;
        try { dataSilvi = DateTime.parse(silvi.dataExecucao!); } catch (_) {}
        if (dataSilvi == null) continue;
        if (_isMesmoDia(dataSilvi, dataDiario) && _liderMatch(liderDiario, silvi.nomeLider)) {
          areaNoDia += silvi.areaAplicadaHa ?? 0;
          qtdNoDia++;
          totalSilviCount++;
        }
      }

      _producaoPorDiario[diario.id!] = qtdNoDia;
      _producaoVolumePorDiario[diario.id!] = volNoDia;
      _producaoAreaPorDiario[diario.id!] = areaNoDia;
      totalProducaoVinculada += qtdNoDia;
      totalVolumeM3 += volNoDia;
      totalAreaHa += areaNoDia;
    }

    // 4. Totais no período filtrado
    final parcelasNoFiltro = _filtrarColetas<Parcela>(
      lista: todasAsParcelas, filterProvider: filterProvider, getDate: (p) => p.dataColeta, getLider: (p) => p.nomeLider,
    );
    final cubagensNoFiltro = _filtrarColetas<CubagemArvore>(
      lista: todasAsCubagens, filterProvider: filterProvider, getDate: (c) => c.dataColeta, getLider: (c) => c.nomeLider,
    );

    final parcelasFeitas = parcelasNoFiltro.where((p) => p.status == StatusParcela.concluida || p.status == StatusParcela.exportada).length;
    final cubagensFeitas = cubagensNoFiltro.where((c) => c.alturaTotal > 0).length;

    // 5. KPIs financeiros
    _calcularKPIsFinanceiros(
      _diariosFiltrados,
      totalProducaoVinculada,
      parcelasNoFiltro.length,
      parcelasFeitas,
      cubagensNoFiltro.length,
      cubagensFeitas,
      totalVolumeM3,
      totalAreaHa,
      totalPilhasCount,
      totalSilviCount,
    );

    _calcularComposicaoDespesas(_diariosFiltrados);
    _calcularCustosPorVeiculo(_diariosFiltrados);

    _diariosFiltrados.sort((a, b) => b.dataRelatorio.compareTo(a.dataRelatorio));

    notifyListeners();
  }

  List<T> _filtrarColetas<T>({
    required List<T> lista,
    required OperacoesFilterProvider filterProvider,
    required DateTime? Function(T) getDate,
    required String? Function(T) getLider,
  }) {
    return lista.where((item) {
      final data = getDate(item);
      final lider = getLider(item);
      if (filterProvider.lideresSelecionados.isNotEmpty) {
        final liderItem = _normalizar(lider);
        bool matchLider = filterProvider.lideresSelecionados.any((l) => _normalizar(l) == liderItem || liderItem.contains(_normalizar(l)));
        if (!matchLider) return false;
      }
      return _filtroDeData(data, filterProvider);
    }).toList();
  }

  bool _filtroDeData(DateTime? data, OperacoesFilterProvider filter) {
    if (data == null) return false;
    final agora = DateTime.now();
    switch (filter.periodo) {
      case PeriodoFiltro.todos: return true;
      case PeriodoFiltro.hoje: return data.year == agora.year && data.month == agora.month && data.day == agora.day;
      case PeriodoFiltro.ultimos7Dias: return data.isAfter(agora.subtract(const Duration(days: 7)));
      case PeriodoFiltro.esteMes: return data.year == agora.year && data.month == agora.month;
      case PeriodoFiltro.mesPassado:
        final mesPassado = DateTime(agora.year, agora.month - 1, 1);
        return data.year == mesPassado.year && data.month == mesPassado.month;
      case PeriodoFiltro.personalizado:
        if (filter.periodoPersonalizado != null) {
          final inicio = filter.periodoPersonalizado!.start.subtract(const Duration(days: 1));
          final fim = filter.periodoPersonalizado!.end.add(const Duration(days: 1));
          return data.isAfter(inicio) && data.isBefore(fim);
        }
        return true;
    }
  }

  List<DiarioDeCampo> _filtrarDiarios(List<DiarioDeCampo> todos, OperacoesFilterProvider filterProvider) {
    return todos.where((d) {
      DateTime? dataDiario;
      try { dataDiario = DateTime.parse(d.dataRelatorio); } catch (_) { return false; }
      if (filterProvider.projetoIdsFiltro.isNotEmpty && !filterProvider.projetoIdsFiltro.contains(d.projetoId)) return false;
      if (filterProvider.lideresSelecionados.isNotEmpty && !filterProvider.lideresSelecionados.contains(d.nomeLider)) return false;
      return _filtroDeData(dataDiario, filterProvider);
    }).toList();
  }

  void _calcularKPIsFinanceiros(
    List<DiarioDeCampo> diarios,
    int totalProducaoVinculada,
    int totalParcelas,
    int parcelasFeitas,
    int totalCubagens,
    int cubagensFeitas,
    double totalVolumeM3,
    double totalAreaHa,
    int totalPilhas,
    int totalSilviOps,
  ) {
    double custoTotal = 0;
    double custoAbastecimentoTotal = 0;
    double kmTotal = 0;

    for (final d in diarios) {
      final abastecimento = d.abastecimentoValor ?? 0;
      custoAbastecimentoTotal += abastecimento;
      custoTotal += abastecimento + (d.pedagioValor ?? 0) + (d.alimentacaoRefeicaoValor ?? 0) + (d.outrasDespesasValor ?? 0);
      if (d.kmFinal != null && d.kmInicial != null && d.kmFinal! > d.kmInicial!) {
        kmTotal += (d.kmFinal! - d.kmInicial!);
      }
    }

    final int producaoTotalFisica = parcelasFeitas + cubagensFeitas;

    _kpis = KpiData(
      progressoAmostras: "$parcelasFeitas/$totalParcelas",
      progressoCubagens: "$cubagensFeitas/$totalCubagens",
      coletasRealizadas: producaoTotalFisica,
      custoTotalCampo: custoTotal,
      kmRodados: kmTotal,
      custoPorColeta: producaoTotalFisica > 0 ? custoTotal / producaoTotalFisica : 0.0,
      custoTotalAbastecimento: custoAbastecimentoTotal,
      custoMedioKmGeral: kmTotal > 0 ? custoAbastecimentoTotal / kmTotal : 0.0,
      volumeTotalM3: totalVolumeM3,
      custoPorM3: totalVolumeM3 > 0 ? custoTotal / totalVolumeM3 : 0.0,
      totalPilhas: totalPilhas,
      areaTotalHa: totalAreaHa,
      custoPorHa: totalAreaHa > 0 ? custoTotal / totalAreaHa : 0.0,
      totalOperacoesSilvi: totalSilviOps,
    );
  }

  void _calcularComposicaoDespesas(List<DiarioDeCampo> diarios) {
    double totalAbastecimento = diarios.fold(0.0, (prev, d) => prev + (d.abastecimentoValor ?? 0));
    double totalPedagio = diarios.fold(0.0, (prev, d) => prev + (d.pedagioValor ?? 0));
    double totalAlimentacao = diarios.fold(0.0, (prev, d) => prev + (d.alimentacaoRefeicaoValor ?? 0));
    double totalOutros = diarios.fold(0.0, (prev, d) => prev + (d.outrasDespesasValor ?? 0));
    _composicaoDespesas = {'Abastecimento': totalAbastecimento, 'Alimentação': totalAlimentacao, 'Pedágio': totalPedagio, 'Outros': totalOutros};
  }

  void _calcularCustosPorVeiculo(List<DiarioDeCampo> diarios) {
    final grupoPorPlaca = groupBy(diarios.where((d) => d.veiculoPlaca != null && d.veiculoPlaca!.isNotEmpty), (DiarioDeCampo d) => d.veiculoPlaca!);
    _custosPorVeiculo = grupoPorPlaca.entries.map((entry) {
      final kmTotal = entry.value.fold(0.0, (prev, d) => prev + ((d.kmFinal != null && d.kmInicial != null && d.kmFinal! > d.kmInicial!) ? (d.kmFinal! - d.kmInicial!) : 0.0));
      final custoTotalAbastecimento = entry.value.fold(0.0, (prev, d) => prev + (d.abastecimentoValor ?? 0));
      return CustoPorVeiculo(placa: entry.key, kmRodados: kmTotal, custoAbastecimento: custoTotalAbastecimento, custoMedioPorKm: kmTotal > 0 ? custoTotalAbastecimento / kmTotal : 0.0);
    }).toList();
  }
}

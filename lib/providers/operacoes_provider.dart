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
  final int coletasRealizadas; // Usado no rodapé da tabela
  final double custoTotalCampo;
  final double kmRodados;
  final double custoPorColeta;
  final double custoTotalAbastecimento;
  final double custoMedioKmGeral;

  KpiData({
    this.progressoAmostras = "0/0",
    this.progressoCubagens = "0/0",
    this.coletasRealizadas = 0,
    this.custoTotalCampo = 0.0,
    this.kmRodados = 0.0,
    this.custoPorColeta = 0.0,
    this.custoTotalAbastecimento = 0.0,
    this.custoMedioKmGeral = 0.0,
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
  
  // Mapa que vincula ID do Diário -> Quantidade Produzida naquele dia
  Map<int, int> _producaoPorDiario = {};

  KpiData get kpis => _kpis;
  Map<String, double> get composicaoDespesas => _composicaoDespesas;
  Map<String, int> get coletasPorEquipe => _coletasPorEquipe;
  List<CustoPorVeiculo> get custosPorVeiculo => _custosPorVeiculo;
  List<DiarioDeCampo> get diariosFiltrados => _diariosFiltrados;
  Map<int, int> get producaoPorDiario => _producaoPorDiario;

  String _normalizar(String? texto) => (texto ?? '').trim().toLowerCase();

  bool _isMesmoDia(DateTime d1, DateTime d2) {
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  void update(GerenteProvider gerenteProvider, OperacoesFilterProvider filterProvider) {
    final todosOsDiarios = gerenteProvider.diariosSincronizados;
    final todasAsParcelas = gerenteProvider.parcelasSincronizadas;
    final todasAsCubagens = gerenteProvider.cubagensSincronizadas;

    // 1. Filtra Diários (Base Financeira)
    _diariosFiltrados = _filtrarDiarios(todosOsDiarios, filterProvider);
    
    // 2. Prepara listas de TUDO realizado para "casar" com a tabela
    final parcelasRealizadas = todasAsParcelas.where((p) => 
       p.dataColeta != null && 
       (p.status == StatusParcela.concluida || p.status == StatusParcela.exportada)
    ).toList();

    final cubagensRealizadas = todasAsCubagens.where((c) => 
       c.dataColeta != null && c.alturaTotal > 0
    ).toList();

    // 3. Preenche o mapa de produção por diário (Para a Tabela)
    _producaoPorDiario = {};
    int totalProducaoVinculada = 0;

    for (var diario in _diariosFiltrados) {
      if (diario.id == null) continue;

      DateTime? dataDiario;
      try { dataDiario = DateTime.parse(diario.dataRelatorio); } catch(_) {}
      if (dataDiario == null) continue;

      final liderDiario = _normalizar(diario.nomeLider);
      int qtdNoDia = 0;

      // Conta Parcelas
      for (var p in parcelasRealizadas) {
        if (_isMesmoDia(p.dataColeta!, dataDiario)) {
            final liderP = _normalizar(p.nomeLider);
            if (liderP.isEmpty || liderP.contains(liderDiario) || liderDiario.contains(liderP)) {
              qtdNoDia++;
            }
        }
      }
      // Conta Cubagens
      for (var c in cubagensRealizadas) {
        if (_isMesmoDia(c.dataColeta!, dataDiario)) {
            final liderC = _normalizar(c.nomeLider);
            if (liderC.isEmpty || liderC.contains(liderDiario) || liderDiario.contains(liderC)) {
              qtdNoDia++;
            }
        }
      }

      _producaoPorDiario[diario.id!] = qtdNoDia;
      totalProducaoVinculada += qtdNoDia;
    }

    // 4. Calcula Totais Gerais do Período (Para os Cards de Cima)
    // Aqui pegamos TUDO que foi feito no filtro, independente se tem diário ou não
    final parcelasNoFiltro = _filtrarColetas<Parcela>(
      lista: todasAsParcelas, filterProvider: filterProvider, getDate: (p) => p.dataColeta, getLider: (p) => p.nomeLider
    );
    final cubagensNoFiltro = _filtrarColetas<CubagemArvore>(
      lista: todasAsCubagens, filterProvider: filterProvider, getDate: (c) => c.dataColeta, getLider: (c) => c.nomeLider
    );

    final parcelasFeitas = parcelasNoFiltro.where((p) => p.status == StatusParcela.concluida || p.status == StatusParcela.exportada).length;
    final cubagensFeitas = cubagensNoFiltro.where((c) => c.alturaTotal > 0).length;

    // 5. Calcula KPIs usando a SOMA de Parcelas + Cubagens
    _calcularKPIsFinanceiros(
      _diariosFiltrados, 
      totalProducaoVinculada, // Para a tabela
      parcelasNoFiltro.length, 
      parcelasFeitas, 
      cubagensNoFiltro.length, 
      cubagensFeitas
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
      try { dataDiario = DateTime.parse(d.dataRelatorio); } catch(_) { return false; }
      if (filterProvider.lideresSelecionados.isNotEmpty) {
         if (!filterProvider.lideresSelecionados.contains(d.nomeLider)) return false;
      }
      return _filtroDeData(dataDiario, filterProvider);
    }).toList();
  }

  void _calcularKPIsFinanceiros(
    List<DiarioDeCampo> diarios, 
    int totalProducaoVinculada, 
    int totalParcelas, 
    int parcelasFeitas, 
    int totalCubagens, 
    int cubagensFeitas
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
    
    // AQUI ESTÁ A MÁGICA: Somamos Amostras + Cubagens para o divisor
    final int producaoTotalFisica = parcelasFeitas + cubagensFeitas;

    _kpis = KpiData(
      progressoAmostras: "$parcelasFeitas/$totalParcelas",
      progressoCubagens: "$cubagensFeitas/$totalCubagens",
      
      coletasRealizadas: producaoTotalFisica, // Mostra a soma total de produção
      
      custoTotalCampo: custoTotal,
      kmRodados: kmTotal,
      
      // CUSTO AGORA DIVIDE PELA SOMA DE (Parcelas Feitas + Cubagens Feitas)
      custoPorColeta: producaoTotalFisica > 0 ? custoTotal / producaoTotalFisica : 0.0,
      
      custoTotalAbastecimento: custoAbastecimentoTotal,
      custoMedioKmGeral: kmTotal > 0 ? custoAbastecimentoTotal / kmTotal : 0.0,
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
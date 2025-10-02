// lib/providers/operacoes_provider.dart (VERSÃO FINAL CORRIGIDA)

import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geoforestv1/providers/operacoes_filter_provider.dart';


// <<< IMPORT ADICIONADO AQUI >>>
import 'package:geoforestv1/models/parcela_model.dart';
// <<< FIM DO IMPORT >>>


class KpiData {
  final int coletasRealizadas;
  final double custoTotalCampo;
  final double kmRodados;
  final double custoPorColeta;
  final double custoTotalAbastecimento;
  final double custoMedioKmGeral;

  KpiData({
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

  KpiData get kpis => _kpis;
  Map<String, double> get composicaoDespesas => _composicaoDespesas;
  Map<String, int> get coletasPorEquipe => _coletasPorEquipe;
  List<CustoPorVeiculo> get custosPorVeiculo => _custosPorVeiculo;
  List<DiarioDeCampo> get diariosFiltrados => _diariosFiltrados;

  /// PONTO DE ENTRADA PÚBLICO: Chamado pelo ProxyProvider para recalcular todas as métricas.
  void update(GerenteProvider gerenteProvider, OperacoesFilterProvider filterProvider) {
    final todosOsDiarios = gerenteProvider.diariosSincronizados;
    final todasAsParcelas = gerenteProvider.parcelasSincronizadas;
    final todasAsCubagens = gerenteProvider.cubagensSincronizadas;

    // 1. Filtra os diários pelo período e líder
    _diariosFiltrados = _filtrarDiarios(todosOsDiarios, filterProvider);
    
    // 2. Filtra as parcelas pelo mesmo período e líder
    final parcelasNoPeriodo = todasAsParcelas.where((p) {
      if (p.dataColeta == null) return false;
      final liderMatch = filterProvider.lideresSelecionados.isEmpty ||
                         (p.nomeLider != null && filterProvider.lideresSelecionados.contains(p.nomeLider!));
      return _filtroDeData(p.dataColeta, filterProvider) && liderMatch;
    }).toList();

    // 3. Filtra as cubagens pelo mesmo período e líder
    final cubagensNoPeriodo = todasAsCubagens.where((c) {
      if (c.dataColeta == null) return false;
      final liderMatch = filterProvider.lideresSelecionados.isEmpty ||
                         (c.nomeLider != null && filterProvider.lideresSelecionados.contains(c.nomeLider!));
      return _filtroDeData(c.dataColeta, filterProvider) && liderMatch;
    }).toList();
    
    // 4. Calcula o total de coletas REALIZADAS (concluídas) DENTRO do período filtrado
    final int parcelasRealizadas = parcelasNoPeriodo
        .where((p) => p.status == StatusParcela.concluida || p.status == StatusParcela.exportada)
        .length;
        
    final int cubagensRealizadas = cubagensNoPeriodo
        .where((c) => c.alturaTotal > 0)
        .length;

    final totalColetasRealizadas = parcelasRealizadas + cubagensRealizadas;

    if (_diariosFiltrados.isEmpty && totalColetasRealizadas == 0) {
      _limparDados();
      notifyListeners();
      return;
    }
    
    // 5. Calcula os KPIs usando o número correto de coletas realizadas
    _calcularKPIs(_diariosFiltrados, totalColetasRealizadas);
    _calcularComposicaoDespesas(_diariosFiltrados);
    _calcularColetasPorEquipe(_diariosFiltrados);
    _calcularCustosPorVeiculo(_diariosFiltrados);
    _diariosFiltrados.sort((a, b) => b.dataRelatorio.compareTo(a.dataRelatorio));

    notifyListeners();
  }
  
  // MÉTODOS DE CÁLCULO (agora privados)

  List<DiarioDeCampo> _filtrarDiarios(List<DiarioDeCampo> todos, OperacoesFilterProvider filterProvider) {
    List<DiarioDeCampo> filtradosPorData;
    final agora = DateTime.now();

    switch (filterProvider.periodo) {
      case PeriodoFiltro.todos:
        filtradosPorData = todos;
        break;
      case PeriodoFiltro.hoje:
        final hoje = DateTime(agora.year, agora.month, agora.day);
        filtradosPorData = todos.where((d) => DateTime.parse(d.dataRelatorio).isAtSameMomentAs(hoje)).toList();
        break;
      case PeriodoFiltro.ultimos7Dias:
        final seteDiasAtras = agora.subtract(const Duration(days: 6));
        final inicioDoDia = DateTime(seteDiasAtras.year, seteDiasAtras.month, seteDiasAtras.day);
        filtradosPorData = todos.where((d) => !DateTime.parse(d.dataRelatorio).isBefore(inicioDoDia)).toList();
        break;
      case PeriodoFiltro.esteMes:
        filtradosPorData = todos.where((d) {
          final dataDiario = DateTime.parse(d.dataRelatorio);
          return dataDiario.year == agora.year && dataDiario.month == agora.month;
        }).toList();
        break;
      case PeriodoFiltro.mesPassado:
        final primeiroDiaDoMesAtual = DateTime(agora.year, agora.month, 1);
        final ultimoDiaMesPassado = primeiroDiaDoMesAtual.subtract(const Duration(days: 1));
        final primeiroDiaMesPassado = DateTime(ultimoDiaMesPassado.year, ultimoDiaMesPassado.month, 1);
        filtradosPorData = todos.where((d) {
          final dataDiario = DateTime.parse(d.dataRelatorio);
          return dataDiario.year == primeiroDiaMesPassado.year && dataDiario.month == primeiroDiaMesPassado.month;
        }).toList();
        break;
      case PeriodoFiltro.personalizado:
        if (filterProvider.periodoPersonalizado != null) {
          final dataFim = filterProvider.periodoPersonalizado!.end.add(const Duration(days: 1));
          filtradosPorData = todos.where((d) {
            final dataDiario = DateTime.parse(d.dataRelatorio);
            return dataDiario.isAfter(filterProvider.periodoPersonalizado!.start.subtract(const Duration(days: 1))) &&
                   dataDiario.isBefore(dataFim);
          }).toList();
        } else {
          filtradosPorData = todos;
        }
        break;
    }

    if (filterProvider.lideresSelecionados.isEmpty) {
      return filtradosPorData;
    } else {
      return filtradosPorData.where((d) => filterProvider.lideresSelecionados.contains(d.nomeLider)).toList();
    }
  }
  
  // <<< FUNÇÃO _filtroDeData ADICIONADA AQUI >>>
  bool _filtroDeData(DateTime? dataColeta, OperacoesFilterProvider filter) {
    if (dataColeta == null) return filter.periodo == PeriodoFiltro.todos;
    if (filter.periodo == PeriodoFiltro.todos) return true;

    final agora = DateTime.now();
    final dataColetaLocal = dataColeta.toLocal(); // Garante comparação na mesma timezone
    
    switch (filter.periodo) {
      case PeriodoFiltro.hoje:
        return dataColetaLocal.year == agora.year &&
            dataColetaLocal.month == agora.month &&
            dataColetaLocal.day == agora.day;
      case PeriodoFiltro.ultimos7Dias:
        return dataColetaLocal.isAfter(agora.subtract(const Duration(days: 7)));
      case PeriodoFiltro.esteMes:
        return dataColetaLocal.year == agora.year && dataColetaLocal.month == agora.month;
      case PeriodoFiltro.mesPassado:
        final primeiroDiaMesAtual = DateTime(agora.year, agora.month, 1);
        final ultimoDiaMesPassado = primeiroDiaMesAtual.subtract(const Duration(days: 1));
        return dataColetaLocal.year == ultimoDiaMesPassado.year &&
            dataColetaLocal.month == ultimoDiaMesPassado.month;
      case PeriodoFiltro.personalizado:
        if (filter.periodoPersonalizado != null) {
          final dataFim = filter.periodoPersonalizado!.end.add(const Duration(days: 1));
          return dataColetaLocal.isAfter(filter.periodoPersonalizado!.start.subtract(const Duration(days: 1))) &&
              dataColetaLocal.isBefore(dataFim);
        }
        return true;
      default:
        return true;
    }
  }
  // <<< FIM DA FUNÇÃO ADICIONADA >>>

  void _calcularKPIs(List<DiarioDeCampo> diarios, int totalColetas) {
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

    _kpis = KpiData(
      coletasRealizadas: totalColetas,
      custoTotalCampo: custoTotal,
      kmRodados: kmTotal,
      custoPorColeta: totalColetas > 0 ? custoTotal / totalColetas : 0.0,
      custoTotalAbastecimento: custoAbastecimentoTotal,
      custoMedioKmGeral: kmTotal > 0 ? custoAbastecimentoTotal / kmTotal : 0.0,
    );
  }

  void _calcularComposicaoDespesas(List<DiarioDeCampo> diarios) {
    double totalAbastecimento = diarios.fold(0.0, (prev, d) => prev + (d.abastecimentoValor ?? 0));
    double totalPedagio = diarios.fold(0.0, (prev, d) => prev + (d.pedagioValor ?? 0));
    double totalAlimentacao = diarios.fold(0.0, (prev, d) => prev + (d.alimentacaoRefeicaoValor ?? 0));
    double totalOutros = diarios.fold(0.0, (prev, d) => prev + (d.outrasDespesasValor ?? 0));

    _composicaoDespesas = {
      'Abastecimento': totalAbastecimento,
      'Alimentação': totalAlimentacao,
      'Pedágio': totalPedagio,
      'Outros': totalOutros,
    };
  }
  
  void _calcularColetasPorEquipe(List<DiarioDeCampo> diarios) {
    final grupo = groupBy(diarios, (DiarioDeCampo d) => d.nomeLider);
    _coletasPorEquipe = grupo.map((lider, listaDiarios) => MapEntry(lider, listaDiarios.length));
  }

  void _calcularCustosPorVeiculo(List<DiarioDeCampo> diarios) {
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

  void _limparDados() {
    _kpis = KpiData();
    _composicaoDespesas = {};
    _coletasPorEquipe = {};
    _custosPorVeiculo = [];
    _diariosFiltrados = [];
  }
}
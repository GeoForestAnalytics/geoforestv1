// lib/providers/operacoes_provider.dart (VERSÃO COM MAIS KPIs PARA OS TOTALIZADORES)

import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geoforestv1/providers/operacoes_filter_provider.dart';
import 'package:intl/intl.dart';

// <<< 1. ATUALIZAÇÃO DO MODELO DE DADOS DOS KPIs >>>
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

  void update(GerenteProvider gerenteProvider, OperacoesFilterProvider filterProvider) {
    final todosOsDiarios = gerenteProvider.diariosSincronizados;
    final todasAsParcelas = gerenteProvider.parcelasSincronizadas;
    final todasAsCubagens = gerenteProvider.cubagensSincronizadas;

    _diariosFiltrados = _filtrarDiarios(todosOsDiarios, filterProvider);
    
    final datasFiltradas = _diariosFiltrados.map((d) => d.dataRelatorio).toSet();
    final lideresFiltrados = _diariosFiltrados.map((d) => d.nomeLider).toSet();

    final parcelasFiltradas = todasAsParcelas.where((p) {
      if (p.dataColeta == null || p.nomeLider == null) return false;
      final dataString = DateFormat('yyyy-MM-dd').format(p.dataColeta!);
      final liderMatch = lideresFiltrados.isEmpty || lideresFiltrados.contains(p.nomeLider!);
      return datasFiltradas.contains(dataString) && liderMatch;
    }).toList();

    final cubagensFiltradas = todasAsCubagens.where((c) {
      if (c.dataColeta == null || c.nomeLider == null) return false;
      final dataString = DateFormat('yyyy-MM-dd').format(c.dataColeta!);
      final liderMatch = lideresFiltrados.isEmpty || lideresFiltrados.contains(c.nomeLider!);
      return datasFiltradas.contains(dataString) && liderMatch;
    }).toList();

    final totalColetasFiltradas = parcelasFiltradas.length + cubagensFiltradas.length;

    if (_diariosFiltrados.isEmpty && totalColetasFiltradas == 0) {
      _limparDados();
      return;
    }
    
    _calcularKPIs(_diariosFiltrados, totalColetasFiltradas);
    _calcularComposicaoDespesas(_diariosFiltrados);
    _calcularColetasPorEquipe(_diariosFiltrados);
    _calcularCustosPorVeiculo(_diariosFiltrados);
    _diariosFiltrados.sort((a, b) => b.dataRelatorio.compareTo(a.dataRelatorio));

    notifyListeners();
  }
  
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

  // <<< 2. ATUALIZAÇÃO DOS CÁLCULOS GERAIS (KPIs) >>>
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
    notifyListeners();
  }
}
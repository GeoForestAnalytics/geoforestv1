// lib/providers/operacoes_provider.dart

import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geoforestv1/providers/operacoes_filter_provider.dart';
import 'package:geoforestv1/models/parcela_model.dart'; 
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:intl/intl.dart'; // Importante para datas

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
  
  // Mapa que vincula ID do Diário -> Quantidade Produzida naquele dia
  Map<int, int> _producaoPorDiario = {};

  KpiData get kpis => _kpis;
  Map<String, double> get composicaoDespesas => _composicaoDespesas;
  Map<String, int> get coletasPorEquipe => _coletasPorEquipe;
  List<CustoPorVeiculo> get custosPorVeiculo => _custosPorVeiculo;
  List<DiarioDeCampo> get diariosFiltrados => _diariosFiltrados;
  Map<int, int> get producaoPorDiario => _producaoPorDiario;

  void update(GerenteProvider gerenteProvider, OperacoesFilterProvider filterProvider) {
    final todosOsDiarios = gerenteProvider.diariosSincronizados;
    final todasAsParcelas = gerenteProvider.parcelasSincronizadas;
    final todasAsCubagens = gerenteProvider.cubagensSincronizadas;

    // 1. Filtra os diários (Base Financeira)
    _diariosFiltrados = _filtrarDiarios(todosOsDiarios, filterProvider);
    
    // 2. Prepara listas de tudo que foi REALIZADO (Concluído/Exportado) e tem data
    final parcelasCandidatas = todasAsParcelas.where((p) => 
      p.dataColeta != null && 
      (p.status == StatusParcela.concluida || p.status == StatusParcela.exportada)
    ).toList();

    final cubagensCandidatas = todasAsCubagens.where((c) => 
      c.dataColeta != null && c.alturaTotal > 0
    ).toList();

    // 3. REALIZA O "CASAMENTO" (JOIN) DE DADOS
    _producaoPorDiario = {};
    int totalProducaoVinculada = 0;

    for (var diario in _diariosFiltrados) {
      if (diario.id == null) continue;

      // Normaliza dados do DIÁRIO para comparação segura
      // Data vem como String 'YYYY-MM-DD'
      DateTime? dataDiario;
      try {
        dataDiario = DateTime.parse(diario.dataRelatorio);
      } catch (_) { continue; }

      final nomeLiderDiario = diario.nomeLider.trim().toLowerCase(); 

      // Conta Parcelas que batem com este diário
      final qtdParcelas = parcelasCandidatas.where((p) {
        final pData = p.dataColeta!;
        
        // Compara apenas ANO, MÊS e DIA
        final bool dataBate = pData.year == dataDiario!.year && 
                              pData.month == dataDiario.month && 
                              pData.day == dataDiario.day;
        
        if (!dataBate) return false;

        // Compara Nome (insensível a maiúsculas/espaços)
        final pLider = (p.nomeLider ?? '').trim().toLowerCase();
        // Se a parcela não tiver líder (importação antiga), assume que é do dono do diário
        if (pLider.isEmpty) return true; 

        return pLider == nomeLiderDiario;
      }).length;

      // Conta Cubagens que batem com este diário
      final qtdCubagens = cubagensCandidatas.where((c) {
        final cData = c.dataColeta!;
        
        final bool dataBate = cData.year == dataDiario!.year && 
                              cData.month == dataDiario.month && 
                              cData.day == dataDiario.day;

        if (!dataBate) return false;

        final cLider = (c.nomeLider ?? '').trim().toLowerCase();
        if (cLider.isEmpty) return true;

        return cLider == nomeLiderDiario;
      }).length;

      final producaoTotalDia = qtdParcelas + qtdCubagens;
      
      // Salva no mapa para a tabela
      _producaoPorDiario[diario.id!] = producaoTotalDia;
      
      // Soma ao total geral
      totalProducaoVinculada += producaoTotalDia;
    }

    if (_diariosFiltrados.isEmpty) {
      _limparDados();
      notifyListeners();
      return;
    }
    
    // 4. Calcula KPIs usando a produção que conseguimos vincular
    _calcularKPIs(_diariosFiltrados, totalProducaoVinculada);
    _calcularComposicaoDespesas(_diariosFiltrados);
    
    // Para o gráfico de pizza, usamos a lista total de itens realizados no período
    // (mesmo que por algum motivo não tenha casado com o diário, a produção existiu)
    _calcularColetasPorEquipe(parcelasCandidatas, cubagensCandidatas); 
    
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
        final hojeStr = DateFormat('yyyy-MM-dd').format(agora);
        filtradosPorData = todos.where((d) => d.dataRelatorio == hojeStr).toList();
        break;
      case PeriodoFiltro.ultimos7Dias:
        final seteDiasAtras = agora.subtract(const Duration(days: 6));
        final dataCorte = DateFormat('yyyy-MM-dd').format(seteDiasAtras);
        filtradosPorData = todos.where((d) => d.dataRelatorio.compareTo(dataCorte) >= 0).toList();
        break;
      case PeriodoFiltro.esteMes:
        filtradosPorData = todos.where((d) {
          final dt = DateTime.parse(d.dataRelatorio);
          return dt.year == agora.year && dt.month == agora.month;
        }).toList();
        break;
      case PeriodoFiltro.mesPassado:
        final dataMesPassado = DateTime(agora.year, agora.month - 1, 1);
        filtradosPorData = todos.where((d) {
           final dt = DateTime.parse(d.dataRelatorio);
           return dt.year == dataMesPassado.year && dt.month == dataMesPassado.month;
        }).toList();
        break;
      case PeriodoFiltro.personalizado:
        if (filterProvider.periodoPersonalizado != null) {
          final inicio = filterProvider.periodoPersonalizado!.start;
          final fim = filterProvider.periodoPersonalizado!.end.add(const Duration(days: 1));
          filtradosPorData = todos.where((d) {
            final dt = DateTime.parse(d.dataRelatorio);
            return dt.isAfter(inicio.subtract(const Duration(seconds: 1))) && dt.isBefore(fim);
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

  void _calcularKPIs(List<DiarioDeCampo> diarios, int totalColetasVinculadas) {
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
      coletasRealizadas: totalColetasVinculadas, // Agora exibe a SOMA DA PRODUÇÃO
      custoTotalCampo: custoTotal,
      kmRodados: kmTotal,
      // Custo Médio por Amostra
      custoPorColeta: totalColetasVinculadas > 0 ? custoTotal / totalColetasVinculadas : 0.0,
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
  
  void _calcularColetasPorEquipe(List<Parcela> parcelas, List<CubagemArvore> cubagens) {
    final List<Map<String, String?>> allItems = [
      ...parcelas.map((p) => {'lider': p.nomeLider}),
      ...cubagens.map((c) => {'lider': c.nomeLider}),
    ];

    final grupo = groupBy(allItems, (item) => item['lider'] ?? 'Gerente');
    _coletasPorEquipe = grupo.map((lider, items) => MapEntry(lider, items.length));
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
    _producaoPorDiario = {};
    _custosPorVeiculo = [];
    _diariosFiltrados = [];
  }
}
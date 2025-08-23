// lib/providers/dashboard_metrics_provider.dart (VERSÃO CORRIGIDA)

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geoforestv1/providers/dashboard_filter_provider.dart';
import 'package:geoforestv1/services/analysis_service.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

class ProgressoFazenda {
  final String nome;
  final int totalParcelas;
  final int concluidas;
  final double progresso;

  ProgressoFazenda({
    required this.nome,
    required this.totalParcelas,
    required this.concluidas,
    required this.progresso,
  });
}

class DesempenhoFazenda {
  final String nomeAtividade;
  final String nomeFazenda;
  final int pendentes;
  final int emAndamento;
  final int concluidas;
  final int exportadas;
  final int total;
  DesempenhoFazenda({
    required this.nomeAtividade,
    required this.nomeFazenda,
    this.pendentes = 0,
    this.emAndamento = 0,
    this.concluidas = 0,
    this.exportadas = 0,
    this.total = 0,
  });
}

class DesempenhoFazendaTotais {
  final int pendentes;
  final int emAndamento;
  final int concluidas;
  final int exportadas;
  final int total;
  DesempenhoFazendaTotais(
      {this.pendentes = 0,
      this.emAndamento = 0,
      this.concluidas = 0,
      this.exportadas = 0,
      this.total = 0});
}

class DashboardMetricsProvider with ChangeNotifier {
  List<Parcela> _parcelasFiltradas = [];
  List<CubagemArvore> _cubagensFiltradas = [];

  List<DesempenhoFazenda> _desempenhoPorCubagem = [];
  Map<String, int> _progressoPorEquipe = {};
  Map<String, int> _coletasPorAtividade = {};
  Map<String, int> _coletasPorMes = {};
  List<DesempenhoFazenda> _desempenhoPorFazenda = [];
  List<ProgressoFazenda> _progressoPorFazenda = [];
  DesempenhoFazendaTotais _desempenhoInventarioTotais = DesempenhoFazendaTotais();
  DesempenhoFazendaTotais _desempenhoCubagemTotais = DesempenhoFazendaTotais();

  double _volumeTotalColetado = 0.0;
  int _totalAmostrasConcluidas = 0;
  int _totalCubagensConcluidas = 0;
  double _mediaDiariaColetas = 0.0;

  List<Parcela> get parcelasFiltradas => _parcelasFiltradas;
  List<DesempenhoFazenda> get desempenhoPorCubagem => _desempenhoPorCubagem;
  Map<String, int> get progressoPorEquipe => _progressoPorEquipe;
  Map<String, int> get coletasPorAtividade => _coletasPorAtividade;
  Map<String, int> get coletasPorMes => _coletasPorMes;
  List<DesempenhoFazenda> get desempenhoPorFazenda => _desempenhoPorFazenda;
  List<ProgressoFazenda> get progressoPorFazenda => _progressoPorFazenda;
  DesempenhoFazendaTotais get desempenhoInventarioTotais => _desempenhoInventarioTotais;
  DesempenhoFazendaTotais get desempenhoCubagemTotais => _desempenhoCubagemTotais;
  double get volumeTotalColetado => _volumeTotalColetado;
  int get totalAmostrasConcluidas => _totalAmostrasConcluidas;
  int get totalCubagensConcluidas => _totalCubagensConcluidas;
  double get mediaDiariaColetas => _mediaDiariaColetas;

  final AnalysisService _analysisService = AnalysisService();

  void update(GerenteProvider gerenteProvider, DashboardFilterProvider filterProvider) {
    debugPrint("METRICS PROVIDER UPDATE: Recebeu ${gerenteProvider.parcelasSincronizadas.length} parcelas para calcular.");

    final lideres = {
      ...gerenteProvider.parcelasSincronizadas.map((p) => p.nomeLider),
      ...gerenteProvider.cubagensSincronizadas.map((c) => c.nomeLider),
    }.where((nome) => nome != null && nome.isNotEmpty).cast<String>().toSet().toList();
    
    filterProvider.updateLideresDisponiveis(lideres);

    final projetosAtivos = gerenteProvider.projetos.where((p) => p.status == 'ativo').toList();
    final Map<int, String> atividadeIdToTipoMap = { for (var a in gerenteProvider.atividades) if (a.id != null) a.id!: a.tipo };

    _recalcularParcelasFiltradas(
      gerenteProvider.parcelasSincronizadas,
      projetosAtivos,
      filterProvider,
      gerenteProvider,
    );

    _cubagensFiltradas = _filtrarCubagens(
      gerenteProvider.cubagensSincronizadas,
      gerenteProvider.talhaoToProjetoMap,
      projetosAtivos,
      filterProvider,
      gerenteProvider,
    );

    _recalcularDesempenhoPorCubagem(gerenteProvider.talhaoToAtividadeMap, atividadeIdToTipoMap);
    _recalcularKpisDeProjeto(gerenteProvider);
    _recalcularProgressoPorEquipe();
    _recalcularColetasPorAtividade(gerenteProvider);
    _recalcularColetasPorMes();
    _recalcularMediaDiariaColetas(filterProvider);
    _recalcularDesempenhoPorFazenda();
    _recalcularProgressoPorFazenda();

    notifyListeners();
  }

  void _recalcularParcelasFiltradas(
    List<Parcela> todasAsParcelas,
    List<Projeto> projetosAtivos,
    DashboardFilterProvider filterProvider,
    GerenteProvider gerenteProvider,
  ) {
    final idsProjetosAtivos = projetosAtivos.map((p) => p.id!).toSet();

    _parcelasFiltradas = todasAsParcelas.where((p) {
      if (filterProvider.selectedProjetoIds.isNotEmpty) {
        if (p.projetoId == null || !filterProvider.selectedProjetoIds.contains(p.projetoId)) return false;
      } else {
        if (p.projetoId == null || !idsProjetosAtivos.contains(p.projetoId)) return false;
      }

      // <<< MUDANÇA: Lógica de filtro por tipo de atividade >>>
      if (filterProvider.selectedAtividadeTipos.isNotEmpty) {
        final atividadeId = gerenteProvider.talhaoToAtividadeMap[p.talhaoId];
        final atividade = gerenteProvider.atividades.firstWhereOrNull((a) => a.id == atividadeId);
        if (atividade == null || !filterProvider.selectedAtividadeTipos.contains(atividade.tipo)) {
          return false;
        }
      }

      if (filterProvider.selectedFazendaNomes.isNotEmpty) {
        if (p.nomeFazenda == null || !filterProvider.selectedFazendaNomes.contains(p.nomeFazenda!)) return false;
      }

      if (filterProvider.lideresSelecionados.isNotEmpty) {
        final nomeLider = p.nomeLider?.isNotEmpty == true ? p.nomeLider! : 'Gerente';
        if (!filterProvider.lideresSelecionados.contains(nomeLider)) return false;
      }

      return _filtroDeData(p.dataColeta, filterProvider);
    }).toList();
  }

  List<CubagemArvore> _filtrarCubagens(
    List<CubagemArvore> todasAsCubagens,
    Map<int, int> talhaoToProjetoMap,
    List<Projeto> projetosAtivos,
    DashboardFilterProvider filterProvider,
    GerenteProvider gerenteProvider,
  ) {
    final idsProjetosAtivos = projetosAtivos.map((p) => p.id).toSet();
    return todasAsCubagens.where((c) {
      final projetoId = talhaoToProjetoMap[c.talhaoId];

      if (filterProvider.selectedProjetoIds.isNotEmpty) {
        if (projetoId == null || !filterProvider.selectedProjetoIds.contains(projetoId)) return false;
      } else {
        if (projetoId == null || !idsProjetosAtivos.contains(projetoId)) return false;
      }

      // <<< MUDANÇA: Lógica de filtro por tipo de atividade >>>
      if (filterProvider.selectedAtividadeTipos.isNotEmpty) {
        final atividadeId = gerenteProvider.talhaoToAtividadeMap[c.talhaoId];
        final atividade = gerenteProvider.atividades.firstWhereOrNull((a) => a.id == atividadeId);
        if (atividade == null || !filterProvider.selectedAtividadeTipos.contains(atividade.tipo)) {
          return false;
        }
      }

      if (filterProvider.selectedFazendaNomes.isNotEmpty) {
        if (!filterProvider.selectedFazendaNomes.contains(c.nomeFazenda)) return false;
      }

      if (filterProvider.lideresSelecionados.isNotEmpty) {
        final nomeLider = c.nomeLider?.isNotEmpty == true ? c.nomeLider! : 'Gerente';
        if (!filterProvider.lideresSelecionados.contains(nomeLider)) return false;
      }

      return _filtroDeData(c.dataColeta, filterProvider);
    }).toList();
  }

  void _recalcularKpisDeProjeto(GerenteProvider gerenteProvider) {
    final parcelasConcluidas = _parcelasFiltradas
        .where((p) =>
            p.status == StatusParcela.concluida ||
            p.status == StatusParcela.exportada)
        .toList();

    _totalAmostrasConcluidas = parcelasConcluidas.length;
    _totalCubagensConcluidas = _cubagensFiltradas.where((c) => c.alturaTotal > 0).length;

    if (parcelasConcluidas.isEmpty) {
      _volumeTotalColetado = 0.0;
      return;
    }

    final parcelasPorTalhao = groupBy(parcelasConcluidas, (Parcela p) => p.talhaoId);
    double volumeTotalAcumulado = 0.0;

    parcelasPorTalhao.forEach((talhaoId, parcelasDoTalhao) {
      if (talhaoId == null) return;
      
      final todasAsArvoresDoTalhao = parcelasDoTalhao
          .expand((p) => p.arvores)
          .toList();

      if (todasAsArvoresDoTalhao.isEmpty) return;
      
      final analiseTalhao = _analysisService.getTalhaoInsights(parcelasDoTalhao, todasAsArvoresDoTalhao);
      final volumeHaDoTalhao = analiseTalhao.volumePorHectare;

      final talhaoInfo = gerenteProvider.talhoes.firstWhereOrNull((t) => t.id == talhaoId);
      final areaHaDoTalhao = talhaoInfo?.areaHa ?? 0.0;

      if (areaHaDoTalhao > 0) {
        volumeTotalAcumulado += volumeHaDoTalhao * areaHaDoTalhao;
      }
    });

    _volumeTotalColetado = volumeTotalAcumulado;
  }
  
  void _recalcularMediaDiariaColetas(DashboardFilterProvider filter) {
    final List<DateTime> datasColetas = [
      ..._parcelasFiltradas.where((p) => p.status == StatusParcela.concluida || p.status == StatusParcela.exportada).map((p) => p.dataColeta),
      ..._cubagensFiltradas.where((c) => c.alturaTotal > 0).map((c) => c.dataColeta),
    ].whereType<DateTime>().toList();

    if (datasColetas.isEmpty) {
      _mediaDiariaColetas = 0.0;
      return;
    }

    final totalColetas = datasColetas.length;
    
    int diasNoPeriodo = 1;
    if(filter.periodo == PeriodoFiltro.todos) {
        if(datasColetas.length > 1) {
            datasColetas.sort();
            diasNoPeriodo = datasColetas.last.difference(datasColetas.first).inDays + 1;
        }
    } else if (filter.periodo == PeriodoFiltro.personalizado && filter.periodoPersonalizado != null) {
        diasNoPeriodo = filter.periodoPersonalizado!.duration.inDays + 1;
    } else if (filter.periodo == PeriodoFiltro.ultimos7Dias) {
        diasNoPeriodo = 7;
    } else if (filter.periodo == PeriodoFiltro.esteMes) {
        final now = DateTime.now();
        diasNoPeriodo = DateTime(now.year, now.month + 1, 0).day;
    } else if (filter.periodo == PeriodoFiltro.mesPassado) {
        final now = DateTime.now();
        diasNoPeriodo = DateTime(now.year, now.month, 0).day;
    }
    
    _mediaDiariaColetas = diasNoPeriodo > 0 ? totalColetas / diasNoPeriodo : 0.0;
  }
  
  void _recalcularColetasPorAtividade(GerenteProvider gerenteProvider) {
    final List<dynamic> todasAsColetasConcluidas = [
      ..._parcelasFiltradas.where((p) => p.status == StatusParcela.concluida || p.status == StatusParcela.exportada), 
      ..._cubagensFiltradas.where((c) => c.alturaTotal > 0)
    ];
    
    if (todasAsColetasConcluidas.isEmpty) {
      _coletasPorAtividade = {};
      return;
    }

    final grupoPorAtividadeId = groupBy(todasAsColetasConcluidas, (coleta) {
      int? talhaoId;
      if (coleta is Parcela) talhaoId = coleta.talhaoId;
      if (coleta is CubagemArvore) talhaoId = coleta.talhaoId;
      return gerenteProvider.talhaoToAtividadeMap[talhaoId];
    });

    final mapaContagem = grupoPorAtividadeId.map((atividadeId, listaColetas) {
      final atividade = gerenteProvider.atividades.firstWhereOrNull((a) => a.id == atividadeId);
      final nomeAtividade = atividade?.tipo ?? 'Desconhecida';
      return MapEntry(nomeAtividade, listaColetas.length);
    });

    _coletasPorAtividade = Map.fromEntries(
        mapaContagem.entries.toList()..sort((a, b) => b.value.compareTo(a.value))
    );
  }

  void _recalcularProgressoPorFazenda() {
    if (_parcelasFiltradas.isEmpty) {
      _progressoPorFazenda = [];
      return;
    }
    final grupoPorFazenda = groupBy(_parcelasFiltradas, (Parcela p) => p.nomeFazenda ?? 'Fazenda Desconhecida');
    _progressoPorFazenda = grupoPorFazenda.entries.map((entry) {
      final nomeFazenda = entry.key;
      final parcelasDaFazenda = entry.value;
      final total = parcelasDaFazenda.length;
      final concluidas = parcelasDaFazenda
          .where((p) =>
              p.status == StatusParcela.concluida ||
              p.status == StatusParcela.exportada)
          .length;
      final progresso = (total > 0) ? concluidas / total : 0.0;
      return ProgressoFazenda(
        nome: nomeFazenda,
        totalParcelas: total,
        concluidas: concluidas,
        progresso: progresso,
      );
    }).toList();
  }

  void _recalcularDesempenhoPorCubagem(
    Map<int, int> talhaoToAtividadeMap,
    Map<int, String> atividadeIdToTipoMap,
  ) {
    if (_cubagensFiltradas.isEmpty) {
      _desempenhoPorCubagem = [];
      _desempenhoCubagemTotais = DesempenhoFazendaTotais();
      return;
    }
    final grupoPorAtividadeEFazenda =
        groupBy(_cubagensFiltradas, (CubagemArvore c) {
      final atividadeId = talhaoToAtividadeMap[c.talhaoId];
      final tipoAtividade =
          atividadeId != null ? atividadeIdToTipoMap[atividadeId] : "N/A";
      return "$tipoAtividade:::${c.nomeFazenda}";
    });
    _desempenhoPorCubagem = grupoPorAtividadeEFazenda.entries.map((entry) {
      final parts = entry.key.split(':::');
      final nomeAtividade = parts[0];
      final nomeFazenda = parts[1];
      final cubagens = entry.value;
      return DesempenhoFazenda(
        nomeAtividade: nomeAtividade,
        nomeFazenda: nomeFazenda,
        pendentes:
            cubagens.where((c) => c.alturaTotal == 0 && !c.exportada).length,
        emAndamento: 0,
        concluidas:
            cubagens.where((c) => c.alturaTotal > 0 && !c.exportada).length,
        exportadas: cubagens.where((c) => c.exportada).length,
        total: cubagens.length,
      );
    }).toList()
      ..sort((a, b) => '${a.nomeAtividade}-${a.nomeFazenda}'
          .compareTo('${b.nomeAtividade}-${b.nomeFazenda}'));
    _desempenhoCubagemTotais = _desempenhoPorCubagem.fold(
        DesempenhoFazendaTotais(),
        (totais, item) => DesempenhoFazendaTotais(
              pendentes: totais.pendentes + item.pendentes,
              concluidas: totais.concluidas + item.concluidas,
              exportadas: totais.exportadas + item.exportadas,
              total: totais.total + item.total,
            ));
  }
  
  void _recalcularProgressoPorEquipe() {
    final parcelasConcluidas = _parcelasFiltradas
        .where((p) =>
            p.status == StatusParcela.concluida ||
            p.status == StatusParcela.exportada)
        .toList();
    if (parcelasConcluidas.isEmpty) {
      _progressoPorEquipe = {};
      return;
    }
    final grupoPorEquipe = groupBy(
        parcelasConcluidas,
        (Parcela p) =>
            p.nomeLider?.isNotEmpty == true ? p.nomeLider! : 'Gerente');
    final mapaContagem = grupoPorEquipe
        .map((nomeEquipe, listaParcelas) => MapEntry(nomeEquipe, listaParcelas.length));
    final sortedEntries = mapaContagem.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _progressoPorEquipe = Map.fromEntries(sortedEntries);
  }

  void _recalcularColetasPorMes() {
    final parcelas = _parcelasFiltradas
        .where((p) => p.status == StatusParcela.concluida && p.dataColeta != null)
        .toList();
    if (parcelas.isEmpty) {
      _coletasPorMes = {};
      return;
    }
    final grupoPorMes = groupBy(parcelas,
        (Parcela p) => DateFormat('MMM/yy', 'pt_BR').format(p.dataColeta!));
    final mapaContagem =
        grupoPorMes.map((mes, lista) => MapEntry(mes, lista.length));
    final chavesOrdenadas = mapaContagem.keys.toList()
      ..sort((a, b) {
        try {
          final dataA = DateFormat('MMM/yy', 'pt_BR').parse(a);
          final dataB = DateFormat('MMM/yy', 'pt_BR').parse(b);
          return dataA.compareTo(dataB);
        } catch (e) {
          return 0;
        }
      });
    _coletasPorMes = {for (var key in chavesOrdenadas) key: mapaContagem[key]!};
  }

  void _recalcularDesempenhoPorFazenda() {
    if (_parcelasFiltradas.isEmpty) {
      _desempenhoPorFazenda = [];
      _desempenhoInventarioTotais = DesempenhoFazendaTotais();
      return;
    }
    final grupoPorFazendaEAtividade = groupBy(
        _parcelasFiltradas,
        (Parcela p) =>
            "${p.atividadeTipo ?? 'N/A'}:::${p.nomeFazenda ?? 'Fazenda Desconhecida'}");
    _desempenhoPorFazenda = grupoPorFazendaEAtividade.entries.map((entry) {
      final parts = entry.key.split(':::');
      final nomeAtividade = parts[0];
      final nomeFazenda = parts[1];
      final parcelas = entry.value;
      return DesempenhoFazenda(
        nomeAtividade: nomeAtividade,
        nomeFazenda: nomeFazenda,
        pendentes:
            parcelas.where((p) => p.status == StatusParcela.pendente).length,
        emAndamento:
            parcelas.where((p) => p.status == StatusParcela.emAndamento).length,
        concluidas: parcelas
            .where((p) =>
                p.status == StatusParcela.concluida ||
                p.status == StatusParcela.exportada)
            .length,
        exportadas: parcelas.where((p) => p.exportada).length,
        total: parcelas.length,
      );
    }).toList()
      ..sort((a, b) => '${a.nomeAtividade}-${a.nomeFazenda}'
          .compareTo('${b.nomeAtividade}-${b.nomeFazenda}'));
    _desempenhoInventarioTotais = _desempenhoPorFazenda.fold(
        DesempenhoFazendaTotais(),
        (totais, item) => DesempenhoFazendaTotais(
              pendentes: totais.pendentes + item.pendentes,
              emAndamento: totais.emAndamento + item.emAndamento,
              concluidas: totais.concluidas + item.concluidas,
              exportadas: totais.exportadas + item.exportadas,
              total: totais.total + item.total,
            ));
  }
  
  bool _filtroDeData(DateTime? dataColeta, DashboardFilterProvider filter) {
    if (dataColeta == null) return filter.periodo == PeriodoFiltro.todos;
    if (filter.periodo == PeriodoFiltro.todos) return true;

    final agora = DateTime.now();
    switch (filter.periodo) {
      case PeriodoFiltro.hoje:
        return dataColeta.year == agora.year &&
            dataColeta.month == agora.month &&
            dataColeta.day == agora.day;
      case PeriodoFiltro.ultimos7Dias:
        return dataColeta.isAfter(agora.subtract(const Duration(days: 7)));
      case PeriodoFiltro.esteMes:
        return dataColeta.year == agora.year && dataColeta.month == agora.month;
      case PeriodoFiltro.mesPassado:
        final primeiroDiaMesAtual = DateTime(agora.year, agora.month, 1);
        final ultimoDiaMesPassado =
            primeiroDiaMesAtual.subtract(const Duration(days: 1));
        return dataColeta.year == ultimoDiaMesPassado.year &&
            dataColeta.month == ultimoDiaMesPassado.month;
      case PeriodoFiltro.personalizado:
        if (filter.periodoPersonalizado != null) {
          final dataFim =
              filter.periodoPersonalizado!.end.add(const Duration(days: 1));
          return dataColeta.isAfter(filter.periodoPersonalizado!.start
                  .subtract(const Duration(days: 1))) &&
              dataColeta.isBefore(dataFim);
        }
        return true;
      default:
        return true;
    }
  }
}
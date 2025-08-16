// lib/providers/dashboard_metrics_provider.dart (VERSÃO COM AGRUPAMENTO DE CUBAGEM CORRIGIDO)

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geoforestv1/providers/dashboard_filter_provider.dart';
import 'package:intl/intl.dart';

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

// Removido o DesempenhoCubagem, pois usaremos o DesempenhoFazenda para ambos.

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
    this.total = 0 
  });
}


class DashboardMetricsProvider with ChangeNotifier {
  
  List<Parcela> _parcelasFiltradas = [];
  // <<< MUDANÇA 1: A lista de cubagem agora usa o mesmo modelo da de inventário >>>
  List<DesempenhoFazenda> _desempenhoPorCubagem = [];
  Map<String, int> _progressoPorEquipe = {};
  Map<String, int> _coletasPorMes = {};
  List<DesempenhoFazenda> _desempenhoPorFazenda = [];
  List<ProgressoFazenda> _progressoPorFazenda = [];
  
  List<Parcela> get parcelasFiltradas => _parcelasFiltradas;
  // <<< MUDANÇA 2: O getter é atualizado para o novo tipo >>>
  List<DesempenhoFazenda> get desempenhoPorCubagem => _desempenhoPorCubagem;
  Map<String, int> get progressoPorEquipe => _progressoPorEquipe;
  Map<String, int> get coletasPorMes => _coletasPorMes;
  List<DesempenhoFazenda> get desempenhoPorFazenda => _desempenhoPorFazenda;
  List<ProgressoFazenda> get progressoPorFazenda => _progressoPorFazenda;

  void update(GerenteProvider gerenteProvider, DashboardFilterProvider filterProvider) {
    debugPrint("METRICS PROVIDER UPDATE: Recebeu ${gerenteProvider.parcelasSincronizadas.length} parcelas para calcular.");
    final projetosAtivos = gerenteProvider.projetos.where((p) => p.status == 'ativo').toList();
    final Map<int, String> atividadeIdToTipoMap = { for (var a in gerenteProvider.atividades) if (a.id != null) a.id!: a.tipo };

    _recalcularParcelasFiltradas(
      gerenteProvider.parcelasSincronizadas,
      projetosAtivos,
      filterProvider,
    );

    _recalcularDesempenhoPorCubagem(
      gerenteProvider.cubagensSincronizadas,
      gerenteProvider.talhaoToProjetoMap,
      gerenteProvider.talhaoToAtividadeMap,
      atividadeIdToTipoMap,
      projetosAtivos,
      filterProvider,
    );
    _recalcularProgressoPorEquipe(filterProvider);
    _recalcularColetasPorMes(filterProvider);
    _recalcularDesempenhoPorFazenda(filterProvider);
    _recalcularProgressoPorFazenda();
    
    notifyListeners();
  }
  
  void _recalcularParcelasFiltradas(List<Parcela> todasAsParcelas, List<Projeto> projetosAtivos, DashboardFilterProvider filterProvider) {
    final idsProjetosAtivos = projetosAtivos.map((p) => p.id!).toSet();
    
    List<Parcela> parcelasVisiveis;

    if (filterProvider.selectedProjetoIds.isEmpty) {
      parcelasVisiveis = todasAsParcelas
          .where((p) => p.projetoId != null && idsProjetosAtivos.contains(p.projetoId))
          .toList();
    } else {
      parcelasVisiveis = todasAsParcelas
          .where((p) => p.projetoId != null && filterProvider.selectedProjetoIds.contains(p.projetoId))
          .toList();
    }
    
    _parcelasFiltradas = parcelasVisiveis;
  }
  
  void _recalcularProgressoPorFazenda() {
    if (_parcelasFiltradas.isEmpty) {
      _progressoPorFazenda = [];
      return;
    }

    final grupoPorFazenda = groupBy(
      _parcelasFiltradas,
      (Parcela p) => p.nomeFazenda ?? 'Fazenda Desconhecida'
    );

    _progressoPorFazenda = grupoPorFazenda.entries.map((entry) {
      final nomeFazenda = entry.key;
      final parcelasDaFazenda = entry.value;

      final total = parcelasDaFazenda.length;
      final concluidas = parcelasDaFazenda
          .where((p) => p.status == StatusParcela.concluida || p.status == StatusParcela.exportada)
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

  // <<< MUDANÇA 3: A função inteira é reescrita para agrupar por fazenda e usar o modelo DesempenhoFazenda >>>
  void _recalcularDesempenhoPorCubagem(
    List<CubagemArvore> todasAsCubagens,
    Map<int, int> talhaoToProjetoMap,
    Map<int, int> talhaoToAtividadeMap,
    Map<int, String> atividadeIdToTipoMap,
    List<Projeto> projetosAtivos,
    DashboardFilterProvider filterProvider,
  ) {
    List<CubagemArvore> cubagensFiltradas;

    if (filterProvider.selectedProjetoIds.isEmpty) {
      final idsProjetosAtivos = projetosAtivos.map((p) => p.id).toSet();
      cubagensFiltradas = todasAsCubagens.where((c) {
        final projetoId = talhaoToProjetoMap[c.talhaoId];
        return projetoId != null && idsProjetosAtivos.contains(projetoId);
      }).toList();
    } else {
      cubagensFiltradas = todasAsCubagens.where((c) {
        final projetoId = talhaoToProjetoMap[c.talhaoId];
        return projetoId != null &&
            filterProvider.selectedProjetoIds.contains(projetoId);
      }).toList();
    }

    if (filterProvider.selectedFazendaNomes.isNotEmpty) {
      cubagensFiltradas = cubagensFiltradas
          .where((c) =>
              filterProvider.selectedFazendaNomes.contains(c.nomeFazenda))
          .toList();
    }

    if (cubagensFiltradas.isEmpty) {
      _desempenhoPorCubagem = [];
      return;
    }

    // Agrupa por uma chave combinada de Atividade e Fazenda
    final grupoPorAtividadeEFazenda =
        groupBy(cubagensFiltradas, (CubagemArvore c) {
      final atividadeId = talhaoToAtividadeMap[c.talhaoId];
      final tipoAtividade = atividadeId != null ? atividadeIdToTipoMap[atividadeId] : "N/A";
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
        pendentes: cubagens.where((c) => c.alturaTotal == 0 && !c.exportada).length,
        emAndamento: 0, // Cubagem não tem estado "em andamento"
        concluidas: cubagens.where((c) => c.alturaTotal > 0 && !c.exportada).length,
        exportadas: cubagens.where((c) => c.exportada).length,
        total: cubagens.length,
      );
    }).toList()
      ..sort((a, b) => '${a.nomeAtividade}-${a.nomeFazenda}'.compareTo('${b.nomeAtividade}-${b.nomeFazenda}'));
  }
  
  void _recalcularProgressoPorEquipe(DashboardFilterProvider filterProvider) {
    final parcelasVisiveis = filterProvider.selectedFazendaNomes.isNotEmpty
      ? _parcelasFiltradas.where((p) => p.nomeFazenda != null && filterProvider.selectedFazendaNomes.contains(p.nomeFazenda!)).toList()
      : _parcelasFiltradas;

    final parcelasConcluidas = parcelasVisiveis.where((p) => p.status == StatusParcela.concluida).toList();
    if (parcelasConcluidas.isEmpty) {
      _progressoPorEquipe = {};
      return;
    }
    final grupoPorEquipe = groupBy(parcelasConcluidas, (Parcela p) => p.nomeLider?.isNotEmpty == true ? p.nomeLider! : 'Gerente');
    final mapaContagem = grupoPorEquipe.map((nomeEquipe, listaParcelas) => MapEntry(nomeEquipe, listaParcelas.length));
    final sortedEntries = mapaContagem.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    _progressoPorEquipe = Map.fromEntries(sortedEntries);
  }

  void _recalcularColetasPorMes(DashboardFilterProvider filterProvider) {
    final parcelasVisiveis = filterProvider.selectedFazendaNomes.isNotEmpty
      ? _parcelasFiltradas.where((p) => p.nomeFazenda != null && filterProvider.selectedFazendaNomes.contains(p.nomeFazenda!)).toList()
      : _parcelasFiltradas;
      
    final parcelas = parcelasVisiveis.where((p) => p.status == StatusParcela.concluida && p.dataColeta != null).toList();
    if (parcelas.isEmpty) {
      _coletasPorMes = {};
      return;
    }
    final grupoPorMes = groupBy(parcelas, (Parcela p) => DateFormat('MMM/yy', 'pt_BR').format(p.dataColeta!));
    final mapaContagem = grupoPorMes.map((mes, lista) => MapEntry(mes, lista.length));
    final chavesOrdenadas = mapaContagem.keys.toList()..sort((a, b) {
      try {
        final dataA = DateFormat('MMM/yy', 'pt_BR').parse(a);
        final dataB = DateFormat('MMM/yy', 'pt_BR').parse(b);
        return dataA.compareTo(dataB);
      } catch (e) { return 0; }
    });
    _coletasPorMes = {for (var key in chavesOrdenadas) key: mapaContagem[key]!};
  }

  void _recalcularDesempenhoPorFazenda(DashboardFilterProvider filterProvider) {
    final parcelasVisiveis = filterProvider.selectedFazendaNomes.isNotEmpty
      ? _parcelasFiltradas.where((p) => p.nomeFazenda != null && filterProvider.selectedFazendaNomes.contains(p.nomeFazenda!)).toList()
      : _parcelasFiltradas;

    if (parcelasVisiveis.isEmpty) {
      _desempenhoPorFazenda = [];
      return;
    }
    
    final grupoPorFazendaEAtividade = groupBy(
      parcelasVisiveis, 
      (Parcela p) => "${p.atividadeTipo ?? 'N/A'}:::${p.nomeFazenda ?? 'Fazenda Desconhecida'}"
    );

    _desempenhoPorFazenda = grupoPorFazendaEAtividade.entries.map((entry) {
      final parts = entry.key.split(':::');
      final nomeAtividade = parts[0];
      final nomeFazenda = parts[1];
      final parcelas = entry.value;

      return DesempenhoFazenda(
        nomeAtividade: nomeAtividade,
        nomeFazenda: nomeFazenda,
        pendentes: parcelas.where((p) => p.status == StatusParcela.pendente).length,
        emAndamento: parcelas.where((p) => p.status == StatusParcela.emAndamento).length,
        concluidas: parcelas.where((p) => p.status == StatusParcela.concluida || p.status == StatusParcela.exportada).length,
        exportadas: parcelas.where((p) => p.exportada).length,
        total: parcelas.length,
      );
    }).toList()..sort((a,b) => '${a.nomeAtividade}-${a.nomeFazenda}'.compareTo('${b.nomeAtividade}-${b.nomeFazenda}'));
  }
}
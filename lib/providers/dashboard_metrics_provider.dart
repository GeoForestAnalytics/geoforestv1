// lib/providers/dashboard_metrics_provider.dart (NOVO ARQUIVO)

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geoforestv1/providers/dashboard_filter_provider.dart';
import 'package:intl/intl.dart';

// As classes de modelo de dados (DesempenhoCubagem, DesempenhoFazenda)
// foram movidas do GerenteProvider para cá, pois são diretamente relacionadas
// ao resultado dos cálculos deste provider.

class DesempenhoCubagem {
  final String nome;
  final int pendentes;
  final int concluidas;
  final int exportadas;
  final int total;
  DesempenhoCubagem({ required this.nome, this.pendentes = 0, this.concluidas = 0, this.exportadas = 0, this.total = 0 });
}

class DesempenhoFazenda {
  final String nome;
  final int pendentes;
  final int emAndamento;
  final int concluidas;
  final int exportadas;
  final int total;
  DesempenhoFazenda({ required this.nome, this.pendentes = 0, this.emAndamento = 0, this.concluidas = 0, this.exportadas = 0, this.total = 0 });
}


class DashboardMetricsProvider with ChangeNotifier {
  
  // --- RESULTADOS DOS CÁLCULOS (ESTADO INTERNO) ---
  List<Parcela> _parcelasFiltradas = [];
  List<DesempenhoCubagem> _desempenhoPorCubagem = [];
  Map<String, int> _progressoPorEquipe = {};
  Map<String, int> _coletasPorMes = {};
  List<DesempenhoFazenda> _desempenhoPorFazenda = [];
  
  // --- GETTERS PÚBLICOS ---
  List<Parcela> get parcelasFiltradas => _parcelasFiltradas;
  List<DesempenhoCubagem> get desempenhoPorCubagem => _desempenhoPorCubagem;
  Map<String, int> get progressoPorEquipe => _progressoPorEquipe;
  Map<String, int> get coletasPorMes => _coletasPorMes;
  List<DesempenhoFazenda> get desempenhoPorFazenda => _desempenhoPorFazenda;

  /// Este é o método principal que será chamado sempre que os dados brutos
  /// ou os filtros mudarem. Ele recalcula tudo.
  void update(GerenteProvider gerenteProvider, DashboardFilterProvider filterProvider) {
    // 1. Filtra as parcelas com base nos projetos selecionados
    _recalcularParcelasFiltradas(
      gerenteProvider.parcelasSincronizadas,
      filterProvider.projetosDisponiveis,
      filterProvider.selectedProjetoIds,
    );

    // 2. Recalcula todas as métricas usando os dados já filtrados
    _recalcularDesempenhoPorCubagem(
      gerenteProvider.cubagensSincronizadas,
      gerenteProvider.talhaoToProjetoMap,
      filterProvider.projetosDisponiveis,
      filterProvider.selectedProjetoIds,
    );
    _recalcularProgressoPorEquipe();
    _recalcularColetasPorMes();
    _recalcularDesempenhoPorFazenda();
    
    // 3. Notifica a UI uma única vez após todos os cálculos.
    notifyListeners();
  }

  // --- MÉTODOS DE CÁLCULO PRIVADOS (LÓGICA MOVIDA DO GerenteProvider) ---

  void _recalcularParcelasFiltradas(List<Parcela> todasAsParcelas, List<Projeto> projetosDisponiveis, Set<int> selectedProjetoIds) {
    final idsProjetosAtivos = projetosDisponiveis.map((p) => p.id).toSet();
    List<Parcela> parcelasVisiveis;

    if (selectedProjetoIds.isEmpty) {
      parcelasVisiveis = todasAsParcelas
          .where((p) => idsProjetosAtivos.contains(p.projetoId))
          .toList();
    } else {
      parcelasVisiveis = todasAsParcelas
          .where((p) => selectedProjetoIds.contains(p.projetoId))
          .toList();
    }
    _parcelasFiltradas = parcelasVisiveis;
  }

  void _recalcularDesempenhoPorCubagem(List<CubagemArvore> todasAsCubagens, Map<int, int> talhaoToProjetoMap, List<Projeto> projetosDisponiveis, Set<int> selectedProjetoIds) {
    if (todasAsCubagens.isEmpty) {
      _desempenhoPorCubagem = [];
      return;
    }
    
    List<CubagemArvore> cubagensFiltradas;
    if (selectedProjetoIds.isEmpty) {
       final idsProjetosAtivos = projetosDisponiveis.map((p) => p.id).toSet();
       cubagensFiltradas = todasAsCubagens.where((c) {
         final projetoId = talhaoToProjetoMap[c.talhaoId];
         return projetoId != null && idsProjetosAtivos.contains(projetoId);
       }).toList();
    } else {
      cubagensFiltradas = todasAsCubagens.where((c) {
        final projetoId = talhaoToProjetoMap[c.talhaoId];
        return projetoId != null && selectedProjetoIds.contains(projetoId);
      }).toList();
    }

    if (cubagensFiltradas.isEmpty) {
      _desempenhoPorCubagem = [];
      return;
    }

    final grupoPorTalhao = groupBy(cubagensFiltradas, (CubagemArvore c) => "${c.nomeFazenda} / ${c.nomeTalhao}");
    
    _desempenhoPorCubagem = grupoPorTalhao.entries.map((entry) {
      final nome = entry.key;
      final cubagens = entry.value;
      return DesempenhoCubagem(
        nome: nome,
        pendentes: cubagens.where((c) => c.alturaTotal == 0).length,
        concluidas: cubagens.where((c) => c.alturaTotal > 0).length,
        exportadas: cubagens.where((c) => c.exportada).length,
        total: cubagens.length,
      );
    }).toList()..sort((a,b) => a.nome.compareTo(b.nome));
  }

  void _recalcularProgressoPorEquipe() {
    final parcelasConcluidas = _parcelasFiltradas.where((p) => p.status == StatusParcela.concluida).toList();
    if (parcelasConcluidas.isEmpty) {
      _progressoPorEquipe = {};
      return;
    }
    final grupoPorEquipe = groupBy(parcelasConcluidas, (Parcela p) => p.nomeLider?.isNotEmpty == true ? p.nomeLider! : 'Gerente');
    final mapaContagem = grupoPorEquipe.map((nomeEquipe, listaParcelas) => MapEntry(nomeEquipe, listaParcelas.length));
    final sortedEntries = mapaContagem.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    _progressoPorEquipe = Map.fromEntries(sortedEntries);
  }

  void _recalcularColetasPorMes() {
    final parcelas = _parcelasFiltradas.where((p) => p.status == StatusParcela.concluida && p.dataColeta != null).toList();
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

  void _recalcularDesempenhoPorFazenda() {
    if (_parcelasFiltradas.isEmpty) {
      _desempenhoPorFazenda = [];
      return;
    }
    final grupoPorFazenda = groupBy(_parcelasFiltradas, (Parcela p) => p.nomeFazenda ?? 'Fazenda Desconhecida');
    _desempenhoPorFazenda = grupoPorFazenda.entries.map((entry) {
      final nome = entry.key;
      final parcelas = entry.value;
      return DesempenhoFazenda(
        nome: nome,
        pendentes: parcelas.where((p) => p.status == StatusParcela.pendente).length,
        emAndamento: parcelas.where((p) => p.status == StatusParcela.emAndamento).length,
        concluidas: parcelas.where((p) => p.status == StatusParcela.concluida).length,
        exportadas: parcelas.where((p) => p.exportada).length,
        total: parcelas.length,
      );
    }).toList()..sort((a,b) => a.nome.compareTo(b.nome));
  }
}
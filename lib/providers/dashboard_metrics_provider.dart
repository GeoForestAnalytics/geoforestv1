// lib/providers/dashboard_metrics_provider.dart (VERSÃO FINAL E CORRIGIDA)

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geoforestv1/providers/dashboard_filter_provider.dart';
import 'package:intl/intl.dart';

class DesempenhoCubagem {
  final String nome;
  final int pendentes;
  final int concluidas;
  final int exportadas;
  final int total;
  DesempenhoCubagem({ required this.nome, this.pendentes = 0, this.concluidas = 0, this.exportadas = 0, this.total = 0 });
}

// <<< CORREÇÃO 1: Mudar a estrutura do modelo para ter campos separados >>>
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
  List<DesempenhoCubagem> _desempenhoPorCubagem = [];
  Map<String, int> _progressoPorEquipe = {};
  Map<String, int> _coletasPorMes = {};
  List<DesempenhoFazenda> _desempenhoPorFazenda = [];
  
  List<Parcela> get parcelasFiltradas => _parcelasFiltradas;
  List<DesempenhoCubagem> get desempenhoPorCubagem => _desempenhoPorCubagem;
  Map<String, int> get progressoPorEquipe => _progressoPorEquipe;
  Map<String, int> get coletasPorMes => _coletasPorMes;
  List<DesempenhoFazenda> get desempenhoPorFazenda => _desempenhoPorFazenda;

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
    _recalcularProgressoPorEquipe();
    _recalcularColetasPorMes();
    _recalcularDesempenhoPorFazenda();
    
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

    if (filterProvider.selectedFazendaNomes.isNotEmpty) {
      parcelasVisiveis = parcelasVisiveis
          .where((p) => p.nomeFazenda != null && filterProvider.selectedFazendaNomes.contains(p.nomeFazenda!))
          .toList();
    }

    _parcelasFiltradas = parcelasVisiveis;
  }
  
  void _recalcularDesempenhoPorCubagem(
    List<CubagemArvore> todasAsCubagens, 
    Map<int, int> talhaoToProjetoMap, 
    Map<int, int> talhaoToAtividadeMap,
    Map<int, String> atividadeIdToTipoMap,
    List<Projeto> projetosAtivos, 
    DashboardFilterProvider filterProvider) {
    if (todasAsCubagens.isEmpty) {
      _desempenhoPorCubagem = [];
      return;
    }
    
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
        return projetoId != null && filterProvider.selectedProjetoIds.contains(projetoId);
      }).toList();
    }

    if (filterProvider.selectedFazendaNomes.isNotEmpty) {
        cubagensFiltradas = cubagensFiltradas
            .where((c) => filterProvider.selectedFazendaNomes.contains(c.nomeFazenda))
            .toList();
    }

    if (cubagensFiltradas.isEmpty) {
      _desempenhoPorCubagem = [];
      return;
    }

    final grupoPorTalhao = groupBy(cubagensFiltradas, (CubagemArvore c) {
      final atividadeId = talhaoToAtividadeMap[c.talhaoId];
      final tipoAtividade = atividadeId != null ? atividadeIdToTipoMap[atividadeId] : "N/A";
      return "$tipoAtividade - ${c.nomeFazenda} / ${c.nomeTalhao}";
    });
    
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
    
    // <<< CORREÇÃO 2: A chave de agrupamento agora é uma string com um separador único >>>
    final grupoPorFazendaEAtividade = groupBy(
      _parcelasFiltradas, 
      (Parcela p) => "${p.atividadeTipo ?? 'N/A'}:::${p.nomeFazenda ?? 'Fazenda Desconhecida'}"
    );

    // <<< CORREÇÃO 3: Mapear os resultados para a nova estrutura DesempenhoFazenda >>>
    _desempenhoPorFazenda = grupoPorFazendaEAtividade.entries.map((entry) {
      // Separa a chave novamente para obter os valores individuais
      final parts = entry.key.split(':::');
      final nomeAtividade = parts[0];
      final nomeFazenda = parts[1];
      final parcelas = entry.value;

      return DesempenhoFazenda(
        nomeAtividade: nomeAtividade,
        nomeFazenda: nomeFazenda,
        pendentes: parcelas.where((p) => p.status == StatusParcela.pendente).length,
        emAndamento: parcelas.where((p) => p.status == StatusParcela.emAndamento).length,
        concluidas: parcelas.where((p) => p.status == StatusParcela.concluida).length,
        exportadas: parcelas.where((p) => p.exportada).length,
        total: parcelas.length,
      );
    }).toList()..sort((a,b) => '${a.nomeAtividade}-${a.nomeFazenda}'.compareTo('${b.nomeAtividade}-${b.nomeFazenda}'));
  }
}
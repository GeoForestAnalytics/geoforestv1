// lib/providers/gerente_provider.dart (VERSÃO COM MAPEAMENTO DE TALHÕES CORRIGIDO)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart'; // <<< 1. IMPORT NECESSÁRIO
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/services/gerente_service.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

class DesempenhoCubagem {
  final String nome;
  final int pendentes;
  final int concluidas;
  final int exportadas;
  final int total;

  DesempenhoCubagem({
    required this.nome,
    this.pendentes = 0,
    this.concluidas = 0,
    this.exportadas = 0,
    this.total = 0,
  });
}

class DesempenhoFazenda {
  final String nome;
  final int pendentes;
  final int emAndamento;
  final int concluidas;
  final int exportadas;
  final int total;

  DesempenhoFazenda({
    required this.nome,
    this.pendentes = 0,
    this.emAndamento = 0,
    this.concluidas = 0,
    this.exportadas = 0,
    this.total = 0,
  });
}

class GerenteProvider with ChangeNotifier {
  final GerenteService _gerenteService = GerenteService();
  final TalhaoRepository _talhaoRepository = TalhaoRepository(); // <<< 2. INSTÂNCIA DO REPOSITÓRIO

  StreamSubscription? _dadosColetaSubscription;
  StreamSubscription? _dadosCubagemSubscription;
  List<CubagemArvore> _cubagensSincronizadas = [];
  List<Parcela> _parcelasSincronizadas = [];
  List<Projeto> _projetos = [];
  
  // <<< 3. MAPA CONFIÁVEL PARA RELACIONAR TALHÃO E PROJETO >>>
  Map<int, int> _talhaoToProjetoMap = {};

  bool _isLoading = true;
  String? _error;
  Set<int> _selectedProjetoIds = {};

  // GETTERS
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Projeto> get projetosDisponiveis => _projetos.where((p) => p.status == 'ativo').toList();
  Set<int> get selectedProjetoIds => _selectedProjetoIds;

  List<Parcela> get parcelasFiltradas {
    // ... (este getter não precisa de alteração)
    final idsProjetosAtivos = projetosDisponiveis.map((p) => p.id).toSet();

    List<Parcela> parcelasVisiveis;
    if (_selectedProjetoIds.isEmpty) {
      parcelasVisiveis = _parcelasSincronizadas
          .where((p) => idsProjetosAtivos.contains(p.projetoId))
          .toList();
    } else {
      parcelasVisiveis = _parcelasSincronizadas
          .where((p) => _selectedProjetoIds.contains(p.projetoId))
          .toList();
    }
    return parcelasVisiveis;
  }
  
  // ===================================================================
  // <<< 4. GETTER DE CUBAGEM AGORA USA O MAPA CONFIÁVEL >>>
  // ===================================================================
  List<DesempenhoCubagem> get desempenhoPorCubagem {
    if (_cubagensSincronizadas.isEmpty) return [];

    List<CubagemArvore> cubagensFiltradas;
    if (_selectedProjetoIds.isEmpty) {
       final idsProjetosAtivos = projetosDisponiveis.map((p) => p.id).toSet();
       cubagensFiltradas = _cubagensSincronizadas.where((c) {
         final projetoId = _talhaoToProjetoMap[c.talhaoId];
         return projetoId != null && idsProjetosAtivos.contains(projetoId);
       }).toList();
    } else {
      cubagensFiltradas = _cubagensSincronizadas.where((c) {
        final projetoId = _talhaoToProjetoMap[c.talhaoId];
        return projetoId != null && _selectedProjetoIds.contains(projetoId);
      }).toList();
    }

    if (cubagensFiltradas.isEmpty) return [];

    final grupoPorTalhao = groupBy(cubagensFiltradas, (CubagemArvore c) => "${c.nomeFazenda} / ${c.nomeTalhao}");
    
    return grupoPorTalhao.entries.map((entry) {
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
  
  // ... (outros getters e métodos não precisam de alteração)
  Map<String, int> get progressoPorEquipe {
    final parcelasConcluidas = parcelasFiltradas.where((p) => p.status == StatusParcela.concluida).toList();
    if (parcelasConcluidas.isEmpty) return {};

    final grupoPorEquipe = groupBy(parcelasConcluidas, (Parcela p) {
      if (p.nomeLider == null || p.nomeLider!.isEmpty) {
        return 'Gerente';
      }
      return p.nomeLider!;
    });
    
    final mapaContagem = grupoPorEquipe.map((nomeEquipe, listaParcelas) => MapEntry(nomeEquipe, listaParcelas.length));
    final sortedEntries = mapaContagem.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sortedEntries);
  }

  Map<String, int> get coletasPorMes {
    final parcelas = parcelasFiltradas.where((p) => p.status == StatusParcela.concluida && p.dataColeta != null).toList();
    if (parcelas.isEmpty) return {};
    final grupoPorMes = groupBy(parcelas, (Parcela p) => DateFormat('MMM/yy', 'pt_BR').format(p.dataColeta!));
    final mapaContagem = grupoPorMes.map((mes, lista) => MapEntry(mes, lista.length));
    final chavesOrdenadas = mapaContagem.keys.toList()..sort((a, b) {
      try {
        final dataA = DateFormat('MMM/yy', 'pt_BR').parse(a);
        final dataB = DateFormat('MMM/yy', 'pt_BR').parse(b);
        return dataA.compareTo(dataB);
      } catch (e) { return 0; }
    });
    return {for (var key in chavesOrdenadas) key: mapaContagem[key]!};
  }
  
  List<DesempenhoFazenda> get desempenhoPorFazenda {
    if (parcelasFiltradas.isEmpty) return [];

    final grupoPorFazenda = groupBy(parcelasFiltradas, (Parcela p) => p.nomeFazenda ?? 'Fazenda Desconhecida');
    
    return grupoPorFazenda.entries.map((entry) {
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

  GerenteProvider() {
    initializeDateFormatting('pt_BR', null);
  }

  void toggleProjetoSelection(int projetoId) {
    if (_selectedProjetoIds.contains(projetoId)) {
      _selectedProjetoIds.remove(projetoId);
    } else {
      _selectedProjetoIds.add(projetoId);
    }
    notifyListeners();
  }
  
  void clearProjetoSelection() {
    _selectedProjetoIds.clear();
    notifyListeners();
  }

  // ===================================================================
  // <<< 5. MÉTODO DE INICIALIZAÇÃO AGORA CONSTRÓI O MAPA PRIMEIRO >>>
  // ===================================================================
  Future<void> iniciarMonitoramento() async {
    _dadosColetaSubscription?.cancel();
    _dadosCubagemSubscription?.cancel();
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      // Busca os projetos
      _projetos = await _gerenteService.getTodosOsProjetosStream();
      _projetos.sort((a, b) => a.nome.compareTo(b.nome));
      
      // Constrói o mapa de referência ANTES de ouvir os streams
      final todosOsTalhoes = await _talhaoRepository.getTodosOsTalhoes();
      _talhaoToProjetoMap = {
        for (var talhao in todosOsTalhoes)
          if (talhao.id != null && talhao.projetoId != null) talhao.id!: talhao.projetoId!
      };
      
      _dadosColetaSubscription = _gerenteService.getDadosColetaStream().listen(
        (listaDeParcelas) {
          _parcelasSincronizadas = listaDeParcelas;
          if (_isLoading) _isLoading = false;
          _error = null;
          notifyListeners();
        },
        onError: (e) {
          _error = "Erro ao buscar dados de coleta: $e";
          _isLoading = false;
          notifyListeners();
        },
      );

      _dadosCubagemSubscription = _gerenteService.getDadosCubagemStream().listen(
        (listaDeCubagens) {
          _cubagensSincronizadas = listaDeCubagens;
          notifyListeners();
        },
        onError: (e) {
          debugPrint("Erro no stream de cubagens: $e");
        },
      );

    } catch (e) {
      _error = "Erro ao buscar lista de projetos: $e";
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _dadosColetaSubscription?.cancel();
    _dadosCubagemSubscription?.cancel();
    super.dispose();
  }
}
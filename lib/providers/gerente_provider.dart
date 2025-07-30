// lib/providers/gerente_provider.dart (VERSÃO COMPLETA PARA MULTISSELEÇÃO)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/services/gerente_service.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

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
  StreamSubscription? _dadosColetaSubscription;

  bool _isLoading = true;
  String? _error;
  List<Parcela> _parcelasSincronizadas = [];
  List<Projeto> _projetos = [];
  
  // Variável para lidar com múltiplos IDs
  Set<int> _selectedProjetoIds = {};

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Projeto> get projetosDisponiveis => _projetos.where((p) => p.status == 'ativo').toList();
  Set<int> get selectedProjetoIds => _selectedProjetoIds;

  List<Parcela> get parcelasFiltradas {
    final idsProjetosAtivos = projetosDisponiveis.map((p) => p.id).toSet();

    List<Parcela> parcelasVisiveis;
    if (_selectedProjetoIds.isEmpty) {
      // Se NENHUM projeto estiver selecionado, mostra parcelas de TODOS os projetos ATIVOS.
      parcelasVisiveis = _parcelasSincronizadas
          .where((p) => idsProjetosAtivos.contains(p.projetoId))
          .toList();
    } else {
      // Se UM OU MAIS projetos estiverem selecionados, mostra apenas as parcelas daqueles projetos.
      parcelasVisiveis = _parcelasSincronizadas
          .where((p) => _selectedProjetoIds.contains(p.projetoId))
          .toList();
    }
    return parcelasVisiveis;
  }
  
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
    initializeDateFormatting('pt_BR', null).then((_) {
      iniciarMonitoramento();
    });
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

  Future<void> iniciarMonitoramento() async {
    _dadosColetaSubscription?.cancel();
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _projetos = await _gerenteService.getTodosOsProjetosStream();
      _projetos.sort((a, b) => a.nome.compareTo(b.nome));
      notifyListeners();
      _dadosColetaSubscription = _gerenteService.getDadosColetaStream().listen(
        (listaDeParcelas) {
          _parcelasSincronizadas = listaDeParcelas;
          _isLoading = false;
          _error = null;
          notifyListeners();
        },
        onError: (e) {
          _error = "Erro ao buscar dados de coleta: $e";
          _isLoading = false;
          notifyListeners();
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
    super.dispose();
  }
}
// lib/providers/gerente_provider.dart (VERSÃO REATORADA E SIMPLIFICADA)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/services/gerente_service.dart';
import 'package:intl/date_symbol_data_local.dart';

// As classes DesempenhoCubagem e DesempenhoFazenda foram movidas para o DashboardMetricsProvider.

class GerenteProvider with ChangeNotifier {
  // --- SERVIÇOS E REPOSITÓRIOS ---
  final GerenteService _gerenteService = GerenteService();
  final TalhaoRepository _talhaoRepository = TalhaoRepository();

  // --- ESTADO INTERNO (DADOS BRUTOS) ---
  StreamSubscription? _dadosColetaSubscription;
  StreamSubscription? _dadosCubagemSubscription;
  List<CubagemArvore> _cubagensSincronizadas = [];
  List<Parcela> _parcelasSincronizadas = [];
  List<Projeto> _projetos = [];
  
  // Mapas auxiliares para relacionar os dados
  Map<int, int> _talhaoToProjetoMap = {};
  Map<int, String> _talhaoIdToNomeMap = {};
  Map<String, String> _fazendaIdToNomeMap = {};

  bool _isLoading = true;
  String? _error;
  
  // --- GETTERS PÚBLICOS (APENAS PARA OS DADOS BRUTOS) ---
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  // Estes getters agora são a principal forma de outros providers acessarem os dados
  List<Projeto> get projetos => _projetos;
  List<Parcela> get parcelasSincronizadas => _parcelasSincronizadas;
  List<CubagemArvore> get cubagensSincronizadas => _cubagensSincronizadas;
  Map<int, int> get talhaoToProjetoMap => _talhaoToProjetoMap;

  // <<< GETTERS DE MÉTRICAS REMOVIDOS (agora no DashboardMetricsProvider) >>>
  // List<Parcela> get parcelasFiltradas ...
  // List<DesempenhoCubagem> get desempenhoPorCubagem ...
  // Map<String, int> get progressoPorEquipe ...
  // Map<String, int> get coletasPorMes ...
  // List<DesempenhoFazenda> get desempenhoPorFazenda ...

  // <<< MÉTODOS DE FILTRO REMOVIDOS (agora no DashboardFilterProvider) >>>
  // void toggleProjetoSelection(int projetoId) ...
  // void clearProjetoSelection() ...

  GerenteProvider() {
    initializeDateFormatting('pt_BR', null);
  }

  /// Responsabilidade ÚNICA: Iniciar os streams e carregar os dados brutos.
  Future<void> iniciarMonitoramento() async {
    _dadosColetaSubscription?.cancel();
    _dadosCubagemSubscription?.cancel();
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      _projetos = await _gerenteService.getTodosOsProjetosStream();
      _projetos.sort((a, b) => a.nome.compareTo(b.nome));
      
      final todosOsTalhoes = await _talhaoRepository.getTodosOsTalhoes();
      _talhaoToProjetoMap = { for (var talhao in todosOsTalhoes) if (talhao.id != null && talhao.projetoId != null) talhao.id!: talhao.projetoId! };
      _talhaoIdToNomeMap = { for (var talhao in todosOsTalhoes) if (talhao.id != null) talhao.id!: talhao.nome };
      _fazendaIdToNomeMap = { for (var talhao in todosOsTalhoes) if (talhao.fazendaId.isNotEmpty && talhao.fazendaNome != null) talhao.fazendaId: talhao.fazendaNome! };

      _dadosColetaSubscription = _gerenteService.getDadosColetaStream().listen(
        (listaDeParcelas) {
          _parcelasSincronizadas = listaDeParcelas.map((p) {
            final nomeFazenda = _fazendaIdToNomeMap[p.idFazenda] ?? p.nomeFazenda;
            final nomeTalhao = _talhaoIdToNomeMap[p.talhaoId] ?? p.nomeTalhao;
            return p.copyWith(nomeFazenda: nomeFazenda, nomeTalhao: nomeTalhao);
          }).toList();

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
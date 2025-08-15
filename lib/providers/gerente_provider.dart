// lib/providers/gerente_provider.dart (VERSÃO COM CORREÇÃO DA CONDIÇÃO DE CORRIDA)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/services/gerente_service.dart';
import 'package:intl/date_symbol_data_local.dart';

class GerenteProvider with ChangeNotifier {
  final GerenteService _gerenteService = GerenteService();
  final TalhaoRepository _talhaoRepository = TalhaoRepository();

  StreamSubscription? _dadosColetaSubscription;
  StreamSubscription? _dadosCubagemSubscription;
  List<CubagemArvore> _cubagensSincronizadas = [];
  List<Parcela> _parcelasSincronizadas = [];
  List<Projeto> _projetos = [];
  
  Map<int, int> _talhaoToProjetoMap = {};
  Map<int, String> _talhaoIdToNomeMap = {};
  Map<String, String> _fazendaIdToNomeMap = {};

  bool _isLoading = true;
  String? _error;
  
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  List<Projeto> get projetos => _projetos;
  List<Parcela> get parcelasSincronizadas => _parcelasSincronizadas;
  List<CubagemArvore> get cubagensSincronizadas => _cubagensSincronizadas;
  Map<int, int> get talhaoToProjetoMap => _talhaoToProjetoMap;

  GerenteProvider() {
    initializeDateFormatting('pt_BR', null);
  }

  Future<void> _buildAuxiliaryMaps() async {
    final todosOsTalhoes = await _talhaoRepository.getTodosOsTalhoes();
    _talhaoToProjetoMap = { for (var talhao in todosOsTalhoes) if (talhao.id != null && talhao.projetoId != null) talhao.id!: talhao.projetoId! };
    _talhaoIdToNomeMap = { for (var talhao in todosOsTalhoes) if (talhao.id != null) talhao.id!: talhao.nome };
    _fazendaIdToNomeMap = { for (var talhao in todosOsTalhoes) if (talhao.fazendaId.isNotEmpty && talhao.fazendaNome != null) talhao.fazendaId: talhao.fazendaNome! };
  }

  Future<void> iniciarMonitoramento() async {
    _dadosColetaSubscription?.cancel();
    _dadosCubagemSubscription?.cancel();
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      _projetos = await _gerenteService.getTodosOsProjetosStream();
      _projetos.sort((a, b) => a.nome.compareTo(b.nome));
      
      await _buildAuxiliaryMaps();

      _dadosColetaSubscription = _gerenteService.getDadosColetaStream().listen(
        (listaDeParcelas) async {
          debugPrint("GERENTE PROVIDER RECEBEU: ${listaDeParcelas.length} parcelas do stream.");

          await _buildAuxiliaryMaps();

          _parcelasSincronizadas = listaDeParcelas.map((p) {
            final nomeFazenda = _fazendaIdToNomeMap[p.idFazenda] ?? p.nomeFazenda;
            final nomeTalhao = _talhaoIdToNomeMap[p.talhaoId] ?? p.nomeTalhao;
            
            final projetoId = p.projetoId ?? _talhaoToProjetoMap[p.talhaoId];

            return p.copyWith(
              nomeFazenda: nomeFazenda, 
              nomeTalhao: nomeTalhao,
              projetoId: projetoId,
            );
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

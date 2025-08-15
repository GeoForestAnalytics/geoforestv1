// lib/providers/gerente_provider.dart (VERSÃO COM CORREÇÃO FINAL DA CONDIÇÃO DE CORRIDA)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/services/gerente_service.dart';
import 'package:intl/date_symbol_data_local.dart';

class GerenteProvider with ChangeNotifier {
  final GerenteService _gerenteService = GerenteService();
  final TalhaoRepository _talhaoRepository = TalhaoRepository();
  final AtividadeRepository _atividadeRepository = AtividadeRepository();

  StreamSubscription? _dadosColetaSubscription;
  StreamSubscription? _dadosCubagemSubscription;
  List<CubagemArvore> _cubagensSincronizadas = [];
  List<Parcela> _parcelasSincronizadas = [];
  List<Projeto> _projetos = [];
  List<Atividade> _atividades = [];
  
  Map<int, int> _talhaoToProjetoMap = {};
  Map<int, int> _talhaoToAtividadeMap = {};
  Map<int, String> _talhaoIdToNomeMap = {};
  Map<String, String> _fazendaIdToNomeMap = {};

  bool _isLoading = true;
  String? _error;
  
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  List<Projeto> get projetos => _projetos;
  List<Atividade> get atividades => _atividades;
  List<Parcela> get parcelasSincronizadas => _parcelasSincronizadas;
  List<CubagemArvore> get cubagensSincronizadas => _cubagensSincronizadas;
  Map<int, int> get talhaoToProjetoMap => _talhaoToProjetoMap;
  Map<int, int> get talhaoToAtividadeMap => _talhaoToAtividadeMap;

  GerenteProvider() {
    initializeDateFormatting('pt_BR', null);
  }

  Future<void> _buildAuxiliaryMaps() async {
    final todosOsTalhoes = await _talhaoRepository.getTodosOsTalhoes();
    _talhaoToProjetoMap = { for (var talhao in todosOsTalhoes) if (talhao.id != null && talhao.projetoId != null) talhao.id!: talhao.projetoId! };
    _talhaoToAtividadeMap = { for (var talhao in todosOsTalhoes) if (talhao.id != null) talhao.id!: talhao.fazendaAtividadeId };
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
      
      _atividades = await _atividadeRepository.getTodasAsAtividades();
      final Map<int, String> atividadeIdToTipoMap = { for (var a in _atividades) if (a.id != null) a.id!: a.tipo };
      
      // <<< O build inicial dos mapas é feito aqui, como antes >>>
      await _buildAuxiliaryMaps();

      _dadosColetaSubscription = _gerenteService.getDadosColetaStream().listen(
        (listaDeParcelas) async {
          debugPrint("GERENTE PROVIDER RECEBEU: ${listaDeParcelas.length} parcelas do stream.");

          // <<< CORREÇÃO CRÍTICA: Recarrega os mapas de referência A CADA ATUALIZAÇÃO >>>
          // Isso garante que se um novo talhão foi sincronizado, a informação dele
          // estará disponível para a busca a seguir, evitando o "N/A".
          await _buildAuxiliaryMaps();

          _parcelasSincronizadas = listaDeParcelas.map((p) {
            final nomeFazenda = _fazendaIdToNomeMap[p.idFazenda] ?? p.nomeFazenda;
            final nomeTalhao = _talhaoIdToNomeMap[p.talhaoId] ?? p.nomeTalhao;
            
            final projetoId = p.projetoId ?? _talhaoToProjetoMap[p.talhaoId];
            final atividadeId = _talhaoToAtividadeMap[p.talhaoId];
            final tipoAtividade = atividadeId != null ? atividadeIdToTipoMap[atividadeId] : null;

            return p.copyWith(
              nomeFazenda: nomeFazenda, 
              nomeTalhao: nomeTalhao,
              projetoId: projetoId,
              atividadeTipo: tipoAtividade,
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
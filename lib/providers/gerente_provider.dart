// lib/providers/gerente_provider.dart (VERSÃO COM DADOS DO DIÁRIO DE CAMPO)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart'; // <<< NOVO IMPORT
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/services/gerente_service.dart';
import 'package:intl/date_symbol_data_local.dart';

class GerenteProvider with ChangeNotifier {
  final GerenteService _gerenteService = GerenteService();
  final TalhaoRepository _talhaoRepository = TalhaoRepository();
  final AtividadeRepository _atividadeRepository = AtividadeRepository();

  // Stream Subscriptions
  StreamSubscription? _dadosColetaSubscription;
  StreamSubscription? _dadosCubagemSubscription;
  StreamSubscription? _dadosDiarioSubscription; // <<< NOVA SUBSCRIPTION

  // Listas de dados sincronizados
  List<Parcela> _parcelasSincronizadas = [];
  List<CubagemArvore> _cubagensSincronizadas = [];
  List<DiarioDeCampo> _diariosSincronizados = []; // <<< NOVA LISTA DE DADOS
  List<Projeto> _projetos = [];
  List<Atividade> _atividades = [];
  
  // Mapas auxiliares para resolução de dados
  Map<int, int> _talhaoToProjetoMap = {};
  Map<int, int> _talhaoToAtividadeMap = {};
  Map<int, String> _talhaoIdToNomeMap = {};
  Map<String, String> _fazendaIdToNomeMap = {};

  bool _isLoading = true;
  String? _error;
  
  // Getters públicos
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Projeto> get projetos => _projetos;
  List<Atividade> get atividades => _atividades;
  List<Parcela> get parcelasSincronizadas => _parcelasSincronizadas;
  List<CubagemArvore> get cubagensSincronizadas => _cubagensSincronizadas;
  List<DiarioDeCampo> get diariosSincronizados => _diariosSincronizados; // <<< NOVO GETTER
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
    // Cancela subscriptions antigas para evitar múltiplos ouvintes
    _dadosColetaSubscription?.cancel();
    _dadosCubagemSubscription?.cancel();
    _dadosDiarioSubscription?.cancel(); // <<< CANCELA A NOVA SUBSCRIPTION

    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      _projetos = await _gerenteService.getTodosOsProjetosStream();
      _projetos.sort((a, b) => a.nome.compareTo(b.nome));
      
      _atividades = await _atividadeRepository.getTodasAsAtividades();
      final Map<int, String> atividadeIdToTipoMap = { for (var a in _atividades) if (a.id != null) a.id!: a.tipo };
      
      await _buildAuxiliaryMaps();

      // Listener para PARCELAS
      _dadosColetaSubscription = _gerenteService.getDadosColetaStream().listen(
        (listaDeParcelas) async {
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

      // Listener para CUBAGENS
      _dadosCubagemSubscription = _gerenteService.getDadosCubagemStream().listen(
        (listaDeCubagens) async {
          await _buildAuxiliaryMaps();
          _cubagensSincronizadas = listaDeCubagens;
          if (_isLoading) _isLoading = false;
          notifyListeners();
        },
        onError: (e) => debugPrint("Erro no stream de cubagens: $e"),
      );

      // <<< NOVO LISTENER PARA DIÁRIOS DE CAMPO >>>
      _dadosDiarioSubscription = _gerenteService.getDadosDiarioStream().listen(
        (listaDeDiarios) {
          _diariosSincronizados = listaDeDiarios;
          if (_isLoading) _isLoading = false;
          notifyListeners();
        },
        onError: (e) => debugPrint("Erro no stream de diários de campo: $e"),
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
    _dadosDiarioSubscription?.cancel(); // <<< FAZ O DISPOSE DA NOVA SUBSCRIPTION
    super.dispose();
  }
}
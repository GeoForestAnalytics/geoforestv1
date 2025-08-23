// lib/providers/dashboard_filter_provider.dart (VERSÃO CORRIGIDA)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';

enum PeriodoFiltro { todos, hoje, ultimos7Dias, esteMes, mesPassado, personalizado }

class DashboardFilterProvider with ChangeNotifier {
  // --- Filtros ---
  List<Projeto> _projetosDisponiveis = [];
  Set<int> _selectedProjetoIds = {};
  
  // <<< MUDANÇA 1: Armazena a lista completa de atividades disponíveis >>>
  List<Atividade> _atividadesDisponiveis = [];
  // <<< MUDANÇA 2: O filtro agora é baseado no TIPO (String) da atividade >>>
  Set<String> _selectedAtividadeTipos = {};

  List<String> _fazendasDisponiveis = [];
  Set<String> _selectedFazendaNomes = {};
  PeriodoFiltro _periodo = PeriodoFiltro.todos;
  DateTimeRange? _periodoPersonalizado;
  List<String> _lideresDisponiveis = [];
  Set<String> _lideresSelecionados = {};

  // --- Getters ---
  List<Projeto> get projetosDisponiveis => _projetosDisponiveis;
  Set<int> get selectedProjetoIds => _selectedProjetoIds;

  // <<< MUDANÇA 3: Novo getter para os TIPOS únicos de atividade >>>
  List<String> get atividadesTiposDisponiveis => _atividadesDisponiveis.map((a) => a.tipo).toSet().toList()..sort();
  List<Atividade> get atividadesDisponiveis => _atividadesDisponiveis; // Mantém o getter antigo se necessário em outro lugar
  Set<String> get selectedAtividadeTipos => _selectedAtividadeTipos;

  List<String> get fazendasDisponiveis => _fazendasDisponiveis;
  Set<String> get selectedFazendaNomes => _selectedFazendaNomes;
  PeriodoFiltro get periodo => _periodo;
  DateTimeRange? get periodoPersonalizado => _periodoPersonalizado;
  List<String> get lideresDisponiveis => _lideresDisponiveis;
  Set<String> get lideresSelecionados => _lideresSelecionados;
  
  // --- Métodos de atualização chamados pelo ProxyProvider ---
  void updateProjetosDisponiveis(List<Projeto> novosProjetos) {
    _projetosDisponiveis = novosProjetos;
    _selectedProjetoIds.removeWhere((id) => !_projetosDisponiveis.any((p) => p.id == id));
  }

  void updateAtividadesDisponiveis(List<Atividade> atividades) {
    _atividadesDisponiveis = atividades;
    _selectedAtividadeTipos.removeWhere((tipo) => !_atividadesDisponiveis.any((a) => a.tipo == tipo));
  }

  void updateFazendasDisponiveis(List<Parcela> parcelas) {
      final nomesFazendas = parcelas
          .where((p) => p.nomeFazenda != null && p.nomeFazenda!.isNotEmpty)
          .map((p) => p.nomeFazenda!)
          .toSet()
          .toList();
      nomesFazendas.sort();
      _fazendasDisponiveis = nomesFazendas;
      _selectedFazendaNomes.removeWhere((nome) => !_fazendasDisponiveis.contains(nome));
  }
  
  void updateLideresDisponiveis(List<String> lideres) {
    _lideresDisponiveis = lideres..sort();
    _lideresSelecionados.removeWhere((l) => !_lideresDisponiveis.contains(l));
  }

  // --- Métodos de manipulação dos filtros (chamados pela UI) ---
  void setSelectedProjetos(Set<int> newSelection) {
    _selectedProjetoIds = newSelection;
    _selectedAtividadeTipos.clear();
    _selectedFazendaNomes.clear();
    _lideresSelecionados.clear();
    notifyListeners();
  }

  // <<< MUDANÇA 4: Métodos de filtro de atividade atualizados >>>
  void setSelectedAtividadeTipos(Set<String> newSelection) {
    _selectedAtividadeTipos = newSelection;
    notifyListeners();
  }

  void clearAtividadeTipoSelection() {
    _selectedAtividadeTipos.clear();
    notifyListeners();
  }

  void setSelectedFazendas(Set<String> newSelection) {
    _selectedFazendaNomes = newSelection;
    notifyListeners();
  }

  void clearProjetoSelection() {
    _selectedProjetoIds.clear();
    _selectedAtividadeTipos.clear();
    _selectedFazendaNomes.clear();
    _lideresSelecionados.clear();
    notifyListeners();
  }
  
  void clearFazendaSelection() {
    _selectedFazendaNomes.clear();
    notifyListeners();
  }

  void setPeriodo(PeriodoFiltro novoPeriodo, {DateTimeRange? personalizado}) {
    _periodo = novoPeriodo;
    _periodoPersonalizado = (_periodo == PeriodoFiltro.personalizado) ? personalizado : null;
    notifyListeners();
  }

  void setSingleLider(String? lider) {
    _lideresSelecionados.clear();
    if (lider != null) {
      _lideresSelecionados.add(lider);
    }
    notifyListeners();
  }
}

extension PeriodoFiltroExtension on PeriodoFiltro {
  String get displayName {
    switch (this) {
      case PeriodoFiltro.todos: return 'Todos';
      case PeriodoFiltro.hoje: return 'Hoje';
      case PeriodoFiltro.ultimos7Dias: return 'Últimos 7 dias';
      case PeriodoFiltro.esteMes: return 'Este mês';
      case PeriodoFiltro.mesPassado: return 'Mês passado';
      case PeriodoFiltro.personalizado: return 'Personalizado';
    }
  }
}
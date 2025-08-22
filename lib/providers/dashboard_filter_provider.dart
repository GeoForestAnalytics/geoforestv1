// lib/providers/dashboard_filter_provider.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/models/atividade_model.dart'; // <<< ADICIONE ESTE IMPORT
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';

// Enum copiado do filtro de operações para manter a consistência
enum PeriodoFiltro { todos, hoje, ultimos7Dias, esteMes, mesPassado, personalizado }

class DashboardFilterProvider with ChangeNotifier {
  // --- Filtros ---
  List<Projeto> _projetosDisponiveis = [];
  Set<int> _selectedProjetoIds = {};
  List<String> _fazendasDisponiveis = [];
  Set<String> _selectedFazendaNomes = {};
  PeriodoFiltro _periodo = PeriodoFiltro.todos;
  DateTimeRange? _periodoPersonalizado;
  List<String> _lideresDisponiveis = [];
  Set<String> _lideresSelecionados = {};

  // <<< ADICIONE ESTAS DUAS LINHAS PARA O FILTRO DE ATIVIDADE >>>
  List<Atividade> _atividadesDisponiveis = [];
  Set<int> _selectedAtividadeIds = {};


  // --- Getters ---
  List<Projeto> get projetosDisponiveis => _projetosDisponiveis;
  Set<int> get selectedProjetoIds => _selectedProjetoIds;
  List<String> get fazendasDisponiveis => _fazendasDisponiveis;
  Set<String> get selectedFazendaNomes => _selectedFazendaNomes;
  PeriodoFiltro get periodo => _periodo;
  DateTimeRange? get periodoPersonalizado => _periodoPersonalizado;
  List<String> get lideresDisponiveis => _lideresDisponiveis;
  Set<String> get lideresSelecionados => _lideresSelecionados;
  
  // <<< ADICIONE ESTES DOIS GETTERS PARA O FILTRO DE ATIVIDADE >>>
  List<Atividade> get atividadesDisponiveis => _atividadesDisponiveis;
  Set<int> get selectedAtividadeIds => _selectedAtividadeIds;


  // --- Métodos de atualização chamados pelo ProxyProvider ---
  void updateProjetosDisponiveis(List<Projeto> novosProjetos) {
    _projetosDisponiveis = novosProjetos;
    _selectedProjetoIds.removeWhere((id) => !_projetosDisponiveis.any((p) => p.id == id));
  }

  // <<< ADICIONE ESTE NOVO MÉTODO >>>
  void updateAtividadesDisponiveis(List<Atividade> atividades) {
    _atividadesDisponiveis = atividades;
    _selectedAtividadeIds.removeWhere((id) => !_atividadesDisponiveis.any((a) => a.id == id));
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
    _selectedAtividadeIds.clear(); // <<< ADICIONE (Limpa o filtro de atividade)
    _selectedFazendaNomes.clear();
    _lideresSelecionados.clear();
    notifyListeners();
  }

  // <<< ADICIONE ESTES DOIS NOVOS MÉTODOS >>>
  void setSelectedAtividades(Set<int> newSelection) {
    _selectedAtividadeIds = newSelection;
    notifyListeners();
  }

  void clearAtividadeSelection() {
    _selectedAtividadeIds.clear();
    notifyListeners();
  }

  void setSelectedFazendas(Set<String> newSelection) {
    _selectedFazendaNomes = newSelection;
    notifyListeners();
  }

  void clearProjetoSelection() {
    _selectedProjetoIds.clear();
    _selectedAtividadeIds.clear(); // <<< ADICIONE (Limpa o filtro de atividade)
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
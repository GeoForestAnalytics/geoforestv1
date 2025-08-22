// lib/providers/operacoes_filter_provider.dart (VERSÃO FINAL COM OPÇÃO "TODOS")

import 'package:flutter/material.dart';

/// Enum para definir os períodos de filtro pré-configurados.
// <<< ALTERAÇÃO 1: Adicionando a nova opção 'todos' >>>
enum PeriodoFiltro { todos, hoje, ultimos7Dias, esteMes, mesPassado, personalizado }

/// Provider responsável por gerenciar o estado dos filtros do Dashboard de Operações.
class OperacoesFilterProvider with ChangeNotifier {
  // --- ESTADO DOS FILTROS ---

  // Filtro de Período
  // <<< ALTERAÇÃO 2: O valor inicial padrão agora é 'todos' >>>
  PeriodoFiltro _periodo = PeriodoFiltro.todos;
  DateTimeRange? _periodoPersonalizado;

  // Filtro de Equipe
  Set<String> _lideresSelecionados = {};
  List<String> _lideresDisponiveis = [];

  // --- GETTERS PÚBLICOS ---
  PeriodoFiltro get periodo => _periodo;
  DateTimeRange? get periodoPersonalizado => _periodoPersonalizado;
  Set<String> get lideresSelecionados => _lideresSelecionados;
  List<String> get lideresDisponiveis => _lideresDisponiveis;

  // --- MÉTODOS PARA ATUALIZAR O ESTADO ---

  void setLideresDisponiveis(List<String> lideres) {
    _lideresDisponiveis = lideres..sort();
    _lideresSelecionados.removeWhere((l) => !_lideresDisponiveis.contains(l));
  }

  void setPeriodo(PeriodoFiltro novoPeriodo, {DateTimeRange? personalizado}) {
    _periodo = novoPeriodo;
    if (_periodo == PeriodoFiltro.personalizado) {
      _periodoPersonalizado = personalizado;
    } else {
      // Limpa o período personalizado se outra opção for selecionada
      _periodoPersonalizado = null;
    }
    notifyListeners();
  }

  void toggleLider(String lider) {
    if (_lideresSelecionados.contains(lider)) {
      _lideresSelecionados.remove(lider);
    } else {
      _lideresSelecionados.add(lider);
    }
    notifyListeners();
  }
  
  void setSingleLider(String? lider) {
      _lideresSelecionados.clear();
      if (lider != null) {
          _lideresSelecionados.add(lider);
      }
      notifyListeners();
  }

  void clearLideres() {
    _lideresSelecionados.clear();
    notifyListeners();
  }
}

extension PeriodoFiltroExtension on PeriodoFiltro {
  String get displayName {
    switch (this) {
      // <<< ALTERAÇÃO 3: Adicionando o nome de exibição para a nova opção >>>
      case PeriodoFiltro.todos:
        return 'Todos os Períodos';
      case PeriodoFiltro.hoje:
        return 'Hoje';
      case PeriodoFiltro.ultimos7Dias:
        return 'Últimos 7 dias';
      case PeriodoFiltro.esteMes:
        return 'Este mês';
      case PeriodoFiltro.mesPassado:
        return 'Mês passado';
      case PeriodoFiltro.personalizado:
        return 'Personalizado';
    }
  }
}
// lib/providers/dashboard_filter_provider.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';

enum PeriodoFiltro { todos, hoje, ultimos7Dias, esteMes, mesPassado, personalizado }

class DashboardFilterProvider with ChangeNotifier {
  // --- Filtros ---
  List<Projeto> _projetosDisponiveis = [];
  Set<int> _selectedProjetoIds = {};

  List<Atividade> _atividadesDisponiveis = [];
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

  List<String> get atividadesTiposDisponiveis => _atividadesDisponiveis.map((a) => a.tipo).toSet().toList()..sort();
  Set<String> get selectedAtividadeTipos => _selectedAtividadeTipos;
  
  List<Atividade> get atividadesDisponiveis => _atividadesDisponiveis;

  List<String> get fazendasDisponiveis => _fazendasDisponiveis;
  Set<String> get selectedFazendaNomes => _selectedFazendaNomes;

  PeriodoFiltro get periodo => _periodo;
  DateTimeRange? get periodoPersonalizado => _periodoPersonalizado;
  
  List<String> get lideresDisponiveis => _lideresDisponiveis;
  Set<String> get lideresSelecionados => _lideresSelecionados;
  
  // --- MÉTODOS DE AÇÃO (CORREÇÃO APLICADA AQUI) ---

  /// Alterna a seleção de um projeto individualmente
  void toggleProjetoSelection(int projetoId) {
    if (_selectedProjetoIds.contains(projetoId)) {
      _selectedProjetoIds.remove(projetoId);
    } else {
      _selectedProjetoIds.add(projetoId);
    }
    // Ao mudar o projeto, limpa filtros dependentes para evitar inconsistências
    _selectedAtividadeTipos.clear();
    _selectedFazendaNomes.clear();
    _lideresSelecionados.clear();
    notifyListeners();
  }

  /// Alterna a seleção de uma fazenda individualmente
  void toggleFazendaSelection(String nomeFazenda) {
    if (_selectedFazendaNomes.contains(nomeFazenda)) {
      _selectedFazendaNomes.remove(nomeFazenda);
    } else {
      _selectedFazendaNomes.add(nomeFazenda);
    }
    notifyListeners();
  }

  void clearAllFilters() {
    _selectedProjetoIds.clear();
    _selectedAtividadeTipos.clear();
    _selectedFazendaNomes.clear();
    _lideresSelecionados.clear();
    _periodo = PeriodoFiltro.todos;
    _periodoPersonalizado = null;
    notifyListeners();
  }

  // --- MÉTODOS DE ATUALIZAÇÃO DE DADOS ---

  void updateFiltersFrom(GerenteProvider gerenteProvider) {
    _updateProjetosDisponiveis(gerenteProvider.projetos);

    List<Atividade> atividadesParaFiltro = _selectedProjetoIds.isEmpty
        ? gerenteProvider.atividades
        : gerenteProvider.atividades.where((a) => _selectedProjetoIds.contains(a.projetoId)).toList();
    _updateAtividadesDisponiveis(atividadesParaFiltro);

    List<Parcela> parcelasParaFiltroDeFazenda = gerenteProvider.parcelasSincronizadas;
    
    if (_selectedProjetoIds.isNotEmpty) {
      parcelasParaFiltroDeFazenda = parcelasParaFiltroDeFazenda
          .where((p) => _selectedProjetoIds.contains(p.projetoId)).toList();
    }
    
    if (_selectedAtividadeTipos.isNotEmpty) {
      final idsDeAtividadesFiltradas = gerenteProvider.atividades
          .where((a) => _selectedAtividadeTipos.contains(a.tipo))
          .map((a) => a.id)
          .toSet();
          
      parcelasParaFiltroDeFazenda = parcelasParaFiltroDeFazenda.where((p) {
        final atividadeId = gerenteProvider.talhaoToAtividadeMap[p.talhaoId];
        return atividadeId != null && idsDeAtividadesFiltradas.contains(atividadeId);
      }).toList();
    }
    
    _updateFazendasDisponiveis(parcelasParaFiltroDeFazenda);
  }
  
  void _updateProjetosDisponiveis(List<Projeto> novosProjetos) {
    _projetosDisponiveis = novosProjetos;
    _selectedProjetoIds.removeWhere((id) => !_projetosDisponiveis.any((p) => p.id == id));
  }

  void _updateAtividadesDisponiveis(List<Atividade> atividades) {
    _atividadesDisponiveis = atividades;
    _selectedAtividadeTipos.removeWhere((tipo) => !_atividadesDisponiveis.any((a) => a.tipo == tipo));
  }

  void _updateFazendasDisponiveis(List<Parcela> parcelas) {
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

  void setSelectedProjetos(Set<int> newSelection) {
    _selectedProjetoIds = newSelection;
    _selectedAtividadeTipos.clear();
    _selectedFazendaNomes.clear();
    _lideresSelecionados.clear();
    notifyListeners();
  }
  
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

extension DashboardFilterProviderClone on DashboardFilterProvider {
  DashboardFilterProvider clone() {
    final newInstance = DashboardFilterProvider();
    newInstance._projetosDisponiveis = List.from(this._projetosDisponiveis);
    newInstance._selectedProjetoIds = Set.from(this._selectedProjetoIds);
    newInstance._atividadesDisponiveis = List.from(this._atividadesDisponiveis);
    newInstance._selectedAtividadeTipos = Set.from(this._selectedAtividadeTipos);
    newInstance._fazendasDisponiveis = List.from(this._fazendasDisponiveis);
    newInstance._selectedFazendaNomes = Set.from(this._selectedFazendaNomes);
    newInstance._periodo = this._periodo;
    newInstance._periodoPersonalizado = this._periodoPersonalizado;
    newInstance._lideresDisponiveis = List.from(this._lideresDisponiveis);
    newInstance._lideresSelecionados = Set.from(this._lideresSelecionados);
    return newInstance;
  }
}
// lib/providers/dashboard_filter_provider.dart (VERSÃO COM FILTRO DE FAZENDA)

import 'package:flutter/foundation.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';

class DashboardFilterProvider with ChangeNotifier {
  // --- Filtro de Projeto (Existente) ---
  List<Projeto> _projetosDisponiveis = [];
  Set<int> _selectedProjetoIds = {};

  List<Projeto> get projetosDisponiveis => _projetosDisponiveis;
  Set<int> get selectedProjetoIds => _selectedProjetoIds;

  // --- Filtro de Fazenda (Novo) ---
  List<String> _fazendasDisponiveis = [];
  Set<String> _selectedFazendaNomes = {};

  List<String> get fazendasDisponiveis => _fazendasDisponiveis;
  Set<String> get selectedFazendaNomes => _selectedFazendaNomes;
  
  /// Chamado pelo ProxyProvider para atualizar a lista de projetos.
  void updateProjetosDisponiveis(List<Projeto> novosProjetos) {
    _projetosDisponiveis = novosProjetos;
    // Garante que não fiquem IDs de projetos que não existem mais
    _selectedProjetoIds.removeWhere((id) => !_projetosDisponiveis.any((p) => p.id == id));
  }

  /// <<< NOVO MÉTODO >>>
  /// Chamado pelo ProxyProvider para atualizar a lista de fazendas.
  void updateFazendasDisponiveis(List<Parcela> parcelas) {
      // Extrai os nomes únicos de fazendas das parcelas filtradas por projeto
      final nomesFazendas = parcelas
          .where((p) => p.nomeFazenda != null && p.nomeFazenda!.isNotEmpty)
          .map((p) => p.nomeFazenda!)
          .toSet()
          .toList();
      nomesFazendas.sort(); // Ordena alfabeticamente
      _fazendasDisponiveis = nomesFazendas;
      // Garante que não fiquem nomes de fazendas que não existem mais no filtro atual
      _selectedFazendaNomes.removeWhere((nome) => !_fazendasDisponiveis.contains(nome));
  }

  void toggleProjetoSelection(int projetoId) {
    if (_selectedProjetoIds.contains(projetoId)) {
      _selectedProjetoIds.remove(projetoId);
    } else {
      _selectedProjetoIds.add(projetoId);
    }
    // Ao mudar o projeto, limpamos o filtro de fazenda para evitar inconsistências
    _selectedFazendaNomes.clear();
    notifyListeners();
  }
  
  void clearProjetoSelection() {
    _selectedProjetoIds.clear();
    _selectedFazendaNomes.clear(); // Limpa também o filtro de fazenda
    notifyListeners();
  }

  /// <<< NOVO MÉTODO >>>
  void toggleFazendaSelection(String fazendaNome) {
    if (_selectedFazendaNomes.contains(fazendaNome)) {
      _selectedFazendaNomes.remove(fazendaNome);
    } else {
      _selectedFazendaNomes.add(fazendaNome);
    }
    notifyListeners();
  }
  
  /// <<< NOVO MÉTODO >>>
  void clearFazendaSelection() {
    _selectedFazendaNomes.clear();
    notifyListeners();
  }
}
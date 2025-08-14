// lib/providers/dashboard_filter_provider.dart (NOVO ARQUIVO)

import 'package:flutter/foundation.dart';
import 'package:geoforestv1/models/projeto_model.dart';

class DashboardFilterProvider with ChangeNotifier {
  // --- ESTADO INTERNO ---
  // Lista de todos os projetos que podem ser filtrados
  List<Projeto> _projetosDisponiveis = [];
  // Conjunto de IDs dos projetos que estão atualmente selecionados
  Set<int> _selectedProjetoIds = {};

  // --- GETTERS PÚBLICOS ---
  // Permite que a UI leia a lista de projetos disponíveis
  List<Projeto> get projetosDisponiveis => _projetosDisponiveis;
  // Permite que a UI e outros providers saibam quais projetos estão selecionados
  Set<int> get selectedProjetoIds => _selectedProjetoIds;

  /// Método para que o GerenteProvider possa "alimentar" este provider
  /// com a lista de projetos carregada.
  void updateProjetosDisponiveis(List<Projeto> novosProjetos) {
    _projetosDisponiveis = novosProjetos;
    // Garante que não haja IDs selecionados que não existem mais
    _selectedProjetoIds.removeWhere((id) => !_projetosDisponiveis.any((p) => p.id == id));
    notifyListeners();
  }

  /// Adiciona ou remove um ID de projeto do conjunto de seleção.
  void toggleProjetoSelection(int projetoId) {
    if (_selectedProjetoIds.contains(projetoId)) {
      _selectedProjetoIds.remove(projetoId);
    } else {
      _selectedProjetoIds.add(projetoId);
    }
    notifyListeners(); // Notifica a UI para reconstruir
  }
  
  /// Limpa todos os filtros selecionados.
  void clearProjetoSelection() {
    _selectedProjetoIds.clear();
    notifyListeners(); // Notifica a UI para reconstruir
  }
}
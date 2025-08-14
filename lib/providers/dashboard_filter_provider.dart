// lib/providers/dashboard_filter_provider.dart (VERSÃO CORRETA E COMPLETA)

import 'package:flutter/foundation.dart';
import 'package:geoforestv1/models/projeto_model.dart';

class DashboardFilterProvider with ChangeNotifier {
  List<Projeto> _projetosDisponiveis = [];
  Set<int> _selectedProjetoIds = {};

  List<Projeto> get projetosDisponiveis => _projetosDisponiveis;
  Set<int> get selectedProjetoIds => _selectedProjetoIds;

  /// Este método é chamado de forma segura pelo ProxyProvider.
  void updateProjetosDisponiveis(List<Projeto> novosProjetos) {
    _projetosDisponiveis = novosProjetos;
    _selectedProjetoIds.removeWhere((id) => !_projetosDisponiveis.any((p) => p.id == id));
    // Não chamamos notifyListeners() aqui, pois isso é gerenciado pelo ProxyProvider.
  }

  void toggleProjetoSelection(int projetoId) {
    if (_selectedProjetoIds.contains(projetoId)) {
      _selectedProjetoIds.remove(projetoId);
    } else {
      _selectedProjetoIds.add(projetoId);
    }
    notifyListeners();
  }
  
  void clearProjetoSelection() {
    _selectedProjetoIds.clear();
    notifyListeners();
  }
}
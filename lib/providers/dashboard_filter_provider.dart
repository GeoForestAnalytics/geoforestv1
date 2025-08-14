// lib/providers/dashboard_filter_provider.dart (VERSÃO SIMPLIFICADA E CORRIGIDA)

import 'package:flutter/foundation.dart';

class DashboardFilterProvider with ChangeNotifier {
  Set<int> _selectedProjetoIds = {};

  Set<int> get selectedProjetoIds => _selectedProjetoIds;

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
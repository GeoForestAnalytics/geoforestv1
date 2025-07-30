// lib/providers/license_provider.dart (VERSÃO ATUALIZADA PARA O NOVO MODELO)

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// <<< 1. IMPORTAR O NOSSO NOVO SERVIÇO >>>
import 'package:geoforestv1/services/licensing_service.dart';

// Modelo para guardar os dados da licença
class LicenseData {
  final String id;
  final String status;
  final DateTime? trialEndDate;
  final Map<String, dynamic> features;
  final Map<String, dynamic> limites;
  // <<< 2. ADICIONAR O CAMPO 'CARGO' >>>
  final String cargo;

  LicenseData({
    required this.id,
    required this.status,
    this.trialEndDate,
    required this.features,
    required this.limites,
    required this.cargo, // Adicionado ao construtor
  });

  // A lógica de 'isTrialExpiringSoon' não precisa de alterações.
  bool get isTrialExpiringSoon {
    if (status != 'trial' || trialEndDate == null) {
      return false;
    }
    final difference = trialEndDate!.difference(DateTime.now()).inDays;
    return difference >= 0 && difference <= 3;
  }
}

class LicenseProvider with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // <<< 1. INSTANCIAR O NOSSO SERVIÇO >>>
  final LicensingService _licensingService = LicensingService();

  LicenseData? _licenseData;
  bool _isLoading = true;
  String? _error;

  LicenseData? get licenseData => _licenseData;
  bool get isLoading => _isLoading;
  String? get error => _error;

  LicenseProvider() {
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        // A chamada agora não precisa passar o UID, a função cuidará disso.
        fetchLicenseData();
      } else {
        clearLicenseData();
      }
    });
    // Dispara a primeira verificação caso já haja um usuário logado
    if (_auth.currentUser != null) {
      fetchLicenseData();
    }
  }

  // =======================================================================
  // <<< 3. FUNÇÃO DE BUSCA DE DADOS COMPLETAMENTE REESCRITA >>>
  // =======================================================================
  Future<void> fetchLicenseData() async {
    final user = _auth.currentUser;
    if (user == null) {
      clearLicenseData();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Usa o serviço para encontrar o documento da licença da empresa
      final doc = await _licensingService.findLicenseDocumentForUser(user);

      if (doc != null && doc.exists) {
        final data = doc.data()!;
        final trialData = data['trial'] as Map<String, dynamic>?;
        
        // Extrai o mapa de usuários permitidos
        final usuariosPermitidos = data['usuariosPermitidos'] as Map<String, dynamic>? ?? {};
        
        // Extrai o cargo específico do usuário logado a partir do seu UID
        final cargoDoUsuario = usuariosPermitidos[user.uid] as String? ?? 'equipe'; // Padrão 'equipe' por segurança

        _licenseData = LicenseData(
          id: doc.id,
          status: data['statusAssinatura'] ?? 'inativa',
          trialEndDate: (trialData?['dataFim'] as Timestamp?)?.toDate(),
          features: data['features'] ?? {},
          limites: data['limites'] ?? {},
          cargo: cargoDoUsuario, // Salva o cargo no nosso modelo
        );
      } else {
        _error = "Sua conta não foi encontrada em nenhuma licença ativa.";
        _licenseData = null; // Garante que a licença antiga seja limpa
      }
    } catch (e) {
      _error = "Erro ao buscar dados da licença: $e";
       _licenseData = null;
    }

    _isLoading = false;
    notifyListeners();
  }

  void clearLicenseData() {
    _licenseData = null;
    _isLoading = false; // Garante que o estado de loading seja resetado
    _error = null;
    notifyListeners();
  }
}
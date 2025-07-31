// lib/utils/navigation_helper.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geoforestv1/providers/license_provider.dart';

class NavigationHelper {
  /// Navega de volta para a tela principal correta (gerente ou equipe),
  /// limpando a pilha de navegação e garantindo um estado limpo.
  static void goBackToHome(BuildContext context) {
    final cargo = context.read<LicenseProvider>().licenseData?.cargo;

    String homeRoute;

    if (cargo == 'gerente') {
      // A rota "home" do gerente é /gerente_home
      homeRoute = '/gerente_home';
    } else {
      // A rota "home" da equipe é /equipe
      homeRoute = '/home';
    }

    // Este comando é a chave da solução:
    // Ele vai para a rota 'homeRoute' e remove TODAS as outras
    // telas que estavam na pilha antes.
    Navigator.of(context).pushNamedAndRemoveUntil(homeRoute, (Route<dynamic> route) => false);
  }
}
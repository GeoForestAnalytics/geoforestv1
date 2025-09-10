// lib/utils/navigation_helper.dart (VERSÃO ATUALIZADA PARA GO_ROUTER)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart'; // ✅ 1. IMPORTAR O GO_ROUTER
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
      // A rota da equipe agora é a de identificação da equipe,
      // e a tela principal de coleta é a /home.
      // Vamos assumir que, ao clicar em "home", o usuário quer ir para a tela de menu de coleta.
      homeRoute = '/home';
    }

    // ✅ 2. SUBSTITUIR O COMANDO DE NAVEGAÇÃO
    // O método `context.go(path)` do go_router já substitui a pilha de navegação,
    // fazendo exatamente o que `pushNamedAndRemoveUntil` fazia, mas de forma
    // mais limpa e integrada ao novo sistema de roteamento.
    context.go(homeRoute);
  }
}
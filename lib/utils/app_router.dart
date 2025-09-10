// lib/utils/app_router.dart (VERSÃO COM ROTA DE DETALHES DA ATIVIDADE)

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';


// Imports dos Providers
import 'package:geoforestv1/controller/login_controller.dart';
import 'package:geoforestv1/providers/license_provider.dart';

// Imports das Páginas
import 'package:geoforestv1/pages/menu/splash_page.dart';
import 'package:geoforestv1/pages/menu/login_page.dart';
import 'package:geoforestv1/pages/menu/equipe_page.dart';
import 'package:geoforestv1/pages/menu/home_page.dart';
import 'package:geoforestv1/pages/projetos/lista_projetos_page.dart';
import 'package:geoforestv1/pages/menu/paywall_page.dart';
import 'package:geoforestv1/pages/gerente/gerente_main_page.dart';
import 'package:geoforestv1/pages/gerente/gerente_map_page.dart';
import 'package:geoforestv1/pages/projetos/detalhes_projeto_page.dart';
import 'package:geoforestv1/pages/atividades/atividades_page.dart';
import 'package:geoforestv1/pages/atividades/detalhes_atividade_page.dart'; // ✅ IMPORT ADICIONADO


class AppRouter {
  final LoginController loginController;
  final LicenseProvider licenseProvider;

  AppRouter({
    required this.loginController,
    required this.licenseProvider,
  });

  late final GoRouter router = GoRouter(
    refreshListenable: Listenable.merge([loginController, licenseProvider]),
    initialLocation: '/splash',
    
    routes: [
      // ... (outras rotas permanecem iguais)
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/equipe',
        builder: (context, state) => const EquipePage(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomePage(title: 'Geo Forest Analytics'),
      ),
      GoRoute(
        path: '/paywall',
        builder: (context, state) => const PaywallPage(),
      ),
      GoRoute(
        path: '/gerente_home',
        builder: (context, state) => const GerenteMainPage(),
      ),
      GoRoute(
        path: '/gerente_map',
        builder: (context, state) => const GerenteMapPage(),
      ),

      GoRoute(
        path: '/projetos',
        builder: (context, state) => const ListaProjetosPage(title: 'Meus Projetos'),
        routes: [
          GoRoute(
            path: ':projetoId',
            builder: (context, state) {
              final projetoId = int.tryParse(state.pathParameters['projetoId'] ?? '') ?? 0;
              return DetalhesProjetoPage(projetoId: projetoId);
            },
            routes: [
              GoRoute(
                path: 'atividades',
                builder: (context, state) {
                   final projetoId = int.tryParse(state.pathParameters['projetoId'] ?? '') ?? 0;
                   return AtividadesPage(projetoId: projetoId);
                },
                // ✅ NOVA SUB-ROTA ANINHADA PARA OS DETALHES DA ATIVIDADE
                routes: [
                  // Ex: /projetos/123/atividades/456
                  GoRoute(
                    path: ':atividadeId',
                    builder: (context, state) {
                      final atividadeId = int.tryParse(state.pathParameters['atividadeId'] ?? '') ?? 0;
                      // Passa o ID para a página de detalhes da atividade
                      return DetalhesAtividadePage(atividadeId: atividadeId);
                    },
                  ),
                ]
              ),
            ]
          ),
        ],
      ),
    ],

    redirect: (BuildContext context, GoRouterState state) {
      if (!loginController.isInitialized) {
        return '/splash';
      }
      
      final bool isLoggedIn = loginController.isLoggedIn;
      final String currentRoute = state.matchedLocation;

      if (!isLoggedIn) {
        return currentRoute == '/login' ? null : '/login';
      }

      if (licenseProvider.isLoading) {
        return '/splash';
      }
      
      final license = licenseProvider.licenseData;
      if (license == null) {
        return '/login';
      }
      
      final bool isLicenseOk = (license.status == 'ativa' || license.status == 'trial');

      if (!isLicenseOk) {
        return currentRoute == '/paywall' ? null : '/paywall';
      }
      
      if (currentRoute == '/login' || currentRoute == '/splash') {
        if (license.cargo == 'gerente') {
          return '/gerente_home';
        } else {
          return '/equipe';
        }
      }
      
      return null;
    },
    
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Página não encontrada')),
      body: Center(
        child: Text('A rota "${state.uri}" não existe.'),
      ),
    ),
  );
}
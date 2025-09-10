// lib/utils/app_router.dart (VERSÃO FINAL COM HIERARQUIA COMPLETA E CORRETA)

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
import 'package:geoforestv1/pages/atividades/detalhes_atividade_page.dart';
import 'package:geoforestv1/pages/fazenda/detalhes_fazenda_page.dart';
import 'package:geoforestv1/pages/talhoes/detalhes_talhao_page.dart';


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

      // ROTA PRINCIPAL DE PROJETOS E SUA HIERARQUIA ANINHADA
      GoRoute(
        path: '/projetos',
        builder: (context, state) => const ListaProjetosPage(title: 'Meus Projetos'),
        routes: [
          GoRoute(
            path: ':projetoId', // Ex: /projetos/123
            builder: (context, state) {
              final projetoId = int.tryParse(state.pathParameters['projetoId'] ?? '') ?? 0;
              return DetalhesProjetoPage(projetoId: projetoId);
            },
            routes: [
              GoRoute(
                path: 'atividades', // Ex: /projetos/123/atividades  <- ROTA CORRIGIDA (LISTA)
                builder: (context, state) {
                   final projetoId = int.tryParse(state.pathParameters['projetoId'] ?? '') ?? 0;
                   return AtividadesPage(projetoId: projetoId);
                },
                routes: [
                  GoRoute(
                    path: ':atividadeId', // Ex: /projetos/123/atividades/456 <- ROTA DE DETALHES
                    builder: (context, state) {
                      final atividadeId = int.tryParse(state.pathParameters['atividadeId'] ?? '') ?? 0;
                      return DetalhesAtividadePage(atividadeId: atividadeId);
                    },
                    routes: [
                        GoRoute(
                            path: 'fazendas/:fazendaId', // Ex: /projetos/123/atividades/456/fazendas/FAZ01
                            builder: (context, state) {
                                // GoRouter passa todos os parâmetros do path, então não precisamos do projetoId aqui.
                                final atividadeId = int.tryParse(state.pathParameters['atividadeId'] ?? '') ?? 0;
                                final fazendaId = state.pathParameters['fazendaId'] ?? '';
                                return DetalhesFazendaPage(atividadeId: atividadeId, fazendaId: fazendaId);
                            },
                            routes: [
                                GoRoute(
                                    path: 'talhoes/:talhaoId', // Ex: /projetos/123/atividades/456/fazendas/FAZ01/talhoes/789
                                    builder: (context, state) {
                                        final atividadeId = int.tryParse(state.pathParameters['atividadeId'] ?? '') ?? 0;
                                        final talhaoId = int.tryParse(state.pathParameters['talhaoId'] ?? '') ?? 0;
                                        return DetalhesTalhaoPage(atividadeId: atividadeId, talhaoId: talhaoId);
                                    }
                                )
                            ]
                        )
                    ]
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
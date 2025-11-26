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
import 'package:geoforestv1/providers/team_provider.dart';
import 'package:geoforestv1/pages/menu/visualizador_relatorio_page.dart';

// Imports dos Modelos
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';


class AppRouter {
  final LoginController loginController;
  final LicenseProvider licenseProvider;
  final TeamProvider teamProvider;

  AppRouter({
    required this.loginController,
    required this.licenseProvider,
    required this.teamProvider,
  });

  late final GoRouter router = GoRouter(
    refreshListenable: Listenable.merge([loginController, licenseProvider, teamProvider]),
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

      GoRoute(
      path: '/visualizar-relatorio',
      builder: (context, state) {
        final data = state.extra as Map<String, dynamic>;
        return VisualizadorRelatorioPage(
          diario: data['diario'] as DiarioDeCampo,
          parcelas: data['parcelas'] as List<Parcela>,
          cubagens: data['cubagens'] as List<CubagemArvore>,
        );
      },
    ),

      // ROTA PRINCIPAL DE PROJETOS E SUA HIERARQUIA ANINHADA
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
                routes: [
                  GoRoute(
                    path: ':atividadeId',
                    builder: (context, state) {
                      final atividadeId = int.tryParse(state.pathParameters['atividadeId'] ?? '') ?? 0;
                      return DetalhesAtividadePage(atividadeId: atividadeId);
                    },
                    routes: [
                        GoRoute(
                            path: 'fazendas/:fazendaId',
                            builder: (context, state) {
                                final atividadeId = int.tryParse(state.pathParameters['atividadeId'] ?? '') ?? 0;
                                final fazendaId = state.pathParameters['fazendaId'] ?? '';
                                return DetalhesFazendaPage(atividadeId: atividadeId, fazendaId: fazendaId);
                            },
                            routes: [
                                GoRoute(
                                    path: 'talhoes/:talhaoId',
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
      final String currentRoute = state.matchedLocation;

      // 1. Aguarda inicialização do LoginController
      if (!loginController.isInitialized) {
        return '/splash';
      }
      
      final bool isLoggedIn = loginController.isLoggedIn;

      // 2. Se NÃO está logado
      if (!isLoggedIn) {
        // Se já está no login ou splash, deixa ficar
        if (currentRoute == '/login' || currentRoute == '/splash') {
          return null;
        }
        // Senão, manda pro login
        return '/login';
      }

      // 3. Se ESTÁ logado, mas a licença ainda está carregando
      if (licenseProvider.isLoading) {
        // Manda pro Splash para não ficar travado na tela de Login com spinner infinito
        return '/splash';
      }
      
      final license = licenseProvider.licenseData;
      
      // 4. Se carregou mas não achou licença (erro ou usuário sem cadastro)
      if (license == null) {
        // Manda pro login para tentar outra conta (ou mostrar erro lá)
        return '/login';
      }
      
      // 5. Verifica status da assinatura
      final bool isLicenseOk = (license.status == 'ativa' || license.status == 'trial');
      if (!isLicenseOk) {
        return currentRoute == '/paywall' ? null : '/paywall';
      }
      
      // 6. Lógica de Gerente vs Equipe
      final bool isGerente = license.cargo == 'gerente';
      final bool precisaIdentificarEquipe = !isGerente && (teamProvider.lider == null || teamProvider.lider!.isEmpty);
      
      // Se precisa identificar a equipe e ainda não está na tela correta
      if (precisaIdentificarEquipe) {
        return currentRoute == '/equipe' ? null : '/equipe';
      }

      // 7. Redirecionamento final para a Home
      // Se o usuário está tentando acessar telas de "entrada" (login, splash, equipe) mas já está pronto:
      if (currentRoute == '/login' || currentRoute == '/splash' || (currentRoute == '/equipe' && !precisaIdentificarEquipe)) {
        return isGerente ? '/gerente_home' : '/home';
      }
      
      // Permite a navegação normal para qualquer outra rota
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
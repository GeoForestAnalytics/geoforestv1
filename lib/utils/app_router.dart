// lib/utils/app_router.dart (VERSÃO CORRIGIDA)

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';


// Imports dos Providers necessários para a lógica de redirecionamento
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


/// Configuração centralizada de navegação para o aplicativo.
class AppRouter {
  
  // ✅ 1. TORNAR OS PROVIDERS ACESSÍVEIS NA CLASSE
  // Em vez de passar o context, passamos as instâncias dos providers diretamente.
  final LoginController loginController;
  final LicenseProvider licenseProvider;

  AppRouter({
    required this.loginController,
    required this.licenseProvider,
  });

  late final GoRouter router = GoRouter(
    // ✅ 2. FAZER O ROUTER "OUVIR" AS MUDANÇAS NOS PROVIDERS
    // O `refreshListenable` é o gatilho que faltava. Ele diz ao go_router:
    // "Sempre que o LoginController ou o LicenseProvider notificarem uma mudança,
    // reavalie a lógica de `redirect`".
    // Usamos um `Listenable.merge` para combinar os dois em um único "ouvinte".
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
        path: '/lista_projetos',
        builder: (context, state) => const ListaProjetosPage(title: 'Meus Projetos'),
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
    ],

    // A mágica do redirecionamento acontece aqui
    redirect: (BuildContext context, GoRouterState state) {
      
      // ✅ 3. LÓGICA DE REDIRECIONAMENTO AJUSTADA
      // A lógica interna continua a mesma, mas agora ela será executada
      // nos momentos certos: na inicialização e sempre que o login ou a licença mudarem.

      // Se o LoginController ainda não terminou sua verificação inicial,
      // ficamos na tela de splash.
      if (!loginController.isInitialized) {
        return '/splash';
      }
      
      final bool isLoggedIn = loginController.isLoggedIn;
      final String currentRoute = state.matchedLocation;

      // 1. Lógica de Autenticação
      if (!isLoggedIn) {
        return currentRoute == '/login' ? null : '/login';
      }

      // 2. Lógica de Licença (só executa se o usuário já estiver logado)
      if (licenseProvider.isLoading) {
        return '/splash';
      }
      
      if (licenseProvider.error != null) {
        // Se houver um erro na licença, o AuthCheck no main.dart (que removemos)
        // exibia uma tela de erro. Podemos simular isso ou criar uma rota de erro.
        // Por enquanto, ficamos na tela atual.
        return null;
      }

      final license = licenseProvider.licenseData;
      if (license == null) {
        return '/login'; // Algo deu errado, força o logout.
      }
      
      final bool isLicenseOk = (license.status == 'ativa' || license.status == 'trial');

      if (!isLicenseOk) {
        return currentRoute == '/paywall' ? null : '/paywall';
      }
      
      // 3. Lógica de Redirecionamento Pós-Login e Pós-Licença OK
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
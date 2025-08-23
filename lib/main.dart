// lib/main.dart (VERSÃO CORRIGIDA)

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';

// Imports do projeto
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:geoforestv1/providers/theme_provider.dart';
import 'package:geoforestv1/pages/menu/home_page.dart';
import 'package:geoforestv1/pages/menu/login_page.dart';
import 'package:geoforestv1/pages/menu/equipe_page.dart';
import 'package:geoforestv1/providers/map_provider.dart';
import 'package:geoforestv1/providers/team_provider.dart';
import 'package:geoforestv1/controller/login_controller.dart';
import 'package:geoforestv1/pages/projetos/lista_projetos_page.dart';
import 'package:geoforestv1/pages/menu/splash_page.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:geoforestv1/pages/menu/paywall_page.dart';
import 'package:geoforestv1/pages/gerente/gerente_main_page.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geoforestv1/pages/gerente/gerente_map_page.dart';
import 'package:geoforestv1/providers/dashboard_filter_provider.dart';
import 'package:geoforestv1/providers/dashboard_metrics_provider.dart';
import 'package:geoforestv1/providers/operacoes_provider.dart';
import 'package:geoforestv1/providers/operacoes_filter_provider.dart';
import 'package:geoforestv1/models/atividade_model.dart';


void initializeProj4Definitions() {
  void addProjectionIfNotExists(String name, String definition) {
    try {
      proj4.Projection.get(name);
    } catch (_) {
      proj4.Projection.add(name, definition);
    }
  }
  addProjectionIfNotExists('EPSG:4326', '+proj=longlat +datum=WGS84 +no_defs');
  proj4Definitions.forEach((epsg, def) {
    addProjectionIfNotExists('EPSG:$epsg', def);
  });
  debugPrint("Definições Proj4 inicializadas/verificadas.");
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeProj4Definitions();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  runApp(const AppServicesLoader());
}

class AppServicesLoader extends StatefulWidget {
  const AppServicesLoader({super.key});
  @override
  State<AppServicesLoader> createState() => _AppServicesLoaderState();
}

class _AppServicesLoaderState extends State<AppServicesLoader> {
  late Future<ThemeMode> _initializationFuture;

  @override
  void initState() {
    super.initState();
    _initializationFuture = _initializeAllServices();
  }

  Future<ThemeMode> _initializeAllServices() async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      const androidProvider = kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity;
      await FirebaseAppCheck.instance.activate(androidProvider: androidProvider);
      print("Firebase App Check ativado com sucesso.");
      await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
      );
      return await loadThemeFromPreferences();
    } catch (e) {
      print("!!!!!! ERRO NA INICIALIZAÇÃO DOS SERVIÇOS: $e !!!!!");
      rethrow;
    }
  }

  void _retryInitialization() {
    setState(() {
      _initializationFuture = _initializeAllServices();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ThemeMode>(
      future: _initializationFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: ErrorScreen(
              message: "Falha ao inicializar os serviços do aplicativo:\n${snapshot.error.toString()}",
              onRetry: _retryInitialization,
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: SplashPage(),
          );
        }
        return MyApp(initialThemeMode: snapshot.data!);
      },
    );
  }
}

class MyApp extends StatelessWidget {
  final ThemeMode initialThemeMode;

  const MyApp({super.key, required this.initialThemeMode});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LoginController()),
        ChangeNotifierProvider(create: (_) => MapProvider()),
        ChangeNotifierProvider(create: (_) => TeamProvider()),
        ChangeNotifierProvider(create: (_) => LicenseProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider(initialThemeMode)),
        
        ChangeNotifierProvider(create: (_) => GerenteProvider()),

        ChangeNotifierProxyProvider<GerenteProvider, DashboardFilterProvider>(
          create: (_) => DashboardFilterProvider(),
          update: (_, gerenteProvider, previous) {
            final filter = previous ?? DashboardFilterProvider();
            
            filter.updateProjetosDisponiveis(gerenteProvider.projetos);

            List<Atividade> atividadesParaFiltro = filter.selectedProjetoIds.isEmpty
                ? gerenteProvider.atividades
                : gerenteProvider.atividades.where((a) => filter.selectedProjetoIds.contains(a.projetoId)).toList();
            filter.updateAtividadesDisponiveis(atividadesParaFiltro);

            List<Parcela> parcelasParaFiltroDeFazenda = gerenteProvider.parcelasSincronizadas;
            
            if (filter.selectedProjetoIds.isNotEmpty) {
              parcelasParaFiltroDeFazenda = parcelasParaFiltroDeFazenda
                  .where((p) => filter.selectedProjetoIds.contains(p.projetoId)).toList();
            }
            
            // <<< INÍCIO DA CORREÇÃO >>>
            // A lógica agora usa a nova propriedade 'selectedAtividadeTipos'
            if (filter.selectedAtividadeTipos.isNotEmpty) {
              // Primeiro, encontramos os IDs de todas as atividades que correspondem aos tipos selecionados
              final idsDeAtividadesFiltradas = gerenteProvider.atividades
                  .where((a) => filter.selectedAtividadeTipos.contains(a.tipo))
                  .map((a) => a.id)
                  .toSet();
                  
              // Depois, filtramos as parcelas, verificando se o ID da atividade da parcela está no conjunto de IDs que encontramos
              parcelasParaFiltroDeFazenda = parcelasParaFiltroDeFazenda.where((p) {
                final atividadeId = gerenteProvider.talhaoToAtividadeMap[p.talhaoId];
                return atividadeId != null && idsDeAtividadesFiltradas.contains(atividadeId);
              }).toList();
            }
            // <<< FIM DA CORREÇÃO >>>
            
            filter.updateFazendasDisponiveis(parcelasParaFiltroDeFazenda);
            
            return filter;
          },
        ),
        ChangeNotifierProxyProvider<GerenteProvider, OperacoesFilterProvider>(
          create: (_) => OperacoesFilterProvider(),
          update: (_, gerenteProvider, previous) {
            final filter = previous ?? OperacoesFilterProvider();
            final lideres = gerenteProvider.diariosSincronizados.map((d) => d.nomeLider).toSet().toList();
            filter.setLideresDisponiveis(lideres);
            return filter;
          },
        ),
        
        ChangeNotifierProxyProvider2<GerenteProvider, DashboardFilterProvider, DashboardMetricsProvider>(
          create: (_) => DashboardMetricsProvider(),
          update: (_, gerenteProvider, filterProvider, previous) {
            final metrics = previous ?? DashboardMetricsProvider();
            metrics.update(gerenteProvider, filterProvider);
            return metrics;
          },
        ),
        ChangeNotifierProxyProvider2<GerenteProvider, OperacoesFilterProvider, OperacoesProvider>(
          create: (_) => OperacoesProvider(),
          update: (_, gerenteProvider, filterProvider, previous) {
            final operacoes = previous ?? OperacoesProvider();
            operacoes.update(gerenteProvider, filterProvider);
            return operacoes;
          },
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
              return MaterialApp(
            title: 'Geo Forest Analytics',
            debugShowCheckedModeBanner: false,
            theme: _buildThemeData(Brightness.light),
            darkTheme: _buildThemeData(Brightness.dark),
            themeMode: themeProvider.themeMode,
            initialRoute: '/auth_check',
            routes: {
              '/auth_check': (context) => const AuthCheck(),
              '/equipe': (context) => const EquipePage(),
              '/home': (context) => const HomePage(title: 'Geo Forest Analytics'),
              '/lista_projetos': (context) => const ListaProjetosPage(title: 'Meus Projetos'),
              '/login': (context) => const LoginPage(),
              '/paywall': (context) => const PaywallPage(),
              '/gerente_home': (context) => const GerenteMainPage(),
              '/gerente_map': (context) => const GerenteMapPage(),
            },
            navigatorObservers: [MapProvider.routeObserver],
            builder: (context, child) {
              ErrorWidget.builder = (FlutterErrorDetails details) {
                debugPrint('Caught a Flutter error: ${details.exception}');
                return ErrorScreen(
                  message: 'Ocorreu um erro inesperado.\nPor favor, reinicie o aplicativo.',
                  onRetry: null,
                );
              };
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
                child: child!,
              );
            },
          );
        },
      ),
    );
  }

  ThemeData _buildThemeData(Brightness brightness) {
    final baseColor = const Color(0xFF617359);
    final isLight = brightness == Brightness.light;

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: baseColor,
        brightness: brightness,
        surface: isLight ? const Color(0xFFF3F3F4) : Colors.grey[900],
        background: isLight ? Colors.white : Colors.black,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? baseColor : Colors.grey[850],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: baseColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: isLight ? Colors.white : Colors.grey.shade800,
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(color: isLight ? const Color(0xFF1D4433) : Colors.white, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(color: isLight ? const Color(0xFF1D4433) : Colors.grey.shade300),
        bodyMedium: TextStyle(color: isLight ? const Color(0xFF1D4433) : Colors.grey.shade300),
        titleLarge: TextStyle(color: isLight ? const Color(0xFF1D4433) : Colors.white, fontWeight: FontWeight.bold),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
      ),
    );
  }
}

class AuthCheck extends StatelessWidget {
  const AuthCheck({super.key});

  @override
  Widget build(BuildContext context) {
    final loginController = context.watch<LoginController>();
    final licenseProvider = context.watch<LicenseProvider>();

    if (!loginController.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!loginController.isLoggedIn) {
      return const LoginPage();
    }
    
    if (licenseProvider.error != null && !licenseProvider.isLoading) {
      return ErrorScreen(
        message: "Não foi possível verificar sua licença:\n${licenseProvider.error}",
        onRetry: () => context.read<LicenseProvider>().fetchLicenseData(),
      );
    }

    if (licenseProvider.isLoading || licenseProvider.licenseData == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final license = licenseProvider.licenseData!;
    final bool isLicenseOk = (license.status == 'ativa' || license.status == 'trial');

    if (isLicenseOk) {
      if (license.cargo == 'gerente') {
        return const GerenteMainPage();
      } else {
        return const EquipePage();
      }
    } else {
      return const PaywallPage();
    }
  }
}

class ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorScreen({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 60),
              const SizedBox(height: 20),
              Text('Erro na Aplicação', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 30),
              if (onRetry != null)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF617359), foregroundColor: Colors.white),
                  onPressed: onRetry,
                  child: const Text('Tentar Novamente'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
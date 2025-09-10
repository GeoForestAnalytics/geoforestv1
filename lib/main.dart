// lib/main.dart (VERSÃO FINAL COM GO_ROUTER)

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';

// Imports do projeto
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:geoforestv1/providers/theme_provider.dart';
import 'package:geoforestv1/providers/map_provider.dart';
import 'package:geoforestv1/providers/team_provider.dart';
import 'package:geoforestv1/controller/login_controller.dart';
import 'package:geoforestv1/pages/menu/splash_page.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geoforestv1/providers/dashboard_filter_provider.dart';
import 'package:geoforestv1/providers/dashboard_metrics_provider.dart';
import 'package:geoforestv1/providers/operacoes_provider.dart';
import 'package:geoforestv1/providers/operacoes_filter_provider.dart';
import 'package:geoforestv1/utils/app_router.dart'; // ✅ 1. IMPORTAR O NOVO ROTEADOR


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

  const androidProvider = kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity;
  await FirebaseAppCheck.instance.activate(androidProvider: androidProvider);
  print("Firebase App Check ativado com sucesso no main().");

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
        // Providers independentes
        ChangeNotifierProvider(create: (_) => LoginController()),
        ChangeNotifierProvider(create: (_) => MapProvider()),
        ChangeNotifierProvider(create: (_) => TeamProvider()),
        ChangeNotifierProvider(create: (_) => LicenseProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider(initialThemeMode)),
        ChangeNotifierProvider(create: (_) => GerenteProvider()),

        // Proxy Providers
        ChangeNotifierProxyProvider<GerenteProvider, DashboardFilterProvider>(
          create: (_) => DashboardFilterProvider(),
          update: (_, gerenteProvider, previousFilter) {
            final filter = previousFilter ?? DashboardFilterProvider();
            filter.updateFiltersFrom(gerenteProvider);
            return filter;
          },
        ),
        ChangeNotifierProxyProvider<GerenteProvider, OperacoesFilterProvider>(
          create: (_) => OperacoesFilterProvider(),
          update: (_, gerenteProvider, previousFilter) {
            final filter = previousFilter ?? OperacoesFilterProvider();
            filter.updateFiltersFrom(gerenteProvider);
            return filter;
          },
        ),
        ChangeNotifierProxyProvider2<GerenteProvider, DashboardFilterProvider, DashboardMetricsProvider>(
          create: (_) => DashboardMetricsProvider(),
          update: (_, gerenteProvider, filterProvider, previousMetrics) {
            final metrics = previousMetrics ?? DashboardMetricsProvider();
            metrics.update(gerenteProvider, filterProvider);
            return metrics;
          },
        ),
        ChangeNotifierProxyProvider2<GerenteProvider, OperacoesFilterProvider, OperacoesProvider>(
          create: (_) => OperacoesProvider(),
          update: (_, gerenteProvider, filterProvider, previousOperacoes) {
            final operacoes = previousOperacoes ?? OperacoesProvider();
            operacoes.update(gerenteProvider, filterProvider);
            return operacoes;
          },
        ),
      ],
      // ✅ 2. O `Consumer` agora envolve a criação do MaterialApp.router
      // Isso garante que o AppRouter tenha acesso aos providers que ele precisa para o redirecionamento.
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          // ✅ A instância do roteador agora lê os providers diretamente do context.
          final appRouter = AppRouter(
            loginController: context.read<LoginController>(),
            licenseProvider: context.read<LicenseProvider>(),
            teamProvider: context.read<TeamProvider>(), // ✅ 2. ADICIONE ESTA LINHA
          ).router;

          // ✅ 3. MUDANÇA PARA `MaterialApp.router`
          // Trocamos o `MaterialApp` padrão pela sua versão que usa um roteador.
          return MaterialApp.router(
            routerConfig: appRouter, // Passa a configuração do go_router
            
            title: 'Geo Forest Analytics',
            debugShowCheckedModeBanner: false,
            theme: _buildThemeData(Brightness.light),
            darkTheme: _buildThemeData(Brightness.dark),
            themeMode: themeProvider.themeMode,

            // As propriedades `initialRoute` e `routes` são removidas,
            // pois o go_router agora controla isso.
            
            // `navigatorObservers` e `builder` continuam funcionando normalmente.
            // O go_router internamente usa o Navigator 2.0, então isso é compatível.
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
    final baseColor = const Color.fromARGB(255, 13, 58, 89);
    final isLight = brightness == Brightness.light;

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: baseColor,
        brightness: brightness,
        surface: isLight ? const Color.fromARGB(255, 255, 255, 255) : Colors.grey[900],
        background: isLight ? const Color.fromARGB(255, 255, 255, 255) : Colors.black,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? baseColor : Colors.grey[850],
        foregroundColor: const Color.fromARGB(255, 255, 255, 255),
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: baseColor,
          foregroundColor: const Color.fromARGB(255, 255, 255, 255),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: isLight ? const Color.fromARGB(255, 255, 255, 255) : Colors.grey.shade800,
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(color: isLight ? const Color.fromARGB(255, 13, 58, 89) : Colors.white, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(color: isLight ? const Color.fromARGB(255, 13, 58, 89) : Colors.grey.shade300),
        bodyMedium: TextStyle(color: isLight ? const Color.fromARGB(255, 13, 58, 89) : Colors.grey.shade300),
        titleLarge: TextStyle(color: isLight ? const Color.fromARGB(255, 13, 58, 89) : Colors.white, fontWeight: FontWeight.bold),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
      ),
    );
  }
}

// ✅ 4. O WIDGET `AuthCheck` NÃO É MAIS NECESSÁRIO!
// Toda a sua lógica foi movida para a função `redirect` do AppRouter.
// Você pode apagar esta classe inteira.
/*
class AuthCheck extends StatelessWidget {
  const AuthCheck({super.key});

  @override
  Widget build(BuildContext context) {
    // ... toda a lógica antiga ...
  }
}
*/

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
                  style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 9, 12, 65), foregroundColor: Colors.white),
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
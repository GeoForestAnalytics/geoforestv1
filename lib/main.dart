// lib/main.dart (VERSÃO FINAL COM TODAS AS CORREÇÕES DE INICIALIZAÇÃO)

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; 
import 'package:provider/provider.dart';
import 'firebase_options.dart';

// <<< 1. IMPORTS ADICIONAIS PARA INICIALIZAÇÃO GLOBAL DO PROJ4 >>>
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;

// Importações do Projeto
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

// <<< 2. FUNÇÃO GLOBAL PARA INICIALIZAR AS DEFINIÇÕES DE PROJEÇÃO >>>
// Garante que as definições de coordenadas estejam disponíveis tanto para a
// thread principal (usada na exportação) quanto para qualquer isolate.
void initializeProj4Definitions() {
  try {
    // Verifica se já foi inicializado para não fazer de novo.
    proj4.Projection.get('EPSG:4326');
  } catch (_) {
    debugPrint("Inicializando definições Proj4 para o escopo global...");
    proj4.Projection.add('EPSG:4326', '+proj=longlat +datum=WGS84 +no_defs');
    proj4Definitions.forEach((epsg, def) {
      proj4.Projection.add('EPSG:$epsg', def);
    });
  }
}

// PONTO DE ENTRADA PRINCIPAL DO APP
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // <<< 3. INICIALIZAÇÃO DO PROJ4 APLICADA AQUI >>>
  // Isso resolve o problema de exportação de coordenadas.
  initializeProj4Definitions();

  // A sua correção crítica para o FFI, que já estava correta, permanece aqui.
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

// AppServicesLoader (Nenhuma mudança aqui, permanece igual)
class AppServicesLoader extends StatefulWidget {
  const AppServicesLoader({super.key});

  @override
  State<AppServicesLoader> createState() => _AppServicesLoaderState();
}

class _AppServicesLoaderState extends State<AppServicesLoader> {
  late Future<void> _servicesInitializationFuture;

  @override
  void initState() {
    super.initState();
    _servicesInitializationFuture = _initializeRemainingServices();
  }

  Future<void> _initializeRemainingServices() async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      const androidProvider = kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity;
      await FirebaseAppCheck.instance.activate(androidProvider: androidProvider);
      print("Firebase App Check ativado com sucesso.");
      await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
      );
    } catch (e) {
      print("!!!!!! ERRO NA INICIALIZAÇÃO DOS SERVIÇOS: $e !!!!!");
      rethrow;
    }
  }

  void _retryInitialization() {
    setState(() {
      _servicesInitializationFuture = _initializeRemainingServices();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _servicesInitializationFuture,
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
        return const MyApp();
      },
    );
  }
}

// MyApp (Nenhuma mudança aqui, permanece igual)
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LoginController()),
        ChangeNotifierProvider(create: (_) => MapProvider()),
        ChangeNotifierProvider(create: (_) => TeamProvider()),
        ChangeNotifierProvider(create: (_) => LicenseProvider()),
        ChangeNotifierProvider(create: (_) => GerenteProvider()),
      ],
      child: MaterialApp(
        title: 'Geo Forest Analytics',
        debugShowCheckedModeBanner: false,
        theme: _buildThemeData(Brightness.light),
        darkTheme: _buildThemeData(Brightness.dark),
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
      ),
    );
  }

  ThemeData _buildThemeData(Brightness brightness) {
    final baseColor = const Color(0xFF617359);
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: baseColor, brightness: brightness),
      appBarTheme: AppBarTheme(
        backgroundColor: brightness == Brightness.light ? baseColor : Colors.grey[900],
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
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(color: Color(0xFF1D4433), fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(color: Color(0xFF1D4433)),
        bodyMedium: TextStyle(color: Color(0xFF1D4433)),
      ),
    );
  }
}

// AuthCheck (Nenhuma mudança aqui, permanece igual)
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

// ErrorScreen (Nenhuma mudança aqui, permanece igual)
class ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorScreen({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F4),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red[700], size: 60),
              const SizedBox(height: 20),
              Text('Erro na Aplicação', style: TextStyle(color: Colors.red[700], fontSize: 24, fontWeight: FontWeight.bold)),
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
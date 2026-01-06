import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'package:google_fonts/google_fonts.dart'; // Fonte Importada


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
import 'package:geoforestv1/utils/app_router.dart';
import 'package:geoforestv1/utils/app_config.dart';

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

  // 1. Configuração do Banco de Dados (Protegido para não quebrar na Web)
  if (!kIsWeb) {
    // Código que só roda no Celular/Desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  } else {
    // Web não suporta sqflite_ffi direto.
    // Se for usar banco local na web, precisaria de configuração extra (sqflite_common_ffi_web).
    // Por enquanto, deixamos vazio para não travar o app.
  }

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  // 2. Configuração do App Check com a sua chave
  await FirebaseAppCheck.instance.activate(
    // Android
    androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
    
    // iOS
    appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
    
    // WEB: Chave de Site do ReCaptcha (configurável via AppConfig)
    webProvider: ReCaptchaV3Provider(AppConfig.recaptchaSiteKey), 
  );

  debugPrint("Firebase App Check ativado com sucesso.");

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
    } catch (e, stackTrace) {
      debugPrint("ERRO NA INICIALIZAÇÃO DOS SERVIÇOS: $e");
      debugPrint("Stack trace: $stackTrace");
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
              message:
                  "Falha ao inicializar os serviços do aplicativo:\n${snapshot.error.toString()}",
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
        ChangeNotifierProxyProvider2<GerenteProvider, DashboardFilterProvider,
            DashboardMetricsProvider>(
          create: (_) => DashboardMetricsProvider(),
          update: (_, gerenteProvider, filterProvider, previousMetrics) {
            final metrics = previousMetrics ?? DashboardMetricsProvider();
            metrics.update(gerenteProvider, filterProvider);
            return metrics;
          },
        ),
        ChangeNotifierProxyProvider2<GerenteProvider, OperacoesFilterProvider,
            OperacoesProvider>(
          create: (_) => OperacoesProvider(),
          update: (_, gerenteProvider, filterProvider, previousOperacoes) {
            final operacoes = previousOperacoes ?? OperacoesProvider();
            operacoes.update(gerenteProvider, filterProvider);
            return operacoes;
          },
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          final appRouter = AppRouter(
            loginController: context.read<LoginController>(),
            licenseProvider: context.read<LicenseProvider>(),
            teamProvider: context.read<TeamProvider>(),
          ).router;

          return MaterialApp.router(
            routerConfig: appRouter,
            title: 'Geo Forest Analytics',
            debugShowCheckedModeBanner: false,
            theme: _buildThemeData(Brightness.light),
            darkTheme: _buildThemeData(Brightness.dark),
            themeMode: themeProvider.themeMode,
            builder: (context, child) {
              ErrorWidget.builder = (FlutterErrorDetails details) {
                debugPrint('Caught a Flutter error: ${details.exception}');
                return ErrorScreen(
                  message:
                      'Ocorreu um erro inesperado.\nPor favor, reinicie o aplicativo.',
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
    // PALETA PREMIUM
    const primaryNavy = Color(0xFF023853);
    const accentGold = Color(0xFFEBE4AB);

    final isLight = brightness == Brightness.light;

    // Cores de fundo e superfície
    final bgColor = isLight ? const Color(0xFFF5F7FA) : const Color(0xFF023853);
    final surfaceColor = isLight ? Colors.white : const Color(0xFF011D2E);
    final textColor = isLight ? primaryNavy : Colors.white;

    return ThemeData(
      useMaterial3: true,
      brightness:
          brightness, // Importante para o Flutter calcular contrastes automáticos
      textTheme: GoogleFonts.montserratTextTheme(
        isLight ? ThemeData.light().textTheme : ThemeData.dark().textTheme,
      ).apply(
        bodyColor: textColor,
        displayColor: textColor,
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryNavy,
        brightness: brightness,
        primary: primaryNavy,
        onPrimary: accentGold,
        secondary: accentGold,
        onSecondary: primaryNavy,
        surface: surfaceColor,
        background: bgColor,
        error: Colors.redAccent,
      ),
      scaffoldBackgroundColor: bgColor,
      appBarTheme: AppBarTheme(
        backgroundColor: primaryNavy,
        foregroundColor: accentGold,
        centerTitle: true,
        elevation: 4,
        titleTextStyle: GoogleFonts.montserrat(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: accentGold,
            letterSpacing: 1.2),
      ),
      cardTheme: CardThemeData(
        elevation: 4,
        color: surfaceColor, // Card escuro no modo dark
        shadowColor: Colors.black45,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: isLight ? Colors.transparent : accentGold.withOpacity(0.3),
              width: 1),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor:
            MaterialStateProperty.all(primaryNavy.withOpacity(0.8)),
        headingTextStyle: GoogleFonts.montserrat(
            color: accentGold, fontWeight: FontWeight.bold),
        dataTextStyle: GoogleFonts.montserrat(color: textColor),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryNavy,
          foregroundColor: accentGold,
          elevation: 5,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          textStyle:
              GoogleFonts.montserrat(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Colors.white : Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryNavy),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isLight
                  ? primaryNavy.withOpacity(0.3)
                  : accentGold.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryNavy, width: 2),
        ),
        labelStyle: TextStyle(color: isLight ? primaryNavy : accentGold),
        prefixIconColor: isLight ? primaryNavy : accentGold,
        hintStyle:
            TextStyle(color: isLight ? Colors.grey : Colors.grey.shade400),
      ),
    );
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
              Icon(Icons.error_outline,
                  color: Theme.of(context).colorScheme.error, size: 60),
              const SizedBox(height: 20),
              Text('Erro na Aplicação',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 30),
              if (onRetry != null)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 9, 12, 65),
                      foregroundColor: Colors.white),
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

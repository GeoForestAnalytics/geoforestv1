// lib/pages/menu/home_page.dart (VERSÃO CORRIGIDA - MODAL ADAPTATIVO)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

// Importações do Projeto
import 'package:geoforestv1/pages/analises/analise_selecao_page.dart';
import 'package:geoforestv1/pages/menu/configuracoes_page.dart';
import 'package:geoforestv1/pages/planejamento/selecao_atividade_mapa_page.dart';
import 'package:geoforestv1/pages/menu/paywall_page.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:geoforestv1/services/export_service.dart';
import 'package:geoforestv1/widgets/menu_card.dart';
import 'package:geoforestv1/services/sync_service.dart';
import 'package:geoforestv1/models/sync_progress_model.dart';
import 'package:geoforestv1/pages/menu/conflict_resolution_page.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';

class HomePage extends StatefulWidget {
  final String title;
  final bool showAppBar;

  const HomePage({
    super.key,
    required this.title,
    this.showAppBar = true,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isSyncing = false;

  // --- MÉTODO CORRIGIDO: IMPORTAÇÃO ---
  void _mostrarDialogoImportacao(BuildContext context) {
    // 1. Detecta o tema
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 2. Define cores baseadas no tema
    // Escuro: Fundo Azul Navy / Claro: Fundo Branco
    final Color bgColor = isDark ? const Color(0xFF0F172A).withOpacity(0.95) : Colors.white.withOpacity(0.95);
    final Color textColor = isDark ? Colors.white : const Color(0xFF023853);
    final Color subTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor, // Aplica a cor dinâmica
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Wrap(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Text(
              'Importar Dados para um Projeto', 
              // Força a cor do título
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: textColor)
            ),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined, color: Colors.blue),
            title: Text(
              'Importar Arquivo CSV Universal',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              'Selecione o projeto de destino para os dados.',
              style: TextStyle(color: subTextColor),
            ),
            onTap: () {
              Navigator.of(ctx).pop();
              context.push(
                '/projetos',
                extra: {
                  'title': 'Importar para o Projeto...',
                  'isImporting': true,
                },
              );
            },
          ),
          const SizedBox(height: 20), // Espaço extra no final
        ],
      ),
    );
  }

  void _abrirAnalistaDeDados(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AnaliseSelecaoPage()),
    );
  }
  
  // --- MÉTODO CORRIGIDO: EXPORTAÇÃO ---
  void _mostrarDialogoExportacao(BuildContext context) {
    final exportService = ExportService();

    // 1. Detecta o tema
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 2. Define cores
    final Color bgColor = isDark ? const Color(0xFF0F172A).withOpacity(0.95) : Colors.white.withOpacity(0.95);
    final Color textColor = isDark ? Colors.white : const Color(0xFF023853);
    // ignore: unused_local_variable
    final Color subTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;

    void _mostrarDialogoTipo(BuildContext mainDialogContext, {required Function() onNovas, required Function() onTodas}) {
        showDialog(
            context: mainDialogContext,
            builder: (dialogCtx) => AlertDialog(
                backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                title: Text('Tipo de Exportação', style: TextStyle(color: textColor)),
                content: Text(
                  'Deseja exportar apenas os dados novos ou um backup completo?',
                  style: TextStyle(color: textColor),
                ),
                actions: [
                    TextButton(
                        // --- CORREÇÃO AQUI: Forçando a cor do texto ---
                        style: TextButton.styleFrom(
                          foregroundColor: textColor, // Usa Branco no Dark e Azul no Light
                        ),
                        // ----------------------------------------------
                        child: const Text('Apenas Novas'),
                        onPressed: () {
                            Navigator.of(dialogCtx).pop(); 
                            onNovas(); 
                        },
                    ),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF023853),
                          foregroundColor: const Color(0xFFEBE4AB),
                        ),
                        child: const Text('Todas (Backup)'),
                        onPressed: () {
                            Navigator.of(dialogCtx).pop();
                            onTodas();
                        },
                    ),
                ],
            ),
        );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor, // Aplica a cor dinâmica
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Wrap(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Text(
              'Opções de Exportação',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: textColor),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.table_rows_outlined, color: Colors.green),
            title: Text(
              'Coletas de Parcela (CSV)',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
            ),
            onTap: () {
              Navigator.of(ctx).pop(); 
              _mostrarDialogoTipo(
                  context,
                  onNovas: () => exportService.exportarDados(context),
                  onTodas: () => exportService.exportarTodasAsParcelasBackup(context),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined, color: Colors.brown),
            title: Text(
              'Cubagens Rigorosas (CSV)',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
            ),
            onTap: () {
              Navigator.of(ctx).pop();
              _mostrarDialogoTipo(
                  context,
                  onNovas: () => exportService.exportarNovasCubagens(context),
                  onTodas: () => exportService.exportarTodasCubagensBackup(context),
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _mostrarAvisoDeUpgrade(BuildContext context, String featureName) {
    // Também ajustamos o Dialog para garantir contraste
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text("Funcionalidade indisponível", style: TextStyle(color: textColor)),
        content: Text(
          "A função '$featureName' não está disponível no seu plano atual. Faça upgrade para desbloqueá-la.",
          style: TextStyle(color: textColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Entendi"),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallPage()));
            },
            child: const Text("Ver Planos"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final licenseProvider = context.watch<LicenseProvider>();
    final bool podeExportar = licenseProvider.licenseData?.features['exportacao'] ?? true;
    final bool podeAnalisar = licenseProvider.licenseData?.features['analise'] ?? true;

    // --- CORES DO GRADIENTE ---
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color darkTop = const Color.fromARGB(147, 6, 140, 173); 
    final Color darkBottom = const Color.fromARGB(255, 1, 26, 39); 
    final Color lightTop = const Color.fromARGB(255, 255, 250, 215); 
    final Color lightBottom = const Color.fromARGB(255, 255, 255, 255); 

    final List<Color> gradientColors = isDark 
        ? [darkTop, darkBottom] 
        : [lightTop, lightBottom];

    final Color appBarContentColor = const Color(0xFF023853);

    return Scaffold(
      extendBodyBehindAppBar: true, 
      
      appBar: widget.showAppBar 
        ? AppBar(
            title: Text(
              widget.title,
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.bold,
                color: appBarContentColor
              ),
            ),
            centerTitle: true,
            backgroundColor: Colors.transparent, 
            elevation: 0,
            iconTheme: IconThemeData(color: appBarContentColor),
            systemOverlayStyle: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark, 
            ),
          ) 
        : null,
      
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: gradientColors, 
            stops: isDark ? const [0.0, 0.8] : const [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12.0,
              mainAxisSpacing: 12.0,
              childAspectRatio: 1.0,
              children: [
                MenuCard(
                  index: 0,
                  icon: Icons.folder_copy_outlined,
                  label: 'Projetos e Coletas',
                  onTap: () => context.push('/projetos'),
                ),
                MenuCard(
                  index: 1,
                  icon: Icons.map_outlined,
                  label: 'Planejamento de Campo',
                  onTap: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                const SelecaoAtividadeMapaPage()));
                  },
                ),
                MenuCard(
                  icon: Icons.insights_outlined,
                  label: 'GeoForest Analista',
                  onTap: podeAnalisar
                      ? () => _abrirAnalistaDeDados(context)
                      : () => _mostrarAvisoDeUpgrade(context, "GeoForest Analista"),
                ),
                MenuCard(
                  icon: Icons.download_for_offline_outlined,
                  label: 'Importar Dados (CSV)',
                  onTap: () => _mostrarDialogoImportacao(context),
                ),
                MenuCard(
                  icon: Icons.upload_file_outlined,
                  label: 'Exportar Dados',
                  onTap: podeExportar
                      ? () => _mostrarDialogoExportacao(context)
                      : () => _mostrarAvisoDeUpgrade(context, "Exportar Dados"),
                ),
                MenuCard(
                  icon: Icons.settings_outlined,
                  label: 'Configurações',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ConfiguracoesPage()),
                  ),
                ),
                MenuCard(
                  icon: Icons.credit_card,
                  label: 'Assinaturas',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PaywallPage()),
                  ),
                ),
                MenuCard(
                  icon: _isSyncing ? Icons.downloading_outlined : Icons.sync_outlined,
                  label: _isSyncing ? 'Sincronizando...' : 'Sincronizar Dados',
                  onTap: _isSyncing ? () {} : _executarSincronizacao,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _executarSincronizacao() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    
    final syncService = SyncService();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StreamBuilder<SyncProgress>(
          stream: syncService.progressStream,
          builder: (context, snapshot) {
            final progress = snapshot.data;
            
            if (progress?.concluido == true) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.of(dialogContext).pop(); 
                
                if (syncService.conflicts.isNotEmpty && mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ConflictResolutionPage(conflicts: syncService.conflicts),
                    ),
                  );
                } else if (progress?.erro == null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Dados sincronizados com sucesso!'), backgroundColor: Colors.green),
                  );
                }

                if (mounted) {
                  context.read<GerenteProvider>().iniciarMonitoramento();
                  setState(() => _isSyncing = false);
                }
              });
              return const SizedBox.shrink(); 
            }

            return AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(progress?.mensagem ?? 'Iniciando...'),
                  if ((progress?.totalAProcessar ?? 0) > 0) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: (progress!.processados / progress.totalAProcessar)),
                  ]
                ],
              ),
            );
          },
        );
      },
    );

    try {
      await syncService.sincronizarDados();
    } catch (e) {
      debugPrint("Erro grave na sincronização capturado na UI: $e");
    }
  }
}
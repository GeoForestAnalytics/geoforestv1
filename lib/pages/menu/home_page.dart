// lib/pages/menu/home_page.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

// Importações do Projeto
import 'package:geoforestv1/pages/analises/analise_selecao_page.dart';
import 'package:geoforestv1/pages/menu/configuracoes_page.dart';
import 'package:geoforestv1/pages/planejamento/selecao_atividade_mapa_page.dart';
import 'package:geoforestv1/pages/menu/paywall_page.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:geoforestv1/services/export_service.dart';
import 'package:geoforestv1/services/sync_service.dart';
import 'package:geoforestv1/models/sync_progress_model.dart';
import 'package:geoforestv1/pages/menu/conflict_resolution_page.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';

// Importações dos Novos Widgets
import 'package:geoforestv1/widgets/weather_header.dart';
import 'package:geoforestv1/widgets/modern_menu_tile.dart';

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
  SyncProgress? _currentSyncProgress;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('pt_BR', null);
  }

  // --- MÉTODOS AUXILIARES ---

  void _mostrarDialogoImportacao(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF0F172A).withOpacity(0.95) : Colors.white.withOpacity(0.95);
    final Color textColor = isDark ? Colors.white : const Color(0xFF023853);
    final Color subTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Wrap(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Text(
              'Importar Dados para um Projeto', 
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
          const SizedBox(height: 20),
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
  
  void _mostrarDialogoExportacao(BuildContext context) {
    final exportService = ExportService();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF0F172A).withOpacity(0.95) : Colors.white.withOpacity(0.95);
    final Color textColor = isDark ? Colors.white : const Color(0xFF023853);

    void mostrarDialogoTipo(BuildContext mainDialogContext, {required Function() onNovas, required Function() onTodas}) {
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
                        style: TextButton.styleFrom(foregroundColor: textColor),
                        child: const Text('Apenas Novas'),
                        onPressed: () { Navigator.of(dialogCtx).pop(); onNovas(); },
                    ),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF023853),
                          foregroundColor: const Color(0xFFEBE4AB),
                        ),
                        child: const Text('Todas (Backup)'),
                        onPressed: () { Navigator.of(dialogCtx).pop(); onTodas(); },
                    ),
                ],
            ),
        );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Wrap(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Text('Opções de Exportação', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: textColor)),
          ),
          ListTile(
            leading: const Icon(Icons.table_rows_outlined, color: Colors.green),
            title: Text('Coletas de Parcela (CSV)', style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
            onTap: () {
              Navigator.of(ctx).pop(); 
              mostrarDialogoTipo(context, onNovas: () => exportService.exportarDados(context), onTodas: () => exportService.exportarTodasAsParcelasBackup(context));
            },
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined, color: Colors.brown),
            title: Text('Cubagens Rigorosas (CSV)', style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
            onTap: () {
              Navigator.of(ctx).pop();
              mostrarDialogoTipo(context, onNovas: () => exportService.exportarNovasCubagens(context), onTodas: () => exportService.exportarTodasCubagensBackup(context));
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _mostrarAvisoDeUpgrade(BuildContext context, String featureName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        title: Text("Funcionalidade indisponível", style: TextStyle(color: textColor)),
        content: Text("A função '$featureName' não está disponível no seu plano atual.", style: TextStyle(color: textColor)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Entendi")),
          FilledButton(
            onPressed: () { Navigator.of(ctx).pop(); Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallPage())); },
            child: const Text("Ver Planos"),
          ),
        ],
      ),
    );
  }

  Future<void> _executarSincronizacao() async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
      _currentSyncProgress = null;
    });

    final syncService = SyncService();

    // Atualiza o botão em tempo real com o progresso
    syncService.progressStream.listen((p) {
      if (mounted) setState(() => _currentSyncProgress = p);
    });

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StreamBuilder<SyncProgress>(
          stream: syncService.progressStream,
          builder: (context, snapshot) {
            final progress = snapshot.data;
            if (progress?.concluido == true) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.of(dialogContext).pop();
                if (syncService.conflicts.isNotEmpty && mounted) {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => ConflictResolutionPage(conflicts: syncService.conflicts)));
                } else if (progress?.erro == null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dados sincronizados com sucesso!'), backgroundColor: Colors.green));
                }
                if (mounted) {
                  context.read<GerenteProvider>().iniciarMonitoramentoEstrutural;
                  setState(() { _isSyncing = false; _currentSyncProgress = null; });
                }
              });
              return const SizedBox.shrink();
            }

            final isDownloading = progress?.isDownloading ?? false;
            final uploadPct = progress?.uploadPercent ?? 0.0;
            final downloadPct = progress?.downloadPercent ?? 0.0;
            final totalDown = progress?.totalDownload ?? 0;
            final baixados = progress?.downloadados ?? 0;
            final totalUp = progress?.totalAProcessar ?? 0;
            final enviados = progress?.processados ?? 0;

            return AlertDialog(
              title: Row(
                children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  const SizedBox(width: 12),
                  Text(isDownloading ? 'Baixando dados' : 'Enviando dados'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(progress?.mensagem ?? 'Iniciando...', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  if (!isDownloading && totalUp > 0) ...[
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Enviando', style: TextStyle(fontSize: 12)),
                      Text('$enviados / $totalUp  (${(uploadPct * 100).toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: uploadPct, minHeight: 8, borderRadius: BorderRadius.circular(4)),
                  ],
                  if (isDownloading) ...[
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Baixando', style: TextStyle(fontSize: 12)),
                      Text(totalDown > 0 ? '$baixados / $totalDown  (${(downloadPct * 100).toStringAsFixed(0)}%)' : 'calculando...', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: downloadPct, minHeight: 8, borderRadius: BorderRadius.circular(4)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    syncService.cancelarSincronizacao();
                    Navigator.of(dialogContext).pop();
                    if (mounted) {
                      setState(() { _isSyncing = false; _currentSyncProgress = null; });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sincronização cancelada'), backgroundColor: Colors.orange),
                      );
                    }
                  },
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );

    try {
      await syncService.sincronizarDados();
    } catch (e) {
      debugPrint("Erro grave na sincronização capturado na UI: $e");
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Widget _buildSyncProgressButton(Color primaryNavy, Color accentGold) {
    final p = _currentSyncProgress;
    final isDownloading = p?.isDownloading ?? false;
    final pct = isDownloading ? (p?.downloadPercent ?? 0.0) : (p?.uploadPercent ?? 0.0);
    final label = isDownloading
        ? (p != null && p.totalDownload > 0
            ? 'BAIXANDO ${p.downloadados}/${p.totalDownload} (${(pct * 100).toStringAsFixed(0)}%)'
            : 'BAIXANDO...')
        : (p != null && p.totalAProcessar > 0
            ? 'ENVIANDO ${p.processados}/${p.totalAProcessar} (${(pct * 100).toStringAsFixed(0)}%)'
            : 'SINCRONIZANDO...');

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 50,
              backgroundColor: accentGold.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(accentGold),
            ),
          ),
          Center(
            child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: Color(0xFF023853))),
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

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final List<Color> gradientColors = isDark 
        ? [const Color.fromARGB(255, 6, 140, 173), const Color.fromARGB(255, 1, 26, 39)] 
        : [const Color.fromARGB(255, 230, 230, 250), const Color.fromARGB(255, 255, 255, 255)];

    const Color primaryNavy = Color(0xFF023853);
    const Color accentGold = Color(0xFFEBE4AB);

    return Scaffold(
      extendBodyBehindAppBar: true, 
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: gradientColors,
            stops: const [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          top: false,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // 1. CABEÇALHO (Weather Header)
              const SliverToBoxAdapter(
                child: WeatherHeader(),
              ),

              // 2. TÍTULO DO MENU
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
                  child: Text(
                    "Menu Principal",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : primaryNavy,
                    ),
                  ),
                ),
              ),

              // 3. GRID DE MENU
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.85,
                  children: [
                    // ITEM 1: PROJETOS
                    ModernMenuTile(
                      title: 'Projetos e Coletas',
                      imagePath: 'assets/grid/folder.webp', 
                      onTap: () => context.push('/projetos'),
                    ),
                    // ITEM 2: PLANEJAMENTO
                    ModernMenuTile(
                      title: 'Navegação de Campo',
                      imagePath: 'assets/grid/way.webp', 
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const SelecaoAtividadeMapaPage()));
                      },
                    ),
                    // ITEM 3: ANALISTA
                    ModernMenuTile(
                      title: 'GeoForest Analista',
                      imagePath: 'assets/grid/analytics.webp', 
                      onTap: podeAnalisar
                          ? () => _abrirAnalistaDeDados(context)
                          : () => _mostrarAvisoDeUpgrade(context, "GeoForest Analista"),
                    ),
                    // ITEM 4: IMPORTAR
                    ModernMenuTile(
                      title: 'Importar Dados',
                      imagePath: 'assets/grid/download.webp', 
                      onTap: () => _mostrarDialogoImportacao(context),
                    ),
                    // ITEM 5: EXPORTAR
                    ModernMenuTile(
                      title: 'Exportar Dados',
                      imagePath: 'assets/grid/upload.webp', 
                      onTap: podeExportar
                          ? () => _mostrarDialogoExportacao(context)
                          : () => _mostrarAvisoDeUpgrade(context, "Exportar Dados"),
                    ),
                    // ITEM 6: CONFIGURAÇÕES
                    ModernMenuTile(
                      title: 'Configurações',
                      imagePath: 'assets/grid/service-tools.webp', 
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ConfiguracoesPage())),
                    ),
                  ],
                ),
              ),

              // 4. RODAPÉ (SYNC ISOLADO + ASSINATURA FORA)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                  child: Column(
                    children: [
                      // --- CARTÃO DE SINCRONIZAÇÃO (Agora menor e focado) ---
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF023853), Color(0xFF034C6E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF023853).withOpacity(0.4),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Ícone da Nuvem
                            Container(
                              width: 60,
                              height: 60,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  )
                                ],
                              ),
                              child: Image.asset(
                                'assets/grid/cloud.webp',
                                fit: BoxFit.contain,
                              ),
                            ),
                            
                            const SizedBox(height: 12),
                            
                            const Text(
                              "Status da Nuvem",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            
                            const SizedBox(height: 6),
                            
                            Text(
                              "Sincronize seus dados antes de sair.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 13,
                              ),
                            ),
                            
                            const SizedBox(height: 20),
                            
                            // BOTÃO SINCRONIZAR (Destaque Total)
                            if (_isSyncing)
                              _buildSyncProgressButton(primaryNavy, accentGold)
                            else
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: _executarSincronizacao,
                                  icon: const Icon(Icons.sync, size: 24),
                                  label: const Text(
                                    "SINCRONIZAR AGORA",
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accentGold,
                                    foregroundColor: primaryNavy,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // --- BOTÃO DE ASSINATURA (Fora do Card, no fundo da tela) ---
                      // Usamos um Container com borda sutil para ele não flutuar solto demais
                      Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark ? Colors.white24 : primaryNavy.withOpacity(0.2), 
                            width: 1.5
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: TextButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PaywallPage())),
                          icon: const Icon(Icons.workspace_premium, color: Color(0xFFFFD700), size: 22),
                          label: Text(
                            "Gerenciar Assinatura Premium",
                            style: TextStyle(
                              // Cor adapta ao tema (Branco no escuro, Azul no claro) para dar leitura no fundo
                              color: isDark ? Colors.white : primaryNavy, 
                              fontWeight: FontWeight.w700,
                              fontSize: 14
                            ),
                          ),
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Espaço final para garantir scroll
              const SliverToBoxAdapter(child: SizedBox(height: 30)),
            ],
          ),
        ),
      ),
    );
  }
}
// lib/pages/menu/home_page.dart (VERSÃO COM EXPORTAÇÃO SIMPLIFICADA)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Importações do Projeto
import 'package:geoforestv1/pages/analises/analise_selecao_page.dart';
import 'package:geoforestv1/pages/menu/configuracoes_page.dart';
import 'package:geoforestv1/pages/projetos/lista_projetos_page.dart';
import 'package:geoforestv1/pages/planejamento/selecao_atividade_mapa_page.dart';
import 'package:geoforestv1/pages/menu/paywall_page.dart';
import 'package:geoforestv1/providers/map_provider.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:geoforestv1/services/export_service.dart';
import 'package:geoforestv1/widgets/menu_card.dart';
import 'package:geoforestv1/services/sync_service.dart';

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

  Future<void> _executarSincronizacao() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Iniciando sincronização...'), duration: Duration(seconds: 15)),
    );
    try {
      final syncService = SyncService();
      await syncService.sincronizarDados();
      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dados sincronizados com sucesso!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro na sincronização: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }
  
  void _mostrarDialogoImportacao(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Wrap(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Text('Importar Dados para um Projeto', style: Theme.of(context).textTheme.titleLarge),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined, color: Colors.blue),
            title: const Text('Importar Arquivo CSV Universal'),
            subtitle: const Text('Selecione o projeto de destino para os dados.'),
            onTap: () {
              Navigator.of(ctx).pop();
              Navigator.push(context, MaterialPageRoute(
                builder: (context) => const ListaProjetosPage(
                  title: 'Importar para o Projeto...',
                  isImporting: true,
                ),
              ));
            },
          ),
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

  // <<< FUNÇÃO DE EXPORTAÇÃO REFINADA E SIMPLIFICADA >>>
  void _mostrarDialogoExportacao(BuildContext context) {
    // Instancia o serviço
    final exportService = ExportService();

    // Função auxiliar para evitar repetição de código ao perguntar o tipo de exportação
    void _mostrarDialogoTipo(BuildContext mainDialogContext, {required Function() onNovas, required Function() onTodas}) {
        showDialog(
            context: mainDialogContext,
            builder: (dialogCtx) => AlertDialog(
                title: const Text('Tipo de Exportação'),
                content: const Text('Deseja exportar apenas os dados novos ou um backup completo?'),
                actions: [
                    TextButton(
                        child: const Text('Apenas Novas'),
                        onPressed: () {
                            Navigator.of(dialogCtx).pop(); // Fecha o diálogo de alerta
                            onNovas(); // Executa a função para exportar novos dados
                        },
                    ),
                    ElevatedButton(
                        child: const Text('Todas (Backup)'),
                        onPressed: () {
                            Navigator.of(dialogCtx).pop(); // Fecha o diálogo de alerta
                            onTodas(); // Executa a função para exportar todos os dados
                        },
                    ),
                ],
            ),
        );
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Wrap(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Text('Opções de Exportação',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          ListTile(
            leading: const Icon(Icons.table_rows_outlined, color: Colors.green),
            title: const Text('Coletas de Parcela (CSV)'),
            onTap: () {
              Navigator.of(ctx).pop(); // Fecha o BottomSheet
              // Chama a função auxiliar passando os métodos corretos do serviço
              _mostrarDialogoTipo(
                  context,
                  onNovas: () => exportService.exportarDados(context),
                  onTodas: () => exportService.exportarTodasAsParcelasBackup(context),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined, color: Colors.brown),
            title: const Text('Cubagens Rigorosas (CSV)'),
            onTap: () {
              Navigator.of(ctx).pop(); // Fecha o BottomSheet
              _mostrarDialogoTipo(
                  context,
                  onNovas: () => exportService.exportarNovasCubagens(context),
                  onTodas: () => exportService.exportarTodasCubagensBackup(context),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.map_outlined, color: Colors.purple),
            title: const Text('Plano de Amostragem (GeoJSON)'),
            onTap: () {
              Navigator.of(ctx).pop();
              context.read<MapProvider>().exportarPlanoDeAmostragem(context);
            },
          ),
        ],
      ),
    );
  }

  void _mostrarAvisoDeUpgrade(BuildContext context, String featureName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Funcionalidade indisponível"),
        content: Text("A função '$featureName' não está disponível no seu plano atual. Faça upgrade para desbloqueá-la."),
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
    final bool podeExportar = licenseProvider.licenseData?.features['exportacao'] ?? true; // Default true para teste
    final bool podeAnalisar = licenseProvider.licenseData?.features['analise'] ?? true; // Default true para teste

    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: Text(widget.title)) : null,
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12.0,
          mainAxisSpacing: 12.0,
          childAspectRatio: 1.0,
          children: [
            MenuCard(
              icon: Icons.folder_copy_outlined,
              label: 'Projetos e Coletas',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ListaProjetosPage(title: 'Meus Projetos'),
                ),
              ),
            ),
            MenuCard(
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
    );
  }
}
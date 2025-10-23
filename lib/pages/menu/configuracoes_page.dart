// lib/pages/menu/configuracoes_page.dart (VERSÃO AJUSTADA)

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/controller/login_controller.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoforestv1/services/licensing_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geoforestv1/pages/projetos/gerenciar_delegacoes_page.dart';
import 'package:geoforestv1/providers/theme_provider.dart';
import 'package:geoforestv1/pages/gerente/gerenciar_equipe_page.dart';
import 'package:geoforestv1/pages/menu/relatorio_diario_page.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/utils/constants.dart';

// Imports para novas funcionalidades
import 'package:geoforestv1/services/validation_service.dart';
import 'package:geoforestv1/pages/menu/consistencia_resultado_page.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/widgets/progress_dialog.dart';

// <<< Import da nova página de histórico >>>
import 'package:geoforestv1/pages/menu/historico_diarios_page.dart';

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  String? _zonaSelecionada;

  final _parcelaRepository = ParcelaRepository();
  final _cubagemRepository = CubagemRepository();
  final _licensingService = LicensingService();
  final _validationService = ValidationService();

  Map<String, int>? _deviceUsage;
  bool _isLoadingLicense = true;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
    _fetchDeviceUsage();
  }

  Future<void> _carregarConfiguracoes() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _zonaSelecionada = prefs.getString('zona_utm_selecionada') ?? 'SIRGAS 2000 / UTM Zona 22S';
      });
    }
  }

  Future<void> _salvarConfiguracoes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zona_utm_selecionada', _zonaSelecionada!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurações salvas!'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _fetchDeviceUsage() async {
    try {
      final usage = await _licensingService.getDeviceUsage();
      if (mounted) {
        setState(() {
          _deviceUsage = usage;
          _isLoadingLicense = false;
        });
      }
    } catch (e) {
      print("Erro ao buscar uso de dispositivos: $e");
      if (mounted) {
        setState(() {
          _isLoadingLicense = false;
          _deviceUsage = null;
        });
      }
    }
  }

  Future<void> _mostrarDialogoLimpeza({
    required String titulo,
    required String conteudo,
    required VoidCallback onConfirmar,
    bool isDestructive = true,
  }) async {
    final bool? confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(conteudo),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: isDestructive ? Colors.red : Theme.of(context).primaryColor,
            ),
            child: Text(isDestructive ? 'CONFIRMAR' : 'SAIR'),
          ),
        ],
      ),
    );

    if (confirmado == true && mounted) {
      onConfirmar();
    }
  }

  Future<void> _handleLogout() async {
    await _mostrarDialogoLimpeza(
      titulo: 'Confirmar Saída',
      conteudo: 'Tem certeza de que deseja sair da sua conta?',
      isDestructive: false,
      onConfirmar: () async {
        await context.read<LoginController>().signOut();
      },
    );
  }

  Future<void> _diagnosticarPermissoes() async {
    final statusStorage = await Permission.storage.status;
    debugPrint("DEBUG: Status da permissão [storage]: $statusStorage");
    final statusManage = await Permission.manageExternalStorage.status;
    debugPrint("DEBUG: Status da permissão [manageExternalStorage]: $statusManage");
    final statusMedia = await Permission.accessMediaLocation.status;
    debugPrint("DEBUG: Status da permissão [accessMediaLocation]: $statusMedia");
    await openAppSettings();
  }

  Future<void> _verificarConsistencia() async {
    if (!mounted) return;
    ProgressDialog.show(context, 'Verificando consistência dos dados...');

    try {
      final List<Parcela> parcelasConcluidas = await _parcelaRepository.getTodasAsParcelas()
          .then((list) => list.where((p) => p.status == StatusParcela.concluida || p.status == StatusParcela.exportada).toList());

      final List<CubagemArvore> cubagensConcluidas = await _cubagemRepository.getTodasCubagens()
          .then((list) => list.where((c) => c.alturaTotal > 0).toList());

      final report = await _validationService.performFullConsistencyCheck(
        parcelas: parcelasConcluidas,
        cubagens: cubagensConcluidas,
        parcelaRepo: _parcelaRepository,
        cubagemRepo: _cubagemRepository,
      );

      if (!mounted) return;
      ProgressDialog.hide(context);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ConsistenciaResultadoPage(
            report: report,
            parcelasVerificadas: parcelasConcluidas,
          ),
        ),
      );

    } catch (e) {
      if (!mounted) return;
      ProgressDialog.hide(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao verificar consistência: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final licenseProvider = context.watch<LicenseProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final isGerente = licenseProvider.licenseData?.cargo == 'gerente';

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações e Gerenciamento')),
      body: _zonaSelecionada == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Conta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 2,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: _isLoadingLicense
                              ? const Center(child: CircularProgressIndicator())
                              : _deviceUsage == null
                                  ? const Text('Não foi possível carregar os dados da licença.')
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Usuário: ${FirebaseAuth.instance.currentUser?.email ?? 'Desconhecido'}'),
                                        const SizedBox(height: 12),
                                        const Text('Dispositivos Registrados:', style: TextStyle(fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        Text(' • Smartphones: ${_deviceUsage!['smartphone']}'),
                                        Text(' • Desktops: ${_deviceUsage!['desktop']}'),
                                      ],
                                    ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.logout, color: Colors.red),
                          title: const Text('Sair da Conta', style: TextStyle(color: Colors.red)),
                          onTap: _handleLogout,
                        ),
                      ],
                    ),
                  ),
                  const Divider(thickness: 1, height: 48),
                  const Text('Aparência', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const <ButtonSegment<ThemeMode>>[
                      ButtonSegment<ThemeMode>(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode_outlined)),
                      ButtonSegment<ThemeMode>(value: ThemeMode.system, label: Text('Sistema'), icon: Icon(Icons.brightness_auto_outlined)),
                      ButtonSegment<ThemeMode>(value: ThemeMode.dark, label: Text('Escuro'), icon: Icon(Icons.dark_mode_outlined)),
                    ],
                    selected: <ThemeMode>{themeProvider.themeMode},
                    onSelectionChanged: (Set<ThemeMode> newSelection) {
                      context.read<ThemeProvider>().setThemeMode(newSelection.first);
                    },
                  ),
                  const Divider(thickness: 1, height: 48),
                  const Text('Zona UTM de Exportação', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Text('Define o sistema de coordenadas para os arquivos CSV.', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    value: _zonaSelecionada,
                    isExpanded: true,
                    items: zonasUtmSirgas2000.keys.map((String zona) => DropdownMenuItem<String>(value: zona, child: Text(zona, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (String? novoValor) => setState(() => _zonaSelecionada = novoValor),
                    decoration: const InputDecoration(labelText: 'Sistema de Coordenadas', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Salvar Configuração da Zona'),
                      onPressed: _salvarConfiguracoes,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),
                  const Divider(thickness: 1, height: 48),
                  const Text('Gerenciamento de Dados', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  const SizedBox(height: 12),
                  
                  ListTile(
                    leading: const Icon(Icons.today_outlined, color: Colors.blueGrey),
                    title: const Text('Gerar Relatório Diário da Equipe'),
                    subtitle: const Text('Visualize e exporte as coletas de um dia específico.'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RelatorioDiarioPage()),
                      );
                    },
                  ),
                  
                  // <<< INSERÇÃO DA NOVA OPÇÃO DE MENU >>>
                  ListTile(
                    leading: const Icon(Icons.history_outlined, color: Colors.blueGrey),
                    title: const Text('Histórico de Diários de Campo'),
                    subtitle: const Text('Visualize ou apague relatórios já salvos.'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const HistoricoDiariosPage()),
                      );
                    },
                  ),
                  // <<< FIM DA INSERÇÃO >>>

                  ListTile(
                    leading: const Icon(Icons.rule_folder_outlined, color: Colors.indigo),
                    title: const Text('Verificar Consistência dos Dados'),
                    subtitle: const Text('Busca por erros de sequência, outliers e afilamento.'),
                    onTap: _verificarConsistencia,
                  ),

                  if (isGerente)
                    ListTile(
                      leading: const Icon(Icons.handshake_outlined, color: Colors.teal),
                      title: const Text('Gerenciar Delegações'),
                      subtitle: const Text('Veja o status e gerencie os projetos compartilhados.'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const GerenciarDelegacoesPage()),
                        );
                      },
                    ),
                  if (isGerente)
                    ListTile(
                      leading: const Icon(Icons.groups_outlined, color: Colors.blueAccent),
                      title: const Text('Gerenciar Equipe'),
                      subtitle: const Text('Adicione ou remova membros da equipe.'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const GerenciarEquipePage()),
                        );
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: const Text('Arquivar Coletas Exportadas'),
                    subtitle: const Text('Apaga do dispositivo apenas as coletas (parcelas e cubagens) que já foram exportadas.'),
                    onTap: () => _mostrarDialogoLimpeza(
                      titulo: 'Arquivar Coletas',
                      conteudo: 'Isso removerá do dispositivo todas as coletas (parcelas e cubagens) já marcadas como exportadas. Deseja continuar?',
                      onConfirmar: () async {
                        final parcelasCount = await _parcelaRepository.limparParcelasExportadas();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$parcelasCount parcelas arquivadas.')));
                      },
                    ),
                  ),
                  const Divider(thickness: 1, height: 24),
                  const Text('Ações Perigosas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
                    title: const Text('Limpar TODAS as Coletas de Parcela'),
                    subtitle: const Text('Apaga TODAS as parcelas e árvores salvas.'),
                    onTap: () => _mostrarDialogoLimpeza(
                      titulo: 'Limpar Todas as Parcelas',
                      conteudo: 'Tem certeza? TODOS os dados de parcelas e árvores serão apagados permanentemente.',
                      onConfirmar: () async {
                        await _parcelaRepository.limparTodasAsParcelas();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Todas as parcelas foram apagadas!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
                      },
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
                    title: const Text('Limpar TODOS os Dados de Cubagem'),
                    subtitle: const Text('Apaga TODOS os dados de cubagem salvos.'),
                    onTap: () => _mostrarDialogoLimpeza(
                      titulo: 'Limpar Todas as Cubagens',
                      conteudo: 'Tem certeza? TODOS os dados de cubagem serão apagados permanentemente.',
                      onConfirmar: () async {
                        await _cubagemRepository.limparTodasAsCubagens();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Todos os dados de cubagem foram apagados!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
                      },
                    ),
                  ),
                  const Divider(thickness: 1, height: 48),
                  Center(
                    child: ElevatedButton(
                      onPressed: _diagnosticarPermissoes,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                      child: const Text('Debug de Permissões', style: TextStyle(color: Colors.black)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}
// lib/pages/menu/configuracoes_page.dart (VERSÃO COM LINK PARA GERENCIAR DELEGAÇÕES)

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/controller/login_controller.dart';
import 'package:geoforestv1/pages/menu/login_page.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/services/licensing_service.dart';
import 'package:permission_handler/permission_handler.dart';

// <<< MUDANÇA 1: Import da nova tela de gerenciamento de delegações >>>
import 'package:geoforestv1/pages/projetos/gerenciar_delegacoes_page.dart';


const Map<String, int> zonasUtmSirgas2000 = {
  'SIRGAS 2000 / UTM Zona 18S': 31978, 'SIRGAS 2000 / UTM Zona 19S': 31979,
  'SIRGAS 2000 / UTM Zona 20S': 31980, 'SIRGAS 2000 / UTM Zona 21S': 31981,
  'SIRGAS 2000 / UTM Zona 22S': 31982, 'SIRGAS 2000 / UTM Zona 23S': 31983,
  'SIRGAS 2000 / UTM Zona 24S': 31984, 'SIRGAS 2000 / UTM Zona 25S': 31985,
};

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  String? _zonaSelecionada;
  final dbHelper = DatabaseHelper.instance;
  
  final LicensingService _licensingService = LicensingService();
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
      if(mounted) {
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
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (Route<dynamic> route) => false,
          );
        }
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

  @override
  Widget build(BuildContext context) {
    // <<< MUDANÇA 2: Verificando o cargo do usuário para mostrar o botão condicionalmente >>>
    final licenseProvider = context.watch<LicenseProvider>();
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
                  
                  // <<< MUDANÇA 3: O novo ListTile/Botão que só aparece para o gerente >>>
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

                  ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: const Text('Arquivar Coletas Exportadas'),
                    subtitle: const Text('Apaga do dispositivo apenas as coletas (parcelas e cubagens) que já foram exportadas.'),
                    onTap: () => _mostrarDialogoLimpeza(
                      titulo: 'Arquivar Coletas',
                      conteudo: 'Isso removerá do dispositivo todas as coletas (parcelas e cubagens) já marcadas como exportadas. Deseja continuar?',
                      onConfirmar: () async {
                        final parcelasCount = await dbHelper.limparParcelasExportadas();
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
                        await dbHelper.limparTodasAsParcelas();
                        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Todas as parcelas foram apagadas!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
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
                        await dbHelper.limparTodasAsCubagens();
                        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Todos os dados de cubagem foram apagados!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
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
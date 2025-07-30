// lib/pages/planejamento/selecao_atividade_mapa_page.dart (VERSÃO AJUSTADA E COMPLETA)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Imports do projeto (verifique se todos estão corretos)
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/pages/menu/map_import_page.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:geoforestv1/providers/map_provider.dart';

class SelecaoAtividadeMapaPage extends StatefulWidget {
  const SelecaoAtividadeMapaPage({super.key});

  @override
  State<SelecaoAtividadeMapaPage> createState() => _SelecaoAtividadeMapaPageState();
}

class _SelecaoAtividadeMapaPageState extends State<SelecaoAtividadeMapaPage> {
  final dbHelper = DatabaseHelper.instance;
  // A variável não é mais 'late' pois será inicializada após o build inicial
  Future<List<Projeto>>? _projetosFuture; 
  final Map<int, List<Atividade>> _atividadesPorProjeto = {};
  bool _isLoadingAtividades = false;

  @override
  void initState() {
    super.initState();
    // Chamamos a função para carregar os projetos de forma segura,
    // garantindo que o 'context' do Provider esteja disponível.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _carregarProjetos();
    });
  }

  // Esta nova função é responsável por buscar os projetos de forma segura
  Future<void> _carregarProjetos() async {
    // Usamos o Provider para descobrir qual licença está ativa
    final licenseProvider = context.read<LicenseProvider>();
    
    // Verificação de segurança: se não houver dados da licença, não fazemos nada
    if (licenseProvider.licenseData == null) {
      // Você pode mostrar uma mensagem de erro aqui se desejar
      if (mounted) {
        setState(() {
          _projetosFuture = Future.value([]); // Retorna uma lista vazia
        });
      }
      return;
    }

    // Pegamos o ID da licença do usuário logado
    // (Isso depende do ajuste no LicenseProvider que discutimos)
    final licenseId = licenseProvider.licenseData!.id; 

    // Atualizamos o estado da tela com a chamada correta ao banco de dados
    if (mounted) {
      setState(() {
        // Chamamos a nova função 'getProjetos' passando o filtro 'licenseId'
        _projetosFuture = dbHelper.getTodosProjetos(licenseId);
      });
    }
  }

  // NENHUMA MUDANÇA NECESSÁRIA A PARTIR DAQUI.
  // As funções abaixo já estavam corretas e continuam funcionando.

  Future<void> _carregarAtividadesDoProjeto(int projetoId) async {
    if (_atividadesPorProjeto.containsKey(projetoId)) return;

    setState(() => _isLoadingAtividades = true);
    final atividades = await dbHelper.getAtividadesDoProjeto(projetoId);
    if (mounted) {
      setState(() {
        _atividadesPorProjeto[projetoId] = atividades;
        _isLoadingAtividades = false;
      });
    }
  }

  void _navegarParaMapa(Atividade atividade) {
    final mapProvider = Provider.of<MapProvider>(context, listen: false);

    // 1. Limpa qualquer estado antigo do mapa.
    mapProvider.clearAllMapData();
    // 2. Define a atividade atual no provider.
    mapProvider.setCurrentAtividade(atividade);
    // 3. Carrega as amostras existentes para essa atividade, se houver.
    mapProvider.loadSamplesParaAtividade();

    // 4. Navega para a página do mapa.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MapImportPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Selecionar Atividade'),
      ),
      body: FutureBuilder<List<Projeto>>(
        future: _projetosFuture, // Agora usa a variável de estado correta
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _projetosFuture == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          final projetos = snapshot.data ?? [];
          if (projetos.isEmpty && snapshot.connectionState == ConnectionState.done) {
            return const Center(child: Text('Nenhum projeto encontrado para esta licença.'));
          }

          return ListView.builder(
            itemCount: projetos.length,
            itemBuilder: (context, index) {
              final projeto = projetos[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ExpansionTile(
                  title: Text(projeto.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                  onExpansionChanged: (isExpanding) {
                    if (isExpanding) {
                      _carregarAtividadesDoProjeto(projeto.id!);
                    }
                  },
                  children: [
                    if (_isLoadingAtividades && !_atividadesPorProjeto.containsKey(projeto.id))
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_atividadesPorProjeto[projeto.id]?.isEmpty ?? true)
                      const ListTile(title: Text('Nenhuma atividade neste projeto.'))
                    else
                      ..._atividadesPorProjeto[projeto.id]!.map((atividade) {
                        return ListTile(
                          title: Text(atividade.tipo),
                          subtitle: Text(atividade.descricao.isNotEmpty ? atividade.descricao : 'Sem descrição'),
                          leading: const Icon(Icons.arrow_right),
                          onTap: () => _navegarParaMapa(atividade),
                          trailing: const Icon(Icons.map_outlined, color: Colors.grey),
                        );
                      }).toList()
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
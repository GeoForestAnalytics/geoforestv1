// lib/pages/planejamento/selecao_atividade_mapa_page.dart (VERSÃO COMPLETA E REFATORADA)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// --- NOVOS IMPORTS DOS REPOSITÓRIOS E MODELS ---
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
// ---------------------------------------------

import 'package:geoforestv1/pages/menu/map_import_page.dart';
import 'package:geoforestv1/providers/map_provider.dart';

// O import do database_helper foi removido.
// import 'package:geoforestv1/data/datasources/local/database_helper.dart';

class SelecaoAtividadeMapaPage extends StatefulWidget {
  const SelecaoAtividadeMapaPage({super.key});

  @override
  State<SelecaoAtividadeMapaPage> createState() => _SelecaoAtividadeMapaPageState();
}

class _SelecaoAtividadeMapaPageState extends State<SelecaoAtividadeMapaPage> {
  // --- INSTÂNCIAS DOS NOVOS REPOSITÓRIOS ---
  final _projetoRepository = ProjetoRepository();
  final _atividadeRepository = AtividadeRepository();
  // ---------------------------------------

  Future<List<Projeto>>? _projetosFuture; 
  final Map<int, List<Atividade>> _atividadesPorProjeto = {};
  bool _isLoadingAtividades = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _carregarProjetos();
    });
  }

  // --- MÉTODO ATUALIZADO ---
  Future<void> _carregarProjetos() async {
    // A lógica do LicenseProvider foi removida pois o repositório já lida com isso
    // de forma mais genérica para o gerente.

    if (mounted) {
      setState(() {
        // <<< CORREÇÃO AQUI >>>
        // Trocamos 'getTodosProjetos' por 'getTodosOsProjetosParaGerente'.
        // Esta função busca TODOS os projetos visíveis para o usuário (próprios e delegados),
        // sem filtrar pela licenseId do usuário logado.
        _projetosFuture = _projetoRepository.getTodosOsProjetosParaGerente();
      });
    }
  }

  // --- MÉTODO ATUALIZADO ---
  Future<void> _carregarAtividadesDoProjeto(int projetoId) async {
    if (_atividadesPorProjeto.containsKey(projetoId)) return;

    setState(() => _isLoadingAtividades = true);
    // Usa o AtividadeRepository
    final atividades = await _atividadeRepository.getAtividadesDoProjeto(projetoId);
    if (mounted) {
      setState(() {
        _atividadesPorProjeto[projetoId] = atividades;
        _isLoadingAtividades = false;
      });
    }
  }

  // O restante dos métodos (navegação, build) não precisa de alterações.

  void _navegarParaMapa(Atividade atividade) {
    final mapProvider = Provider.of<MapProvider>(context, listen: false);

    mapProvider.clearAllMapData();
    mapProvider.setCurrentAtividade(atividade);
    mapProvider.loadSamplesParaAtividade();

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
        future: _projetosFuture,
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
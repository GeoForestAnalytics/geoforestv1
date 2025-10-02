// lib/pages/projetos/detalhes_projeto_page.dart (VERSÃO ATUALIZADA PARA GO_ROUTER)

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart'; // ✅ 1. IMPORTAR GO_ROUTER
import 'package:intl/intl.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/pages/atividades/form_atividade_page.dart';
// import 'package:geoforestv1/pages/atividades/detalhes_atividade_page.dart'; // Removido, usaremos go_router
import 'package:geoforestv1/utils/navigation_helper.dart';

import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/services/pdf_service.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart'; // ✅ 2. IMPORTAR REPOSITÓRIO DO PROJETO

class DetalhesProjetoPage extends StatefulWidget {
  // ✅ 3. CONSTRUTOR MODIFICADO
  // Agora recebe apenas o ID do projeto.
  final int projetoId;
  const DetalhesProjetoPage({super.key, required this.projetoId});

  @override
  State<DetalhesProjetoPage> createState() => _DetalhesProjetoPageState();
}

class _DetalhesProjetoPageState extends State<DetalhesProjetoPage> {
  final _atividadeRepository = AtividadeRepository();
  final _pdfService = PdfService();
  final _cubagemRepository = CubagemRepository();
  final _projetoRepository = ProjetoRepository(); // ✅ 4. INSTANCIAR REPOSITÓRIO

  // ✅ 5. ESTADO PARA ARMAZENAR OS DADOS
  // Usaremos um Future para carregar os dados do projeto e das atividades.
  late Future<Projeto?> _projetoFuture;
  late Future<List<Atividade>> _atividadesFuture;

  // Variáveis para o estado da seleção
  bool _isSelectionMode = false;
  final Set<int> _selectedAtividades = {};

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  // ✅ 6. MÉTODO PARA CARREGAR TODOS OS DADOS DA PÁGINA
  void _loadAllData() {
    setState(() {
      _isSelectionMode = false;
      _selectedAtividades.clear();
      // Inicia a busca pelo projeto usando o ID do widget
      _projetoFuture = _projetoRepository.getProjetoById(widget.projetoId);
      // Inicia a busca pelas atividades usando o ID do widget
      _atividadesFuture = _atividadeRepository.getAtividadesDoProjeto(widget.projetoId);
    });
  }
  
  // As lógicas de _navegarParaEdicao, _toggleSelectionMode, _onItemSelected, 
  // e _deleteSelectedAtividades permanecem praticamente as mesmas,
  // apenas precisam garantir que têm acesso ao projetoId.

  void _navegarParaEdicao(Atividade atividade) async {
    // A navegação para edição ainda usa MaterialPageRoute pois é um formulário modal
    final bool? atividadeEditada = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FormAtividadePage(
          projetoId: atividade.projetoId,
          atividadeParaEditar: atividade,
        ),
      ),
    );
    if (atividadeEditada == true && mounted) {
      _loadAllData();
    }
  }

  void _toggleSelectionMode(int? atividadeId) {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedAtividades.clear();
      if (_isSelectionMode && atividadeId != null) {
        _selectedAtividades.add(atividadeId);
      }
    });
  }

  void _onItemSelected(int atividadeId) {
    setState(() {
      if (_selectedAtividades.contains(atividadeId)) {
        _selectedAtividades.remove(atividadeId);
        if (_selectedAtividades.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedAtividades.add(atividadeId);
      }
    });
  }

  Future<void> _deleteSelectedAtividades() async {
    if (_selectedAtividades.isEmpty) return;

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text('Tem certeza que deseja apagar as ${_selectedAtividades.length} atividades selecionadas e todos os seus dados?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    
    if (confirmar == true && mounted) {
      for (final id in _selectedAtividades) {
        await _atividadeRepository.deleteAtividade(id);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_selectedAtividades.length} atividades apagadas.'), backgroundColor: Colors.green),
      );
      _loadAllData();
    }
  }
  
  void _navegarParaNovaAtividade() async {
    final bool? atividadeCriada = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FormAtividadePage(projetoId: widget.projetoId),
      ),
    );
    if (atividadeCriada == true && mounted) {
      _loadAllData();
    }
  }

  // ✅ 7. NAVEGAÇÃO ATUALIZADA
  // Não precisa mais passar o objeto 'atividade', pois a próxima página buscará seus dados.
   // ✅ NAVEGAÇÃO CORRIGIDA PARA USAR GO_ROUTER
  void _navegarParaDetalhesAtividade(Atividade atividade) {
  // CORRETO
  context.push('/projetos/${widget.projetoId}/atividades/${atividade.id}');
}

  AppBar _buildSelectionAppBar() {
    return AppBar(
      title: Text('${_selectedAtividades.length} selecionada(s)'),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => _toggleSelectionMode(null),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Apagar selecionadas',
          onPressed: _deleteSelectedAtividades,
        ),
      ],
    );
  }

  AppBar _buildNormalAppBar(String projetoNome) {
    return AppBar(
      title: Text(projetoNome),
      actions: [
        IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: 'Voltar para o Início',
          onPressed: () => NavigationHelper.goBackToHome(context),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 8. USO DO FUTUREBUILDER
    // O widget principal agora é um FutureBuilder que espera os dados do projeto.
    return FutureBuilder<Projeto?>(
      future: _projetoFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Erro')),
            body: Center(child: Text('Erro ao carregar projeto: ${snapshot.error ?? "Projeto não encontrado."}')),
          );
        }

        final projeto = snapshot.data!;

        // Uma vez que o projeto carregou, construímos a tela normalmente.
        return Scaffold(
          appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(projeto.nome),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Card com os detalhes do projeto
              Card(
                margin: const EdgeInsets.all(12.0),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Detalhes do Projeto', style: Theme.of(context).textTheme.titleLarge),
                      const Divider(height: 20),
                      Text("Empresa: ${projeto.empresa}", style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 8),
                      Text("Responsável: ${projeto.responsavel}", style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 8),
                      Text('Data de Criação: ${DateFormat('dd/MM/yyyy').format(projeto.dataCriacao)}', style: Theme.of(context).textTheme.bodyLarge),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
                child: Text(
                  "Atividades do Projeto",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              // Lista de atividades (que também usa um FutureBuilder)
              Expanded(
                child: FutureBuilder<List<Atividade>>(
                  future: _atividadesFuture,
                  builder: (context, atividadesSnapshot) {
                    if (atividadesSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (atividadesSnapshot.hasError) {
                      return Center(child: Text('Erro ao carregar atividades: ${atividadesSnapshot.error}'));
                    }

                    final atividades = atividadesSnapshot.data ?? [];

                    if (atividades.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Nenhuma atividade encontrada.\nClique no botão "+" para adicionar a primeira.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: atividades.length,
                      itemBuilder: (context, index) {
                        final atividade = atividades[index];
                        final isSelected = _selectedAtividades.contains(atividade.id!);
                        final isCubagem = atividade.tipo.toLowerCase().contains('cubagem');

                        return Slidable(
                          key: ValueKey(atividade.id),
                          startActionPane: ActionPane(
                            motion: const DrawerMotion(),
                            extentRatio: isCubagem ? 0.50 : 0.25,
                            children: [
                              SlidableAction(
                                onPressed: (_) => _navegarParaEdicao(atividade),
                                backgroundColor: Colors.blue.shade700,
                                foregroundColor: Colors.white,
                                icon: Icons.edit_outlined,
                                label: 'Editar',
                              ),
                              if (isCubagem)
                                SlidableAction(
                                  onPressed: (_) async {
                                    final placeholders = await _cubagemRepository.getPlanoDeCubagemPorAtividade(atividade.id!);
                                    if (placeholders.isEmpty && mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum plano de cubagem encontrado.')));
                                      return;
                                    }
                                    await _pdfService.gerarPdfDePlanoExistente(
                                      context: context, 
                                      atividade: atividade, 
                                      placeholders: placeholders
                                    );
                                  },
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                  icon: Icons.picture_as_pdf_outlined,
                                  label: 'PDF Plano',
                                ),
                            ],
                          ),
                          child: Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5) : null,
                            child: ListTile(
                              onTap: () {
                                if (_isSelectionMode) {
                                  _onItemSelected(atividade.id!);
                                } else {
                                  _navegarParaDetalhesAtividade(atividade);
                                }
                              },
                              onLongPress: () {
                                if (!_isSelectionMode) {
                                  _toggleSelectionMode(atividade.id!);
                                }
                              },
                              leading: CircleAvatar(
                                backgroundColor: isSelected ? Theme.of(context).colorScheme.primary : null,
                                child: Icon(isSelected ? Icons.check : _getIconForAtividade(atividade.tipo)),
                              ),
                              title: Text(atividade.tipo, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(atividade.descricao.isNotEmpty ? atividade.descricao : 'Sem descrição'),
                              trailing: _isSelectionMode
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: () async {
                                        _toggleSelectionMode(atividade.id!);
                                        await _deleteSelectedAtividades();
                                      },
                                    ),
                              selected: isSelected,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          floatingActionButton: _isSelectionMode
              ? null
              : FloatingActionButton.extended(
                  onPressed: _navegarParaNovaAtividade,
                  tooltip: 'Nova Atividade',
                  icon: const Icon(Icons.add_task),
                  label: const Text('Nova Atividade'),
                ),
        );
      },
    );
  }

  IconData _getIconForAtividade(String tipo) {
    if (tipo.toLowerCase().contains('inventário')) return Icons.forest;
    if (tipo.toLowerCase().contains('cubagem')) return Icons.architecture;
    if (tipo.toLowerCase().contains('manutenção')) return Icons.build;
    return Icons.assignment;
  }
}
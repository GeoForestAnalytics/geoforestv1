// lib/pages/atividades/detalhes_atividade_page.dart (VERSÃO ATUALIZADA PARA GO_ROUTER)

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:go_router/go_router.dart'; // ✅ IMPORT ADICIONADO
import 'package:intl/intl.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/pages/fazenda/form_fazenda_page.dart';
import 'package:geoforestv1/utils/navigation_helper.dart';
import 'package:geoforestv1/data/repositories/fazenda_repository.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart'; // ✅ IMPORT ADICIONADO

class DetalhesAtividadePage extends StatefulWidget {
  // ✅ CONSTRUTOR MODIFICADO
  final int atividadeId;
  
  const DetalhesAtividadePage({super.key, required this.atividadeId});

  @override
  State<DetalhesAtividadePage> createState() => _DetalhesAtividadePageState();
}

class _DetalhesAtividadePageState extends State<DetalhesAtividadePage> {
  final _fazendaRepository = FazendaRepository();
  final _atividadeRepository = AtividadeRepository(); // ✅ INSTÂNCIA ADICIONADA

  // ✅ ESTADO MODIFICADO PARA USAR FUTURES
  late Future<Atividade?> _atividadeFuture;
  late Future<List<Fazenda>> _fazendasFuture;
  
  bool _isSelectionMode = false;
  final Set<String> _selectedFazendas = {};

  // Funções `get` para facilitar a leitura do tipo de atividade após o carregamento
  bool _isAtividadeDeInventario(Atividade? atividade) {
    if (atividade == null) return false;
    final tipo = atividade.tipo.toUpperCase();
    return tipo.contains("IPC") || tipo.contains("IFC") || tipo.contains("IFS") || tipo.contains("BIO") || tipo.contains("IFQ");
  }

  bool _isAtividadeDeCubagem(Atividade? atividade) {
    if (atividade == null) return false;
    final tipo = atividade.tipo.toUpperCase();
    return tipo.contains("CUB");
  }

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }
  
  // ✅ MÉTODO DE CARREGAMENTO ATUALIZADO
  void _carregarDados() {
    if (mounted) {
      setState(() {
        _isSelectionMode = false;
        _selectedFazendas.clear();
        _atividadeFuture = _atividadeRepository.getAtividadeById(widget.atividadeId); // Busca a atividade pelo ID
        _fazendasFuture = _fazendaRepository.getFazendasDaAtividade(widget.atividadeId);
      });
    }
  }

  void _navegarParaNovaFazenda() async {
    final bool? fazendaCriada = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FormFazendaPage(atividadeId: widget.atividadeId),
      ),
    );
    if (fazendaCriada == true && mounted) {
      _carregarDados();
    }
  }
  
  void _toggleSelectionMode(String? fazendaId) {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedFazendas.clear();
      if (_isSelectionMode && fazendaId != null) {
        _selectedFazendas.add(fazendaId);
      }
    });
  }

  void _onItemSelected(String fazendaId) {
    setState(() {
      if (_selectedFazendas.contains(fazendaId)) {
        _selectedFazendas.remove(fazendaId);
        if (_selectedFazendas.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedFazendas.add(fazendaId);
      }
    });
  }
  
  Future<void> _deleteFazenda(Fazenda fazenda) async {
     final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text('Tem certeza que deseja apagar a fazenda "${fazenda.nome}" e todos os seus dados?'),
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
      await _fazendaRepository.deleteFazenda(fazenda.id, fazenda.atividadeId);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Fazenda apagada.'),
          backgroundColor: Colors.red));
      _carregarDados();
    }
  }

  void _navegarParaEdicaoFazenda(Fazenda fazenda) async {
    final bool? fazendaEditada = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FormFazendaPage(
          atividadeId: fazenda.atividadeId,
          fazendaParaEditar: fazenda,
        ),
      ),
    );
    if (fazendaEditada == true && mounted) {
      _carregarDados();
    }
  }

  // ✅ NAVEGAÇÃO ATUALIZADA (ASSUMINDO QUE A ROTA SERÁ CRIADA)
  void _navegarParaDetalhesFazenda(Fazenda fazenda, Atividade atividade) {
    // Constrói a rota hierárquica completa usando os IDs necessários
    context.go('/projetos/${atividade.projetoId}/atividades/${atividade.id}/fazendas/${fazenda.id}');
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      title: Text('${_selectedFazendas.length} selecionada(s)'),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => _toggleSelectionMode(null),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Apagar selecionadas',
          onPressed: () { 
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use o deslize para apagar individualmente.')));
           },
        ),
      ],
    );
  }
  
  AppBar _buildNormalAppBar(Atividade? atividade) {
    return AppBar(
      title: Text(atividade?.tipo ?? 'Carregando...'),
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
    // ✅ USO DO FUTUREBUILDER PARA CARREGAR OS DADOS DA ATIVIDADE
    return FutureBuilder<Atividade?>(
      future: _atividadeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return Scaffold(appBar: AppBar(title: const Text('Erro')), body: Center(child: Text('Erro ao carregar atividade: ${snapshot.error ?? "Atividade não encontrada"}')));
        }
        
        final atividade = snapshot.data!;

        return Scaffold(
          appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(atividade),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                margin: const EdgeInsets.all(12.0),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Detalhes da Atividade', style: Theme.of(context).textTheme.titleLarge),
                      const Divider(height: 20),
                      Text("Descrição: ${atividade.descricao.isNotEmpty ? atividade.descricao : 'N/A'}",
                          style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 8),
                      Text('Data de Criação: ${DateFormat('dd/MM/yyyy').format(atividade.dataCriacao)}',
                          style: Theme.of(context).textTheme.bodyLarge),
                    ],
                  ),
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
                child: Text(
                  _isAtividadeDeCubagem(atividade) ? "Cubagens Manuais" : "Fazendas da Atividade",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ),

              Expanded(
                child: FutureBuilder<List<Fazenda>>(
                  future: _fazendasFuture,
                  builder: (context, fazendasSnapshot) {
                    if (fazendasSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (fazendasSnapshot.hasError) {
                      return Center(child: Text('Erro ao carregar fazendas: ${fazendasSnapshot.error}'));
                    }

                    final fazendas = fazendasSnapshot.data ?? [];

                    if (fazendas.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'Nenhuma fazenda encontrada.\nClique no botão "+" para adicionar a primeira.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: fazendas.length,
                      itemBuilder: (context, index) {
                        final fazenda = fazendas[index];
                        final isSelected = _selectedFazendas.contains(fazenda.id);
                        return Slidable(
                          key: ValueKey(fazenda.id),
                          startActionPane: ActionPane(
                            motion: const DrawerMotion(),
                            children: [
                              SlidableAction(
                                onPressed: (context) => _navegarParaEdicaoFazenda(fazenda),
                                backgroundColor: Colors.blue.shade700,
                                foregroundColor: Colors.white,
                                icon: Icons.edit_outlined,
                                label: 'Editar',
                              ),
                            ],
                          ),
                          endActionPane: ActionPane(
                            motion: const BehindMotion(),
                            children: [
                              SlidableAction(
                                onPressed: (context) => _deleteFazenda(fazenda),
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                icon: Icons.delete_outline,
                                label: 'Excluir',
                              ),
                            ],
                          ),
                          child: Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withAlpha(128) : null,
                            child: ListTile(
                              onTap: () {
                                if (_isSelectionMode) {
                                  _onItemSelected(fazenda.id);
                                } else {
                                  // Passa o objeto 'atividade' carregado para a próxima página
                                  _navegarParaDetalhesFazenda(fazenda, atividade);
                                }
                              },
                              onLongPress: () {
                                if (!_isSelectionMode) {
                                  _toggleSelectionMode(fazenda.id);
                                }
                              },
                              leading: CircleAvatar(
                                backgroundColor: isSelected ? Theme.of(context).colorScheme.primary : null,
                                child: Icon(isSelected ? Icons.check : Icons.agriculture_outlined),
                              ),
                              title: Text(fazenda.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('ID: ${fazenda.id}\n${fazenda.municipio} - ${fazenda.estado}'),
                              trailing: const Icon(Icons.swap_horiz_outlined, color: Colors.grey),
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
            : SpeedDial(
                icon: Icons.add,
                activeIcon: Icons.close,
                children: [
                  if (_isAtividadeDeInventario(atividade) || _isAtividadeDeCubagem(atividade))
                    SpeedDialChild(
                      child: const Icon(Icons.add_business_outlined),
                      label: 'Nova Fazenda',
                      onTap: _navegarParaNovaFazenda,
                    ),
                ],
            ),
        );
      },
    );
  }
}
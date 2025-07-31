// lib/pages/atividades/detalhes_atividade_page.dart (VERSÃO COMPLETA E REFATORADA)

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:intl/intl.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/pages/fazenda/form_fazenda_page.dart';
import 'package:geoforestv1/pages/fazenda/detalhes_fazenda_page.dart';
import 'package:geoforestv1/utils/navigation_helper.dart';

// --- NOVO IMPORT DO REPOSITÓRIO ---
import 'package:geoforestv1/data/repositories/fazenda_repository.dart';
// ------------------------------------

// O import do database_helper foi removido.
// import 'package:geoforestv1/data/datasources/local/database_helper.dart';

class DetalhesAtividadePage extends StatefulWidget {
  final Atividade atividade;
  const DetalhesAtividadePage({super.key, required this.atividade});

  @override
  State<DetalhesAtividadePage> createState() => _DetalhesAtividadePageState();
}

class _DetalhesAtividadePageState extends State<DetalhesAtividadePage> {
  late Future<List<Fazenda>> _fazendasFuture;

  // --- INSTÂNCIA DO NOVO REPOSITÓRIO ---
  final _fazendaRepository = FazendaRepository();
  // ---------------------------------------

  bool _isSelectionMode = false;
  final Set<String> _selectedFazendas = {};

  bool get _isAtividadeDeInventario {
    final tipo = widget.atividade.tipo.toLowerCase();
    return tipo.contains("ipc") || tipo.contains("ifc") || tipo.contains("inventário");
  }

  @override
  void initState() {
    super.initState();
    _carregarFazendas();
  }

  // --- MÉTODO ATUALIZADO ---
  void _carregarFazendas() {
    if (mounted) {
      setState(() {
        _isSelectionMode = false;
        _selectedFazendas.clear();
        // Usa o FazendaRepository
        _fazendasFuture = _fazendaRepository.getFazendasDaAtividade(widget.atividade.id!);
      });
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
  
  // --- MÉTODO ATUALIZADO ---
  Future<void> _deleteFazenda(Fazenda fazenda) async {
     final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text('Tem certeza que deseja apagar a fazenda "${fazenda.nome}" e todos os seus dados? Esta ação não pode ser desfeita.'),
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
      // Usa o FazendaRepository
      await _fazendaRepository.deleteFazenda(fazenda.id, fazenda.atividadeId);
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Fazenda apagada.'),
          backgroundColor: Colors.red));
      _carregarFazendas();
    }
  }

  // O restante dos métodos (navegação, build, etc.) não precisa de alterações
  // pois eles não interagem diretamente com o banco de dados.

  void _navegarParaNovaFazenda() async {
    final bool? fazendaCriada = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FormFazendaPage(atividadeId: widget.atividade.id!),
      ),
    );
    if (fazendaCriada == true && mounted) {
      _carregarFazendas();
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
      _carregarFazendas();
    }
  }

  void _navegarParaDetalhesFazenda(Fazenda fazenda) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DetalhesFazendaPage(
        fazenda: fazenda,
        atividade: widget.atividade,
      )),
    ).then((_) => _carregarFazendas());
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
  
  AppBar _buildNormalAppBar() {
    return AppBar(
      title: Text(widget.atividade.tipo),
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
    return Scaffold(
      appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
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
                  Text("Descrição: ${widget.atividade.descricao.isNotEmpty ? widget.atividade.descricao : 'N/A'}",
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  Text('Data de Criação: ${DateFormat('dd/MM/yyyy').format(widget.atividade.dataCriacao)}',
                      style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
            child: Text(
              "Fazendas da Atividade",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),

          Expanded(
            child: FutureBuilder<List<Fazenda>>(
              future: _fazendasFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Erro ao carregar fazendas: ${snapshot.error}'));
                }

                final fazendas = snapshot.data ?? [];

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
                              _navegarParaDetalhesFazenda(fazenda);
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
              if (_isAtividadeDeInventario)
                SpeedDialChild(
                child: const Icon(Icons.add_business_outlined),
                label: 'Nova Fazenda',
                onTap: _navegarParaNovaFazenda,
              ),
            ],
        ),
    );
  }
}
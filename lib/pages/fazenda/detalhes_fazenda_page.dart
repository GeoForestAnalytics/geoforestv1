// lib/pages/fazenda/detalhes_fazenda_page.dart (VERSÃO COM NAVEGAÇÃO CORRIGIDA)

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/pages/talhoes/form_talhao_page.dart';
import 'package:geoforestv1/pages/talhoes/detalhes_talhao_page.dart';
import 'package:geoforestv1/utils/navigation_helper.dart';

class DetalhesFazendaPage extends StatefulWidget {
  final Fazenda fazenda;
  final Atividade atividade;

  const DetalhesFazendaPage(
      {super.key, required this.fazenda, required this.atividade});

  @override
  State<DetalhesFazendaPage> createState() => _DetalhesFazendaPageState();
}

class _DetalhesFazendaPageState extends State<DetalhesFazendaPage> {
  List<Talhao> _talhoes = [];
  bool _isLoading = true;
  final dbHelper = DatabaseHelper.instance;

  bool _isSelectionMode = false;
  final Set<int> _selectedTalhoes = {};

  @override
  void initState() {
    super.initState();
    _carregarTalhoes();
  }

  void _carregarTalhoes() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isSelectionMode = false;
        _selectedTalhoes.clear();
      });
    }

    final todosOsTalhoes = await dbHelper.getTalhoesDaFazenda(
        widget.fazenda.id, widget.fazenda.atividadeId);

    if (mounted) {
      setState(() {
        _talhoes = todosOsTalhoes;
        _isLoading = false;
      });
    }
  }

  void _toggleSelectionMode(int? talhaoId) {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedTalhoes.clear();
      if (_isSelectionMode && talhaoId != null) {
        _selectedTalhoes.add(talhaoId);
      }
    });
  }

  void _onItemSelected(int talhaoId) {
    setState(() {
      if (_selectedTalhoes.contains(talhaoId)) {
        _selectedTalhoes.remove(talhaoId);
        if (_selectedTalhoes.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedTalhoes.add(talhaoId);
      }
    });
  }

  Future<void> _deleteTalhao(Talhao talhao) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text(
            'Tem certeza que deseja apagar o talhão "${talhao.nome}" e todos os seus dados? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (confirmar == true && mounted) {
      await dbHelper.deleteTalhao(talhao.id!);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Talhão apagado.'), backgroundColor: Colors.red));
      _carregarTalhoes();
    }
  }

  void _navegarParaNovoTalhao() async {
    final bool? talhaoCriado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FormTalhaoPage(
          fazendaId: widget.fazenda.id,
          fazendaAtividadeId: widget.fazenda.atividadeId,
        ),
      ),
    );
    if (talhaoCriado == true && mounted) {
      _carregarTalhoes();
    }
  }

  void _navegarParaEdicaoTalhao(Talhao talhao) async {
    final bool? talhaoEditado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FormTalhaoPage(
          fazendaId: talhao.fazendaId,
          fazendaAtividadeId: talhao.fazendaAtividadeId,
          talhaoParaEditar: talhao,
        ),
      ),
    );
    if (talhaoEditado == true && mounted) {
      _carregarTalhoes();
    }
  }

  void _navegarParaDetalhesTalhao(Talhao talhao) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => DetalhesTalhaoPage(
                talhao: talhao,
                atividade: widget.atividade,
              )),
    ).then((_) => _carregarTalhoes());
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      title: Text('${_selectedTalhoes.length} selecionado(s)'),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => _toggleSelectionMode(null),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Apagar selecionados',
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Use o deslize para apagar individualmente.')));
          },
        ),
      ],
    );
  }

  AppBar _buildNormalAppBar() {
    return AppBar(
      title: Text(widget.fazenda.nome),
      actions: [
        IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: 'Voltar para o Início',
          // <<< CORREÇÃO DA NAVEGAÇÃO >>>
          // Em vez de recriar a HomePage, ele "desempilha" as telas até chegar na primeira.
          onPressed: () => NavigationHelper.goBackToHome(context)
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
                  Text('Detalhes da Fazenda',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Divider(height: 20),
                  Text("ID: ${widget.fazenda.id}",
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  Text(
                      "Local: ${widget.fazenda.municipio} - ${widget.fazenda.estado.toUpperCase()}",
                      style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
            child: Text(
              "Talhões da Fazenda",
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _talhoes.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'Nenhum talhão encontrado.\nClique no botão "+" para adicionar o primeiro.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey.shade600),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: _talhoes.length,
                        itemBuilder: (context, index) {
                          final talhao = _talhoes[index];
                          final isSelected =
                              _selectedTalhoes.contains(talhao.id!);
                          return Slidable(
                            key: ValueKey(talhao.id),
                            startActionPane: ActionPane(
                              motion: const DrawerMotion(),
                              children: [
                                SlidableAction(
                                  onPressed: (context) =>
                                      _navegarParaEdicaoTalhao(talhao),
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
                                  onPressed: (context) => _deleteTalhao(talhao),
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  icon: Icons.delete_outline,
                                  label: 'Excluir',
                                ),
                              ],
                            ),
                            child: Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              color: isSelected
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withAlpha(128)
                                  : null,
                              child: ListTile(
                                onTap: () {
                                  if (_isSelectionMode) {
                                    _onItemSelected(talhao.id!);
                                  } else {
                                    _navegarParaDetalhesTalhao(talhao);
                                  }
                                },
                                onLongPress: () {
                                  if (!_isSelectionMode) {
                                    _toggleSelectionMode(talhao.id!);
                                  }
                                },
                                leading: CircleAvatar(
                                  backgroundColor: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                  child: Icon(isSelected
                                      ? Icons.check
                                      : Icons.park_outlined),
                                ),
                                title: Text(talhao.nome,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                    'Área: ${talhao.areaHa?.toStringAsFixed(2) ?? 'N/A'} ha - Espécie: ${talhao.especie ?? 'N/A'}'),
                                trailing: const Icon(Icons.swap_horiz_outlined,
                                    color: Colors.grey),
                                selected: isSelected,
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: _navegarParaNovoTalhao,
              tooltip: 'Novo Talhão',
              icon: const Icon(Icons.add_chart),
              label: const Text('Novo Talhão'),
            ),
    );
  }
}
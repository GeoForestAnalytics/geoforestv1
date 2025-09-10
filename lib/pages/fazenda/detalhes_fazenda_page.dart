// lib/pages/fazenda/detalhes_fazenda_page.dart (VERSÃO FINAL CORRIGIDA)

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/pages/talhoes/form_talhao_page.dart';
import 'package:geoforestv1/utils/navigation_helper.dart';

// Repositórios
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/data/repositories/fazenda_repository.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';


class DetalhesFazendaPage extends StatefulWidget {
  final int atividadeId;
  final String fazendaId;

  const DetalhesFazendaPage({
    super.key, 
    required this.atividadeId, 
    required this.fazendaId
  });

  @override
  State<DetalhesFazendaPage> createState() => _DetalhesFazendaPageState();
}

class _DetalhesFazendaPageState extends State<DetalhesFazendaPage> {
  final _talhaoRepository = TalhaoRepository();
  final _fazendaRepository = FazendaRepository();
  final _atividadeRepository = AtividadeRepository();
  
  late Future<List<dynamic>> _pageDataFuture; // ✅ Future único para carregar dados da página
  late Future<List<Talhao>> _talhoesFuture;

  bool _isSelectionMode = false;
  final Set<int> _selectedTalhoes = {};

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  void _carregarDados() {
    setState(() {
      _isSelectionMode = false;
      _selectedTalhoes.clear();
      // Carrega os dados principais da página em um único Future
      _pageDataFuture = Future.wait([
        _atividadeRepository.getAtividadeById(widget.atividadeId),
        _getFazendaDaAtividade(),
      ]);
      // Carrega a lista de talhões separadamente
      _talhoesFuture = _talhaoRepository.getTalhoesDaFazenda(widget.fazendaId, widget.atividadeId);
    });
  }
  
  void _recarregarTalhoes() {
    setState(() {
      _talhoesFuture = _talhaoRepository.getTalhoesDaFazenda(widget.fazendaId, widget.atividadeId);
    });
  }

  Future<Fazenda?> _getFazendaDaAtividade() async {
    final fazendas = await _fazendaRepository.getFazendasDaAtividade(widget.atividadeId);
    try {
      return fazendas.firstWhere((f) => f.id == widget.fazendaId);
    } catch (e) {
      return null;
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
        if (_selectedTalhoes.isEmpty) _isSelectionMode = false;
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
        content: Text('Tem certeza que deseja apagar o talhão "${talhao.nome}" e todos os seus dados?'),
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
      await _talhaoRepository.deleteTalhao(talhao.id!);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Talhão apagado.'), backgroundColor: Colors.red));
      _recarregarTalhoes();
    }
  }
  
  void _navegarParaNovoTalhao() async {
    final bool? talhaoCriado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FormTalhaoPage(
          fazendaId: widget.fazendaId,
          fazendaAtividadeId: widget.atividadeId,
        ),
      ),
    );
    if (talhaoCriado == true && mounted) {
      _recarregarTalhoes();
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
      _recarregarTalhoes();
    }
  }

  // ✅ NAVEGAÇÃO FINALMENTE CORRIGIDA
  void _navegarParaDetalhesTalhao(Talhao talhao, Atividade atividade) {
    final projetoId = atividade.projetoId;
    // Usa o widget.fazendaId em vez de um objeto que não existe neste escopo
    context.go('/projetos/$projetoId/atividades/${atividade.id}/fazendas/${widget.fazendaId}/talhoes/${talhao.id}');
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      title: Text('${_selectedTalhoes.length} selecionado(s)'),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => _toggleSelectionMode(null),
      ),
      actions: [ /* Lógica de apagar múltiplos pode ser adicionada aqui */ ],
    );
  }

  AppBar _buildNormalAppBar(Fazenda? fazenda) {
    return AppBar(
      title: Text(fazenda?.nome ?? 'Carregando...'),
      actions: [
        IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: 'Voltar para o Início',
          onPressed: () => NavigationHelper.goBackToHome(context)
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _pageDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return Scaffold(appBar: AppBar(title: const Text('Erro')), body: Center(child: Text('Erro ao carregar dados: ${snapshot.error}')));
        }

        // ✅ CORREÇÃO DO ERRO DE TIPO
        // Fazemos o "cast" explícito para dizer ao Dart qual é o tipo de cada item na lista.
        final Atividade? atividade = snapshot.data![0] as Atividade?;
        final Fazenda? fazenda = snapshot.data![1] as Fazenda?;

        if (atividade == null || fazenda == null) {
          return Scaffold(appBar: AppBar(title: const Text('Erro')), body: const Center(child: Text('Não foi possível encontrar os dados da atividade ou fazenda.')));
        }

        return Scaffold(
          appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(fazenda),
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
                      Text('Detalhes da Fazenda', style: Theme.of(context).textTheme.titleLarge),
                      const Divider(height: 20),
                      Text("ID: ${fazenda.id}", style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 8),
                      Text("Local: ${fazenda.municipio} - ${fazenda.estado.toUpperCase()}", style: Theme.of(context).textTheme.bodyLarge),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
                child: Text("Talhões da Fazenda", style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
              ),
              Expanded(
                child: FutureBuilder<List<Talhao>>(
                  future: _talhoesFuture,
                  builder: (context, talhoesSnapshot) {
                    if (talhoesSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (talhoesSnapshot.hasError) {
                      return Center(child: Text('Erro ao carregar talhões: ${talhoesSnapshot.error}'));
                    }
                    final talhoes = talhoesSnapshot.data ?? [];
                    if (talhoes.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('Nenhum talhão encontrado.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)),
                        ),
                      );
                    }
                    return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: talhoes.length,
                        itemBuilder: (context, index) {
                          final talhao = talhoes[index];
                          final isSelected = _selectedTalhoes.contains(talhao.id!);
                          return Slidable(
                            key: ValueKey(talhao.id),
                            startActionPane: ActionPane(
                              motion: const DrawerMotion(),
                              children: [
                                SlidableAction(
                                  onPressed: (context) => _navegarParaEdicaoTalhao(talhao),
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
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withAlpha(128) : null,
                              child: ListTile(
                                onTap: () {
                                  if (_isSelectionMode) {
                                    _onItemSelected(talhao.id!);
                                  } else {
                                    _navegarParaDetalhesTalhao(talhao, atividade);
                                  }
                                },
                                onLongPress: () {
                                  if (!_isSelectionMode) {
                                    _toggleSelectionMode(talhao.id!);
                                  }
                                },
                                leading: CircleAvatar(
                                  backgroundColor: isSelected ? Theme.of(context).colorScheme.primary : null,
                                  child: Icon(isSelected ? Icons.check : Icons.park_outlined),
                                ),
                                title: Text(talhao.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Área: ${talhao.areaHa?.toStringAsFixed(2) ?? 'N/A'} ha - Espécie: ${talhao.especie ?? 'N/A'}'),
                                trailing: const Icon(Icons.swap_horiz_outlined, color: Colors.grey),
                                selected: isSelected,
                              ),
                            ),
                          );
                        },
                      );
                  }
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
      },
    );
  }
}
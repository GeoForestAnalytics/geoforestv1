// lib/pages/talhoes/detalhes_talhao_page.dart (VERSÃO FINAL COMPLETA COM GO_ROUTER)

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:intl/intl.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/pages/dashboard/talhao_dashboard_page.dart';
import 'package:geoforestv1/pages/amostra/coleta_dados_page.dart';
import 'package:geoforestv1/pages/cubagem/cubagem_dados_page.dart';
import 'package:geoforestv1/utils/navigation_helper.dart';

// Repositórios
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';

class DetalhesTalhaoPage extends StatefulWidget {
  // ✅ CONSTRUTOR MODIFICADO
  final int atividadeId;
  final int talhaoId;

  const DetalhesTalhaoPage({
    super.key,
    required this.atividadeId,
    required this.talhaoId,
  });

  @override
  State<DetalhesTalhaoPage> createState() => _DetalhesTalhaoPageState();
}

class _DetalhesTalhaoPageState extends State<DetalhesTalhaoPage> {
  // ✅ INSTÂNCIAS DOS REPOSITÓRIOS
  final _parcelaRepository = ParcelaRepository();
  final _cubagemRepository = CubagemRepository();
  final _talhaoRepository = TalhaoRepository();
  final _atividadeRepository = AtividadeRepository();

  // ✅ ESTADO COM FUTURES
  late Future<List<dynamic>> _pageDataFuture; // Para Talhão e Atividade
  late Future<List<dynamic>> _coletasFuture;

  bool _isSelectionMode = false;
  final Set<int> _selectedItens = {};

  // Função auxiliar para verificar tipo de atividade
  bool _isAtividadeDeInventario(Atividade? atividade) {
    if (atividade == null) return false;
    final tipo = atividade.tipo.toLowerCase();
    return tipo.contains("ipc") ||
        tipo.contains("ifc") ||
        tipo.contains("inventário");
  }

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  void _carregarDados() {
    if (mounted) {
      setState(() {
        _isSelectionMode = false;
        _selectedItens.clear();
        _pageDataFuture = Future.wait([
          _talhaoRepository.getTalhaoById(widget.talhaoId),
          _atividadeRepository.getAtividadeById(widget.atividadeId),
        ]);
        
        // Define _coletasFuture dentro do .then() para garantir que 'atividade' não seja nulo
        _pageDataFuture.then((data) {
          if (mounted) {
            final Atividade? atividade = data.length > 1 ? data[1] as Atividade? : null;
            setState(() {
              if (_isAtividadeDeInventario(atividade)) {
                _coletasFuture = _parcelaRepository.getParcelasDoTalhao(widget.talhaoId);
              } else {
                _coletasFuture = _cubagemRepository.getTodasCubagensDoTalhao(widget.talhaoId);
              }
            });
          }
        });
      });
    }
  }

  Future<void> _navegarParaNovaParcela(Talhao talhao) async {
    final bool? recarregar = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ColetaDadosPage(talhao: talhao)),
    );
    if (recarregar == true && mounted) _carregarDados();
  }

  Future<void> _deleteSelectedItems(bool isInventario) async {
    if (_selectedItens.isEmpty || !mounted) return;

    final itemType = isInventario ? 'parcelas' : 'cubagens';
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text('Tem certeza que deseja apagar os ${_selectedItens.length} $itemType selecionados?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Apagar')),
        ],
      ),
    );

    if (confirmar == true) {
      if (isInventario) {
        await _parcelaRepository.deletarMultiplasParcelas(_selectedItens.toList());
      } else {
        await _cubagemRepository.deletarMultiplasCubagens(_selectedItens.toList());
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_selectedItens.length} $itemType apagados.'), backgroundColor: Colors.green));
      _carregarDados();
    }
  }
  
  Future<void> _navegarParaNovaCubagem(Talhao talhao) async {
    final String? metodoEscolhido = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Escolha o Método de Cubagem'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Seções Fixas'),
                subtitle: const Text('Medições em alturas pré-definidas (0.1m, 0.3m, 0.7m, 1.0m...).'),
                onTap: () => Navigator.of(context).pop('Fixas'),
              ),
              ListTile(
                title: const Text('Seções Relativas'),
                subtitle: const Text('Medições em porcentagens da altura total.'),
                onTap: () => Navigator.of(context).pop('Relativas'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );

    if (metodoEscolhido == null || !mounted) return;

    final arvoreCubagem = CubagemArvore(
      talhaoId: talhao.id,
      nomeFazenda: talhao.fazendaNome ?? 'N/A',
      nomeTalhao: talhao.nome,
      identificador: 'Cubagem Avulsa',
    );

    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CubagemDadosPage(
          metodo: metodoEscolhido,
          arvoreParaEditar: arvoreCubagem,
        ),
      ),
    );

    if (resultado != null && mounted) {
      _carregarDados();
    }
  }
  
  Future<void> _navegarParaDetalhesParcela(Parcela parcela) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ColetaDadosPage(parcelaParaEditar: parcela),
      ),
    );
    _carregarDados();
  }
  
  Future<void> _navegarParaDetalhesCubagem(CubagemArvore arvore, Atividade atividade) async {
    final metodoCorreto = arvore.metodoCubagem ?? atividade.metodoCubagem ?? 'Fixas';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CubagemDadosPage(
          metodo: metodoCorreto,
          arvoreParaEditar: arvore,
        ),
      ),
    );
    _carregarDados();
  }
  
  void _toggleSelectionMode(int? itemId) {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedItens.clear();
      if (_isSelectionMode && itemId != null) {
        _selectedItens.add(itemId);
      }
    });
  }

  void _onItemSelected(int itemId) {
    setState(() {
      if (_selectedItens.contains(itemId)) {
        _selectedItens.remove(itemId);
        if (_selectedItens.isEmpty) _isSelectionMode = false;
      } else {
        _selectedItens.add(itemId);
      }
    });
  }

  AppBar _buildAppBar(Talhao? talhao, Atividade? atividade) {
    return AppBar(
      title: Text('Talhão: ${talhao?.nome ?? 'Carregando...'}'),
      actions: [
        if (_isAtividadeDeInventario(atividade) && talhao != null)
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'Ver Análise do Talhão',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => TalhaoDashboardPage(talhao: talhao))),
          ),
        IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: 'Voltar para o Início',
          onPressed: () => NavigationHelper.goBackToHome(context),
        ),
      ],
    );
  }

  String _traduzirStatus(StatusParcela status) {
    switch (status) {
      case StatusParcela.pendente:
        return 'Pendente';
      case StatusParcela.emAndamento:
        return 'Em Andamento';
      case StatusParcela.concluida:
        return 'Concluída';
      case StatusParcela.exportada:
        return 'Exportada';
    }
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

        final Talhao? talhao = snapshot.data![0] as Talhao?;
        final Atividade? atividade = snapshot.data![1] as Atividade?;

        if (talhao == null || atividade == null) {
          return Scaffold(appBar: AppBar(title: const Text('Erro')), body: const Center(child: Text('Não foi possível encontrar os dados do talhão ou atividade.')));
        }

        return Scaffold(
          appBar: _isSelectionMode
              ? AppBar(
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => _toggleSelectionMode(null)),
                  title: Text('${_selectedItens.length} selecionados'),
                  actions: [IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteSelectedItems(_isAtividadeDeInventario(atividade)), tooltip: 'Apagar Selecionados')],
                )
              : _buildAppBar(talhao, atividade),
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
                      Text('Detalhes do Talhão', style: Theme.of(context).textTheme.titleLarge),
                      const Divider(height: 20),
                      Text("Atividade: ${atividade.tipo}", style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text("Fazenda: ${talhao.fazendaNome ?? 'Não informada'}", style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 8),
                      Text("Espécie: ${talhao.especie ?? 'Não informada'}", style: Theme.of(context).textTheme.bodyLarge),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                child: Text(
                  _isAtividadeDeInventario(atividade) ? "Coletas de Parcela" : "Árvores para Cubagem",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<dynamic>>(
                  future: _coletasFuture,
                  builder: (context, coletasSnapshot) {
                    if (coletasSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (coletasSnapshot.hasError) {
                      return Center(child: Text('Erro: ${coletasSnapshot.error}'));
                    }

                    final itens = coletasSnapshot.data ?? [];
                    if (itens.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            _isAtividadeDeInventario(atividade)
                                ? 'Nenhuma parcela coletada.\nClique no botão "+" para iniciar.'
                                : 'Nenhuma árvore para cubar.\nClique no botão "+" para adicionar uma cubagem manual.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ),
                      );
                    }

                    return _isAtividadeDeInventario(atividade)
                        ? _buildListaDeParcelas(itens.cast<Parcela>())
                        : _buildListaDeCubagens(itens.cast<CubagemArvore>(), atividade);
                  },
                ),
              ),
            ],
          ),
          floatingActionButton: _isSelectionMode
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _isAtividadeDeInventario(atividade) ? _navegarParaNovaParcela(talhao) : _navegarParaNovaCubagem(talhao),
                  tooltip: _isAtividadeDeInventario(atividade) ? 'Nova Parcela' : 'Nova Cubagem Manual',
                  icon: Icon(_isAtividadeDeInventario(atividade) ? Icons.add_location_alt_outlined : Icons.add),
                  label: Text(_isAtividadeDeInventario(atividade) ? 'Nova Parcela' : 'Nova Cubagem'),
                ),
        );
      },
    );
  }

  Widget _buildListaDeParcelas(List<Parcela> parcelas) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: parcelas.length,
      itemBuilder: (context, index) {
        final parcela = parcelas[index];
        final isSelected = _selectedItens.contains(parcela.dbId!);
        final dataFormatada = DateFormat('dd/MM/yyyy HH:mm').format(parcela.dataColeta!);
        
        final bool foiExportada = parcela.exportada;
        final StatusParcela statusFinal = foiExportada ? StatusParcela.exportada : parcela.status;
        final Color corFinal = foiExportada ? StatusParcela.exportada.cor : parcela.status.cor;
        final IconData iconeFinal = foiExportada ? StatusParcela.exportada.icone : parcela.status.icone;

        String titulo = 'Parcela ID: ${parcela.idParcela}';
        if (parcela.up != null && parcela.up!.isNotEmpty) {
          titulo = 'UP: ${parcela.up} / Parcela: ${parcela.idParcela}';
        }
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withAlpha(128) : null,
          child: ListTile(
            onTap: () => _isSelectionMode ? _onItemSelected(parcela.dbId!) : _navegarParaDetalhesParcela(parcela),
            onLongPress: () => _toggleSelectionMode(parcela.dbId!),
            leading: CircleAvatar(
              backgroundColor: isSelected ? Theme.of(context).colorScheme.primary : corFinal,
              child: Icon(isSelected ? Icons.check : iconeFinal, color: Colors.white),
            ),
            title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Status: ${_traduzirStatus(statusFinal)}\nColetado em: $dataFormatada'),
            trailing: _isSelectionMode
                ? null
                : IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () {
                      _selectedItens.clear();
                      _selectedItens.add(parcela.dbId!);
                      _deleteSelectedItems(true);
                    },
                  ),
            selected: isSelected,
          ),
        );
      },
    );
  }

  Widget _buildListaDeCubagens(List<CubagemArvore> cubagens, Atividade atividade) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: cubagens.length,
      itemBuilder: (context, index) {
        final arvore = cubagens[index];
        final isSelected = _selectedItens.contains(arvore.id!);
        final isConcluida = arvore.alturaTotal > 0;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withAlpha(128) : null,
          child: ListTile(
            onTap: () => _isSelectionMode ? _onItemSelected(arvore.id!) : _navegarParaDetalhesCubagem(arvore, atividade),
            onLongPress: () => _toggleSelectionMode(arvore.id!),
            leading: CircleAvatar(
              backgroundColor: isConcluida ? Colors.green : (isSelected ? Theme.of(context).colorScheme.primary : Colors.grey),
              child: Icon(isSelected ? Icons.check : (isConcluida ? Icons.check : Icons.pending_outlined), color: Colors.white),
            ),
            title: Text(arvore.identificador),
            subtitle: Text('Classe: ${arvore.classe ?? "Avulsa"}'),
            trailing: _isSelectionMode
                ? null
                : IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () {
                      _selectedItens.clear();
                      _selectedItens.add(arvore.id!);
                      _deleteSelectedItems(false);
                    },
                  ),
            selected: isSelected,
          ),
        );
      },
    );
  }
}
// lib/pages/talhoes/detalhes_talhao_page.dart

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/pilha_madeira_model.dart';
import 'package:intl/intl.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/pages/dashboard/talhao_dashboard_page.dart';
import 'package:geoforestv1/pages/amostra/coleta_dados_page.dart';
import 'package:geoforestv1/pages/cubagem/cubagem_dados_page.dart';
import 'package:geoforestv1/pages/pilhas/coleta_pilha_page.dart';
import 'package:geoforestv1/pages/pilhas/detalhe_pilha_page.dart';
import 'package:geoforestv1/pages/pilhas/estoque_saida_page.dart';
import 'package:geoforestv1/pages/silvicultura/coleta_silvi_page.dart';
import 'package:geoforestv1/pages/silvicultura/visualizar_areas_silvi_page.dart';
import 'package:geoforestv1/utils/navigation_helper.dart';

// Repositórios
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/data/repositories/estoque_repository.dart';
import 'package:geoforestv1/data/repositories/pilha_repository.dart';
import 'package:geoforestv1/data/repositories/silvi_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/models/estoque_saida_model.dart';
import 'package:geoforestv1/models/silvi_model.dart';

class DetalhesTalhaoPage extends StatefulWidget {
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
  final _parcelaRepository = ParcelaRepository();
  final _cubagemRepository = CubagemRepository();
  final _pilhaRepository = PilhaRepository();
  final _estoqueRepository = EstoqueRepository();
  final _silviRepository = SilviRepository();
  final _talhaoRepository = TalhaoRepository();
  final _atividadeRepository = AtividadeRepository();

  late Future<List<dynamic>> _pageDataFuture;
  late Future<List<dynamic>> _coletasFuture;
  Future<List<EstoqueSaida>>? _estoquesFuture;

  bool _isSelectionMode = false;
  final Set<int> _selectedItens = {};

  bool _isAtividadeDeInventario(Atividade? atividade) {
    if (atividade == null) return false;
    final tipo = atividade.tipo.toLowerCase();
    return tipo.contains("ipc") ||
        tipo.contains("ifc") ||
        tipo.contains("ifs") ||
        tipo.contains("bio") ||
        tipo.contains("inventário");
  }

  bool _isAtividadeDeColheita(Atividade? atividade) {
    if (atividade == null) return false;
    final tipo = atividade.tipo.toLowerCase();
    return tipo.contains('colheita') || tipo.contains('pilha');
  }

  bool _isAtividadeDeSilvicultura(Atividade? atividade) {
    if (atividade == null) return false;
    final tipo = atividade.tipo.toLowerCase();
    return tipo.contains('silvi');
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

        _pageDataFuture.then((data) {
          if (mounted) {
            final Atividade? atividade = data.length > 1 ? data[1] as Atividade? : null;
            setState(() {
              if (_isAtividadeDeInventario(atividade)) {
                _coletasFuture = _parcelaRepository.getParcelasDoTalhao(widget.talhaoId);
              } else if (_isAtividadeDeColheita(atividade)) {
                _coletasFuture = _pilhaRepository.getPilhasDoTalhao(widget.talhaoId);
                _estoquesFuture = _estoqueRepository.getEstoquesDoTalhao(widget.talhaoId);
              } else if (_isAtividadeDeSilvicultura(atividade)) {
                _coletasFuture = _silviRepository.getOperacoesDoTalhao(widget.talhaoId);
              } else {
                _coletasFuture = _cubagemRepository.getTodasCubagensDoTalhao(widget.talhaoId).then((lista) {
                  lista.sort((a, b) => a.identificador.compareTo(b.identificador));
                  return lista;
                });
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

  Future<void> _navegarParaNovaPilha(Talhao talhao) async {
    final centroide = await _pilhaRepository.getCentroideParaTalhao(talhao.id!);
    if (!mounted) return;
    if (centroide == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum centróide configurado para este talhão.')),
      );
      return;
    }

    // Mostra opção: Nova Pilha ou Saída de Estoque
    final escolha = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.brown.shade100,
                child: const Icon(Icons.layers_outlined, color: Colors.brown),
              ),
              title: const Text('Nova Pilha', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Medição com seções por comprimento'),
              onTap: () => Navigator.pop(context, 'pilha'),
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.orange.shade100,
                child: Icon(Icons.local_shipping_outlined, color: Colors.orange.shade800),
              ),
              title: const Text('Saída de Estoque', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Volume declarado sem medição de seções'),
              onTap: () => Navigator.pop(context, 'estoque'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || escolha == null) return;

    if (escolha == 'pilha') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ColetaPilhaPage(centroide: centroide)),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EstoqueSaidaPage(centroide: centroide)),
      );
    }

    if (mounted) _carregarDados();
  }

  Future<void> _navegarParaNovaOperacaoSilvi(Talhao talhao) async {
    final centroide = await _silviRepository.getCentroideParaTalhao(talhao.id!);
    if (!mounted) return;
    if (centroide == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum ponto de silvicultura configurado para este talhão.')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ColetaSilviPage(centroide: centroide)),
    );
    if (mounted) _carregarDados();
  }

  Future<void> _deleteSelectedItems(bool isInventario, {bool isColheita = false, bool isSilvicultura = false}) async {
    if (_selectedItens.isEmpty || !mounted) return;

    final itemType = isInventario ? 'parcelas' : isColheita ? 'pilhas' : isSilvicultura ? 'operações' : 'cubagens';
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text('Tem certeza que deseja apagar os ${_selectedItens.length} $itemType selecionados?'),
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

    if (confirmar == true) {
      if (isInventario) {
        await _parcelaRepository.deletarMultiplasParcelas(_selectedItens.toList());
      } else if (isColheita) {
        for (final id in _selectedItens) {
          await _pilhaRepository.deletePilha(id);
        }
      } else if (isSilvicultura) {
        for (final id in _selectedItens) {
          await _silviRepository.deletarOperacao(id);
        }
      } else {
        await _cubagemRepository.deletarMultiplasCubagens(_selectedItens.toList());
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_selectedItens.length} $itemType apagados.'), backgroundColor: Colors.green),
        );
      }
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

  Future<void> _navegarParaDetalhesPilha(PilhaMadeira pilha) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DetalhePilhaPage(pilha: pilha)),
    );
    if (mounted) _carregarDados();
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

        final bool isInventario = _isAtividadeDeInventario(atividade);
        final bool isColheita = _isAtividadeDeColheita(atividade);
        final bool isSilvicultura = _isAtividadeDeSilvicultura(atividade);

        return Scaffold(
          appBar: _isSelectionMode
              ? AppBar(
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => _toggleSelectionMode(null)),
                  title: Text('${_selectedItens.length} selecionados'),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteSelectedItems(isInventario, isColheita: isColheita, isSilvicultura: isSilvicultura),
                      tooltip: 'Apagar Selecionados',
                    ),
                  ],
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
                  isInventario
                      ? "Coletas de Parcela"
                      : isColheita
                          ? "Pilhas de Madeira"
                          : isSilvicultura
                              ? "Operações Silviculturais"
                              : "Árvores para Cubagem",
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

                    if (isInventario) {
                      if (itens.isEmpty) {
                        return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Nenhuma parcela coletada.\nClique no botão "+" para iniciar.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey))));
                      }
                      return _buildListaDeParcelas(itens.cast<Parcela>());
                    } else if (isColheita) {
                      return FutureBuilder<List<EstoqueSaida>>(
                        future: _estoquesFuture,
                        builder: (_, estoqueSnap) {
                          final estoques = estoqueSnap.data ?? [];
                          if (itens.isEmpty && estoques.isEmpty) {
                            return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Nenhuma pilha registrada.\nClique no botão "+" para adicionar.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey))));
                          }
                          return _buildListaDePilhasEEstoques(itens.cast<PilhaMadeira>(), estoques);
                        },
                      );
                    } else if (isSilvicultura) {
                      if (itens.isEmpty) {
                        return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Nenhuma operação registrada.\nClique no botão "+" para registrar.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey))));
                      }
                      return _buildListaDeOperacoesSilvi(itens.cast<OperacaoSilvi>());
                    } else {
                      if (itens.isEmpty) {
                        return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Nenhuma árvore para cubar.\nClique no botão "+" para adicionar uma cubagem manual.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey))));
                      }
                      return _buildListaDeCubagens(itens.cast<CubagemArvore>(), atividade);
                    }
                  },
                ),
              ),
            ],
          ),
          floatingActionButton: _isSelectionMode
              ? null
              : FloatingActionButton.extended(
                  onPressed: () {
                    if (isInventario) {
                      _navegarParaNovaParcela(talhao);
                    } else if (isColheita) {
                      _navegarParaNovaPilha(talhao);
                    } else if (isSilvicultura) {
                      _navegarParaNovaOperacaoSilvi(talhao);
                    } else {
                      _navegarParaNovaCubagem(talhao);
                    }
                  },
                  tooltip: isInventario
                      ? 'Nova Parcela'
                      : isColheita
                          ? 'Nova Pilha'
                          : isSilvicultura
                              ? 'Nova Operação'
                              : 'Nova Cubagem Manual',
                  icon: Icon(isInventario
                      ? Icons.add_location_alt_outlined
                      : isColheita
                          ? Icons.layers_outlined
                          : isSilvicultura
                              ? Icons.spa_outlined
                              : Icons.add),
                  label: Text(isInventario
                      ? 'Nova Parcela'
                      : isColheita
                          ? 'Nova Pilha'
                          : isSilvicultura
                              ? 'Nova Operação'
                              : 'Nova Cubagem'),
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

  Widget _buildListaDePilhasEEstoques(List<PilhaMadeira> pilhas, List<EstoqueSaida> estoques) {
    final nf2 = NumberFormat('#,##0.00', 'pt_BR');
    return CustomScrollView(
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              final pilha = pilhas[i];
              final isSelected = _selectedItens.contains(pilha.id!);
              final volEstereo = pilha.calcularVolumeBruto();
              final volSolido = pilha.calcularVolumesolido();
              final dataFormatada = pilha.dataColeta != null ? DateFormat('dd/MM/yyyy HH:mm').format(pilha.dataColeta!) : '';
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withAlpha(128) : null,
                child: ListTile(
                  onTap: () => _isSelectionMode ? _onItemSelected(pilha.id!) : _navegarParaDetalhesPilha(pilha),
                  onLongPress: () => _toggleSelectionMode(pilha.id!),
                  leading: CircleAvatar(
                    backgroundColor: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : (pilha.exportada ? Colors.grey : Colors.brown),
                    child: Icon(isSelected ? Icons.check : Icons.layers_outlined, color: Colors.white),
                  ),
                  title: Text('Pilha ${pilha.numeroPilha}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${nf2.format(volEstereo)} st  ·  ${nf2.format(volSolido)} m³ sólido\n$dataFormatada'),
                  trailing: _isSelectionMode
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () {
                            _selectedItens.clear();
                            _selectedItens.add(pilha.id!);
                            _deleteSelectedItems(false, isColheita: true);
                          },
                        ),
                  selected: isSelected,
                ),
              );
            },
            childCount: pilhas.length,
          ),
        ),
        if (estoques.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'Saídas de Estoque',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
            ),
          ),
        if (estoques.isNotEmpty)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final e = estoques[i];
                final dataStr = DateFormat('dd/MM/yyyy').format(DateTime.parse(e.dataRegistro));
                final caminhoes = e.numeroCaminhoes > 0 ? ' · ${e.numeroCaminhoes} caminhão(ões)' : '';
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.shade700,
                      child: const Icon(Icons.local_shipping_outlined, color: Colors.white, size: 20),
                    ),
                    title: Text(e.sortimento, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${nf2.format(e.volumeM3)} m³$caminhoes\n$dataStr'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _deletarEstoque(e),
                    ),
                    onTap: () async {
                      final centroide = CentroidePilha(
                        id: e.centroideId,
                        talhaoId: e.talhaoId,
                        fazendaId: e.fazendaId,
                        nomeFazenda: e.nomeFazenda,
                        nomeTalhao: e.nomeTalhao,
                        latitude: 0,
                        longitude: 0,
                        sortimentos: [SortimentoConfig(nome: e.sortimento, comprimentoTora: 2.4)],
                      );
                      final editado = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EstoqueSaidaPage(centroide: centroide, initialData: e),
                        ),
                      );
                      if (editado == true && mounted) _carregarDados();
                    },
                  ),
                );
              },
              childCount: estoques.length,
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
      ],
    );
  }

  Future<void> _deletarEstoque(EstoqueSaida estoque) async {
    final nf2 = NumberFormat('#,##0.00', 'pt_BR');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir saída de estoque?'),
        content: Text('${nf2.format(estoque.volumeM3)} m³ de ${estoque.sortimento} em ${DateFormat('dd/MM/yyyy').format(DateTime.parse(estoque.dataRegistro))}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _estoqueRepository.deletar(estoque.id!);
      _carregarDados();
    }
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

  Future<void> _abrirOpcoesOperacaoSilvi(
      OperacaoSilvi op, List<OperacaoSilvi> todasOperacoes) async {
    final centroide = await _silviRepository.getCentroideParaTalhao(widget.talhaoId);
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        final tipoEnum = op.tipoEnum;
        final dataFormatada = op.dataExecucao != null
            ? DateFormat('dd/MM/yyyy')
                .format(DateTime.tryParse(op.dataExecucao!) ?? DateTime.now())
            : '—';
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: tipoEnum.color.withValues(alpha: 0.15),
                  child: Icon(tipoEnum.icon, color: tipoEnum.color),
                ),
                title: Text(tipoEnum.label,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  '${op.areaAplicadaHa != null ? "${op.areaAplicadaHa!.toStringAsFixed(2)} ha  •  " : ""}$dataFormatada',
                ),
              ),
              const Divider(height: 1),
              if (centroide != null) ...[
                ListTile(
                  leading: const Icon(Icons.map_outlined),
                  title: const Text('Ver todas as áreas no mapa'),
                  subtitle: Text(
                    '${todasOperacoes.where((o) => o.areaGeoJson != null).length} '
                    'polígono(s) registrado(s)',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VisualizarAreasSilviPage(
                          operacoes: todasOperacoes,
                          centroide: centroide,
                        ),
                      ),
                    );
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Editar operação'),
                onTap: () async {
                  Navigator.pop(context);
                  if (centroide == null) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ColetaSilviPage(
                          centroide: centroide, initialData: op),
                    ),
                  );
                  if (mounted) _carregarDados();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildListaDeOperacoesSilvi(List<OperacaoSilvi> operacoes) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: operacoes.length,
      itemBuilder: (context, index) {
        final op = operacoes[index];
        final isSelected = _selectedItens.contains(op.id!);
        final tipoEnum = op.tipoEnum;
        final dataFormatada = op.dataExecucao != null
            ? DateFormat('dd/MM/yyyy')
                .format(DateTime.tryParse(op.dataExecucao!) ?? DateTime.now())
            : '—';
        final temPoligono = op.areaGeoJson != null && op.areaGeoJson!.isNotEmpty;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: tipoEnum.color.withValues(alpha: 0.15),
              child: Icon(tipoEnum.icon, color: tipoEnum.color, size: 22),
            ),
            title: Text(tipoEnum.label,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              '${op.areaAplicadaHa != null ? "${op.areaAplicadaHa!.toStringAsFixed(2)} ha  •  " : ""}$dataFormatada'
              '${op.nomeLider != null ? "\n${op.nomeLider}" : ""}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (temPoligono)
                  Icon(Icons.pentagon_outlined,
                      color: Colors.green.shade600, size: 18),
                const SizedBox(width: 4),
                Icon(
                  op.isSynced
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_upload_outlined,
                  color: op.isSynced ? Colors.green : Colors.orange,
                  size: 20,
                ),
              ],
            ),
            onLongPress: () => _toggleSelectionMode(op.id!),
            onTap: isSelected
                ? () => _toggleSelectionMode(op.id!)
                : () => _abrirOpcoesOperacaoSilvi(op, operacoes),
            selected: isSelected,
          ),
        );
      },
    );
  }
}

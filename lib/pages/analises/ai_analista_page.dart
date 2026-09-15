import 'package:flutter/material.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/pilha_repository.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/silvi_repository.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/services/ai_validation_service.dart';

class AiAnalistaPage extends StatefulWidget {
  const AiAnalistaPage({super.key});

  @override
  State<AiAnalistaPage> createState() => _AiAnalistaPageState();
}

class _AiAnalistaPageState extends State<AiAnalistaPage> {
  final _aiService = AiValidationService();
  final _parcelaRepo = ParcelaRepository();
  final _cubagemRepo = CubagemRepository();
  final _pilhaRepo = PilhaRepository();
  final _silviRepo = SilviRepository();
  final _projetoRepo = ProjetoRepository();

  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  final List<_Mensagem> _mensagens = [];
  Map<String, dynamic>? _contexto;
  bool _carregandoContexto = true;
  bool _respondendo = false;

  static const _sugestoes = [
    'Qual projeto tem mais parcelas concluídas?',
    'Qual líder foi mais produtivo?',
    'Faça um resumo executivo de tudo',
    'Há talhões com cubagem pendente?',
    'Compare o volume colhido por fazenda',
  ];

  @override
  void initState() {
    super.initState();
    _carregarContexto();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _carregarContexto() async {
    setState(() => _carregandoContexto = true);

    try {
      final projetos = await _projetoRepo.getTodosOsProjetosParaGerente();
      final todasParcelas = await _parcelaRepo.getTodasAsParcelas();
      final todasCubagens = await _cubagemRepo.getTodasCubagens();
      final todasPilhas = await _pilhaRepo.getPilhasPorLideres(apenasNaoExportadas: false);
      final todasOperacoesSilvi = await _silviRepo.getTodasOperacoes();

      // Resumo de inventário por projeto
      final resumoProjetos = projetos.map((p) {
        final parcelas = todasParcelas.where((pa) => pa.projetoId == p.id).toList();
        final concluidas = parcelas.where((pa) =>
            pa.status == StatusParcela.concluida ||
            pa.status == StatusParcela.exportada).length;
        return {
          'projeto': p.nome,
          'total_parcelas': parcelas.length,
          'parcelas_concluidas': concluidas,
          'progresso_pct': parcelas.isEmpty ? 0 : ((concluidas / parcelas.length) * 100).round(),
        };
      }).toList();

      // Resumo de produtividade por líder (parcelas)
      final Map<String, int> parcelasPorLider = {};
      for (final p in todasParcelas.where((p) =>
          p.status == StatusParcela.concluida || p.status == StatusParcela.exportada)) {
        if (p.nomeLider != null && p.nomeLider!.isNotEmpty) {
          parcelasPorLider[p.nomeLider!] = (parcelasPorLider[p.nomeLider!] ?? 0) + 1;
        }
      }
      final topLideres = parcelasPorLider.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Resumo de cubagem
      final cubagensComDados = todasCubagens.where((c) => c.alturaTotal > 0).toList();
      final Map<String, int> cubagemPorTalhao = {};
      for (final c in cubagensComDados) {
        if (c.nomeTalhao.isNotEmpty) {
          cubagemPorTalhao[c.nomeTalhao] = (cubagemPorTalhao[c.nomeTalhao] ?? 0) + 1;
        }
      }

      // Resumo de colheita (pilhas)
      double volumeTotalPilhas = 0;
      final Map<String, double> volumePorFazendaPilha = {};
      final Map<String, double> volumePorSortimento = {};
      for (final pilha in todasPilhas) {
        final vol = pilha.volumeBruto ?? 0;
        volumeTotalPilhas += vol;
        final fazenda = pilha.nomeFazenda;
        if (fazenda != null && fazenda.isNotEmpty) {
          volumePorFazendaPilha[fazenda] = (volumePorFazendaPilha[fazenda] ?? 0) + vol;
        }
        if (pilha.sortimento.isNotEmpty) {
          volumePorSortimento[pilha.sortimento] =
              (volumePorSortimento[pilha.sortimento] ?? 0) + vol;
        }
      }

      // Resumo de silvicultura
      double areaTotalSilvi = 0;
      final Map<String, double> areaPorTipo = {};
      for (final op in todasOperacoesSilvi) {
        final area = op.areaAplicadaHa ?? 0;
        areaTotalSilvi += area;
        if (op.tipo.isNotEmpty) {
          areaPorTipo[op.tipo] = (areaPorTipo[op.tipo] ?? 0) + area;
        }
      }

      final contexto = {
        'data_consulta': DateTime.now().toIso8601String().substring(0, 10),
        'inventario': {
          'total_projetos': projetos.length,
          'total_parcelas': todasParcelas.length,
          'parcelas_concluidas': todasParcelas
              .where((p) => p.status == StatusParcela.concluida || p.status == StatusParcela.exportada)
              .length,
          'por_projeto': resumoProjetos,
          'top_lideres_por_parcelas': topLideres
              .take(5)
              .map((e) => {'lider': e.key, 'parcelas': e.value})
              .toList(),
        },
        'cubagem': {
          'total_arvores_cubadas': cubagensComDados.length,
          'arvores_por_talhao': cubagemPorTalhao,
        },
        'colheita': {
          'total_pilhas': todasPilhas.length,
          'volume_total_m3': double.parse(volumeTotalPilhas.toStringAsFixed(2)),
          'volume_por_fazenda_m3': volumePorFazendaPilha
              .map((k, v) => MapEntry(k, double.parse(v.toStringAsFixed(2)))),
          'volume_por_sortimento_m3': volumePorSortimento
              .map((k, v) => MapEntry(k, double.parse(v.toStringAsFixed(2)))),
        },
        'silvicultura': {
          'total_operacoes': todasOperacoesSilvi.length,
          'area_total_ha': double.parse(areaTotalSilvi.toStringAsFixed(2)),
          'area_por_tipo_ha': areaPorTipo
              .map((k, v) => MapEntry(k, double.parse(v.toStringAsFixed(2)))),
        },
      };

      if (mounted) {
        setState(() {
          _contexto = contexto;
          _carregandoContexto = false;
          _mensagens.add(_Mensagem(
            role: 'ai',
            text: 'Olá! Analisei todos os dados do sistema.\n\n'
                '📊 **${todasParcelas.length} parcelas** em ${projetos.length} projeto(s)\n'
                '🌲 **${cubagensComDados.length} árvores** cubadas\n'
                '🚛 **${volumeTotalPilhas.toStringAsFixed(1)} m³** colhidos em ${todasPilhas.length} pilhas\n'
                '🌱 **${areaTotalSilvi.toStringAsFixed(1)} ha** de silvicultura registrada\n\n'
                'Pode me fazer qualquer pergunta sobre esses dados.',
          ));
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _carregandoContexto = false;
          _mensagens.add(_Mensagem(
            role: 'ai',
            text: 'Erro ao carregar os dados do sistema. Verifique a conexão e tente novamente.',
          ));
        });
      }
    }
  }

  Future<void> _enviar(String texto) async {
    if (texto.trim().isEmpty || _contexto == null || _respondendo) return;
    _controller.clear();

    setState(() {
      _mensagens.add(_Mensagem(role: 'user', text: texto.trim()));
      _respondendo = true;
    });
    _scrollToBottom();

    final resposta = await _aiService.perguntarContextoGlobal(texto.trim(), _contexto!);

    if (mounted) {
      setState(() {
        _mensagens.add(_Mensagem(role: 'ai', text: resposta));
        _respondendo = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.auto_awesome, size: 18, color: cs.primary),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('IA Analista', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text('GeoForest AI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
            ],
          ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Recarregar dados',
            onPressed: _carregandoContexto ? null : () {
              setState(() {
                _mensagens.clear();
                _contexto = null;
              });
              _carregarContexto();
            },
          ),
        ],
      ),
      body: _carregandoContexto
          ? _buildCarregando()
          : Column(children: [
              Expanded(child: _buildChat()),
              _buildSugestoes(),
              _buildInput(),
            ]),
    );
  }

  Widget _buildCarregando() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Consolidando dados de todos os módulos…',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _buildChat() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: _mensagens.length + (_respondendo ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _mensagens.length) return _buildTypingIndicator();
        return _buildBolha(_mensagens[i]);
      },
    );
  }

  Widget _buildBolha(_Mensagem msg) {
    final isAi = msg.role == 'ai';
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: 10,
        left: isAi ? 0 : 48,
        right: isAi ? 48 : 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isAi) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.auto_awesome, size: 14, color: cs.primary),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isAi
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : cs.primary,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isAi ? 4 : 16),
                  bottomRight: Radius.circular(isAi ? 16 : 4),
                ),
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: isAi ? cs.onSurface : cs.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: cs.primaryContainer,
          child: Icon(Icons.auto_awesome, size: 14, color: cs.primary),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16), topRight: Radius.circular(16),
              bottomLeft: Radius.circular(4), bottomRight: Radius.circular(16),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _Dot(delay: 0),
            const SizedBox(width: 4),
            _Dot(delay: 200),
            const SizedBox(width: 4),
            _Dot(delay: 400),
          ]),
        ),
      ]),
    );
  }

  Widget _buildSugestoes() {
    if (_mensagens.length > 1) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: _sugestoes.length,
        itemBuilder: (_, i) => ActionChip(
          label: Text(_sugestoes[i], style: const TextStyle(fontSize: 12)),
          onPressed: _respondendo ? null : () => _enviar(_sugestoes[i]),
        ),
      ),
    );
  }

  Widget _buildInput() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_respondendo && _contexto != null,
              decoration: InputDecoration(
                hintText: 'Pergunte sobre os dados…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: _enviar,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _respondendo ? null : () => _enviar(_controller.text),
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(12),
            ),
            child: const Icon(Icons.send_rounded, size: 20),
          ),
        ]),
      ),
    );
  }
}

class _Mensagem {
  final String role;
  final String text;
  const _Mensagem({required this.role, required this.text});
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/silvi_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/silvi_model.dart';
import 'package:geoforestv1/pages/gerente/silvi_mapa_geral_page.dart';
import 'package:geoforestv1/services/export_service.dart';
import 'package:intl/intl.dart';

enum _Periodo {
  todos,
  hoje,
  semana,
  mes,
  mesPassado,
  personalizado;

  String get label => const {
        _Periodo.todos: 'Todos',
        _Periodo.hoje: 'Hoje',
        _Periodo.semana: 'Últimos 7 dias',
        _Periodo.mes: 'Este mês',
        _Periodo.mesPassado: 'Mês passado',
        _Periodo.personalizado: 'Personalizado',
      }[this]!;
}

class SilviDashboardPage extends StatefulWidget {
  const SilviDashboardPage({super.key});

  @override
  State<SilviDashboardPage> createState() => _SilviDashboardPageState();
}

class _SilviDashboardPageState extends State<SilviDashboardPage> {
  final _repo = SilviRepository();
  final _projetoRepo = ProjetoRepository();
  final _talhaoRepo = TalhaoRepository();
  final _exportService = ExportService();

  List<CentroideSilvi> _centroides = [];
  List<OperacaoSilvi> _operacoes = [];
  Map<int, String> _talhaoProjetoNome = {};
  bool _carregando = true;

  bool _invertOrdem = false;

  final Set<String> _tiposFiltro = {};
  final Set<String> _fazendasFiltro = {};
  final Set<String> _talhoesFiltro = {};
  final Set<String> _projetosFiltro = {};
  final Set<String> _lideresFiltro = {};
  List<String> _lideresDoDb = [];
  _Periodo _periodo = _Periodo.todos;
  DateTimeRange? _periodoPersonalizado;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final results = await Future.wait([
      _repo.getTodosCentroides(),
      _repo.getTodasOperacoes(),
      _projetoRepo.getTodosOsProjetosParaGerente(),
      _talhaoRepo.getTodosOsTalhoes(),
      _repo.getDistinctLideres(),
    ]);
    final cs = results[0] as List<CentroideSilvi>;
    final ops = results[1] as List<OperacaoSilvi>;
    final projetos = results[2] as List<Projeto>;
    final talhoes = results[3] as List;
    final lideresDb = results[4] as List<String>;

    final projetoMap = {for (final p in projetos) if (p.id != null) p.id!: p.nome};

    final talhaoProjetoNome = <int, String>{};
    for (final t in talhoes) {
      if (t.id != null && t.projetoId != null) {
        talhaoProjetoNome[t.id as int] = projetoMap[t.projetoId] ?? '';
      }
    }

    if (mounted) {
      setState(() {
        _centroides = cs;
        _operacoes = ops;
        _talhaoProjetoNome = talhaoProjetoNome;
        _lideresDoDb = lideresDb;
        _carregando = false;
      });
    }
  }

  // ── Período helpers ───────────────────────────────────────────────────────

  bool _dataPassaPeriodo(DateTime d) {
    final agora = DateTime.now();
    switch (_periodo) {
      case _Periodo.todos:
        return true;
      case _Periodo.hoje:
        return d.year == agora.year && d.month == agora.month && d.day == agora.day;
      case _Periodo.semana:
        return d.isAfter(agora.subtract(const Duration(days: 7)));
      case _Periodo.mes:
        return d.year == agora.year && d.month == agora.month;
      case _Periodo.mesPassado:
        final mp = DateTime(agora.year, agora.month - 1);
        return d.year == mp.year && d.month == mp.month;
      case _Periodo.personalizado:
        if (_periodoPersonalizado == null) return true;
        return !d.isBefore(_periodoPersonalizado!.start) &&
            !d.isAfter(_periodoPersonalizado!.end.add(const Duration(days: 1)));
    }
  }

  String get _periodoLabel {
    if (_periodo == _Periodo.personalizado && _periodoPersonalizado != null) {
      final fmt = DateFormat('dd/MM');
      return '${fmt.format(_periodoPersonalizado!.start)} – ${fmt.format(_periodoPersonalizado!.end)}';
    }
    return _periodo.label;
  }

  // ── Computed ──────────────────────────────────────────────────────────────

  Map<int, List<OperacaoSilvi>> get _opsPorTalhao {
    final map = <int, List<OperacaoSilvi>>{};
    for (final op in _operacoes) {
      if (op.talhaoId != null) (map[op.talhaoId!] ??= []).add(op);
    }
    return map;
  }

  bool _passaFiltros(CentroideSilvi c) {
    if (_projetosFiltro.isNotEmpty) {
      final proj = c.talhaoId != null ? (_talhaoProjetoNome[c.talhaoId] ?? '') : '';
      if (!_projetosFiltro.contains(proj)) return false;
    }
    if (_tiposFiltro.isNotEmpty) {
      final opsForTalhao = c.talhaoId != null ? (_opsPorTalhao[c.talhaoId] ?? const <OperacaoSilvi>[]) : const <OperacaoSilvi>[];
      final match = c.operacoesPlanejadas.any((op) => _tiposFiltro.contains(op.tipo)) ||
          opsForTalhao.any((op) => _tiposFiltro.contains(op.tipo));
      if (!match) return false;
    }
    if (_fazendasFiltro.isNotEmpty && !_fazendasFiltro.contains(c.nomeFazenda)) return false;
    if (_talhoesFiltro.isNotEmpty && !_talhoesFiltro.contains(c.nomeTalhao)) return false;
    return true;
  }

  bool _passaFiltrosOp(OperacaoSilvi o) {
    if (_fazendasFiltro.isNotEmpty && !_fazendasFiltro.contains(o.nomeFazenda ?? '')) return false;
    if (_talhoesFiltro.isNotEmpty && !_talhoesFiltro.contains(o.nomeTalhao ?? '')) return false;
    if (_tiposFiltro.isNotEmpty && !_tiposFiltro.contains(o.tipo)) return false;
    if (_lideresFiltro.isNotEmpty && !_lideresFiltro.contains(o.nomeLider ?? '')) return false;
    if (_periodo != _Periodo.todos) {
      if (o.dataExecucao == null) return false;
      final d = DateTime.tryParse(o.dataExecucao!);
      if (d == null || !_dataPassaPeriodo(d)) return false;
    }
    return true;
  }

  // ── Disponíveis ───────────────────────────────────────────────────────────

  List<String> get _projetosDisponiveis {
    final nomes = <String>{};
    for (final c in _centroides) {
      final nome = c.talhaoId != null ? (_talhaoProjetoNome[c.talhaoId] ?? '') : '';
      if (nome.isNotEmpty) nomes.add(nome);
    }
    return nomes.toList()..sort();
  }

  List<String> get _fazendasDisponiveis {
    final nomes = <String>{};
    for (final c in _centroides) {
      if (_projetosFiltro.isNotEmpty) {
        final proj = c.talhaoId != null ? (_talhaoProjetoNome[c.talhaoId] ?? '') : '';
        if (!_projetosFiltro.contains(proj)) continue;
      }
      nomes.add(c.nomeFazenda);
    }
    return nomes.toList()..sort();
  }

  List<String> get _talhoesDisponiveis {
    final nomes = <String>{};
    for (final c in _centroides) {
      if (_projetosFiltro.isNotEmpty) {
        final proj = c.talhaoId != null ? (_talhaoProjetoNome[c.talhaoId] ?? '') : '';
        if (!_projetosFiltro.contains(proj)) continue;
      }
      if (_fazendasFiltro.isNotEmpty && !_fazendasFiltro.contains(c.nomeFazenda)) continue;
      nomes.add(c.nomeTalhao);
    }
    return nomes.toList()..sort();
  }

  List<String> get _lideresDisponiveis {
    final nomes = <String>{..._lideresDoDb};
    for (final op in _operacoes) {
      if (_fazendasFiltro.isNotEmpty && !_fazendasFiltro.contains(op.nomeFazenda ?? '')) continue;
      if (_talhoesFiltro.isNotEmpty && !_talhoesFiltro.contains(op.nomeTalhao ?? '')) continue;
      if (op.nomeLider != null && op.nomeLider!.isNotEmpty) nomes.add(op.nomeLider!);
    }
    return nomes.toList()..sort();
  }

  Set<String> get _tiposDisponiveis {
    final tipos = <String>{};
    for (final c in _centroides) {
      if (!_passaFiltros(c)) continue;
      for (final op in c.operacoesPlanejadas) { tipos.add(op.tipo); }
    }
    for (final op in _operacoes) {
      if (!_passaFiltrosOp(op)) continue;
      tipos.add(op.tipo);
    }
    return tipos;
  }

  List<_FazendaData> get _fazendas {
    final opsMap = _opsPorTalhao;
    final byFazenda = <String, List<_TalhaoData>>{};

    for (final c in _centroides) {
      if (!_passaFiltros(c)) continue;
      final tudo = List<OperacaoSilvi>.from(opsMap[c.talhaoId] ?? []);
      tudo.sort((a, b) => (b.dataExecucao ?? '').compareTo(a.dataExecucao ?? ''));
      final filtradas = tudo.where(_passaFiltrosOp).toList();
      (byFazenda[c.nomeFazenda] ??= []).add(_TalhaoData(
        centroide: c,
        todasOperacoes: tudo,
        operacoesFiltradas: filtradas,
      ));
    }

    for (final lista in byFazenda.values) {
      lista.sort((a, b) {
        final aIni = a.todasOperacoes.isNotEmpty;
        final bIni = b.todasOperacoes.isNotEmpty;
        if (aIni != bIni) return _invertOrdem ? (aIni ? 1 : -1) : (aIni ? -1 : 1);
        if (aIni) {
          final aDate = a.todasOperacoes.first.dataExecucao ?? '';
          final bDate = b.todasOperacoes.first.dataExecucao ?? '';
          if (aDate != bDate) return bDate.compareTo(aDate);
        }
        return a.centroide.nomeTalhao.compareTo(b.centroide.nomeTalhao);
      });
    }

    return byFazenda.entries
        .map((e) => _FazendaData(nome: e.key, talhoes: e.value))
        .toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));
  }

  double _totalPlan(String? tipo) {
    double t = 0;
    for (final c in _centroides) {
      if (!_passaFiltros(c)) continue;
      for (final op in c.operacoesPlanejadas) {
        if (tipo == null || op.tipo == tipo) t += op.areaHa ?? 0;
      }
    }
    return t;
  }

  double _totalAplic(String? tipo) => _operacoes
      .where((o) => tipo == null || o.tipo == tipo)
      .where(_passaFiltrosOp)
      .fold(0.0, (s, o) => s + (o.areaAplicadaHa ?? 0));

  double get _totalPlanGlobal =>
      _tiposFiltro.isEmpty ? _totalPlan(null) : _tiposFiltro.fold(0.0, (s, t) => s + _totalPlan(t));

  double get _totalAplicGlobal =>
      _tiposFiltro.isEmpty ? _totalAplic(null) : _tiposFiltro.fold(0.0, (s, t) => s + _totalAplic(t));

  // ── Filtros ───────────────────────────────────────────────────────────────

  Widget _buildFiltros() {
    return Column(
      children: [
        Row(children: [
          Expanded(child: _buildChip('Projeto', _projetosDisponiveis, _projetosFiltro, onChanged: () {
            _fazendasFiltro.removeWhere((f) => !_fazendasDisponiveis.contains(f));
            _talhoesFiltro.removeWhere((t) => !_talhoesDisponiveis.contains(t));
          })),
          const SizedBox(width: 8),
          Expanded(child: _buildChip('Fazenda', _fazendasDisponiveis, _fazendasFiltro, onChanged: () {
            _talhoesFiltro.removeWhere((t) => !_talhoesDisponiveis.contains(t));
          })),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _buildChip('Talhão', _talhoesDisponiveis, _talhoesFiltro)),
          const SizedBox(width: 8),
          Expanded(child: _buildPeriodoChip()),
        ]),
        const SizedBox(height: 6),
        _buildChip('Líder', _lideresDisponiveis, _lideresFiltro),
      ],
    );
  }

  Widget _buildChip(String label, List<String> disponiveis, Set<String> selecionados, {VoidCallback? onChanged}) {
    if (disponiveis.isEmpty) return const SizedBox.shrink();
    final txt = selecionados.isEmpty
        ? 'Todos'
        : selecionados.length == 1
            ? selecionados.first
            : '${selecionados.length} selecionados';
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        final tmp = Set<String>.from(selecionados);
        String busca = '';
        showDialog<void>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDlg) {
              final filtrados = busca.isEmpty
                  ? disponiveis
                  : disponiveis
                      .where((v) => v.toLowerCase().contains(busca.toLowerCase()))
                      .toList();
              return AlertDialog(
                title: Text('Filtrar por $label'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Buscar...',
                          prefixIcon: Icon(Icons.search, size: 18),
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                        onChanged: (v) => setDlg(() => busca = v),
                      ),
                      const SizedBox(height: 6),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            if (busca.isEmpty) ...[
                              CheckboxListTile(
                                title: const Text('Todos', style: TextStyle(fontWeight: FontWeight.bold)),
                                value: tmp.isEmpty,
                                onChanged: (_) => setDlg(() => tmp.clear()),
                              ),
                              const Divider(height: 1),
                            ],
                            ...filtrados.map((v) => CheckboxListTile(
                                  title: Text(v),
                                  value: tmp.contains(v),
                                  onChanged: (on) => setDlg(() => on == true ? tmp.add(v) : tmp.remove(v)),
                                )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      setState(() { selecionados.clear(); onChanged?.call(); });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Limpar'),
                  ),
                  FilledButton(
                    onPressed: () {
                      setState(() { selecionados..clear()..addAll(tmp); onChanged?.call(); });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Aplicar'),
                  ),
                ],
              );
            },
          ),
        );
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          isDense: true,
        ),
        child: Row(children: [
          Expanded(child: Text(txt, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          const Icon(Icons.arrow_drop_down, size: 20),
        ]),
      ),
    );
  }

  Widget _buildPeriodoChip() {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final picked = await showModalBottomSheet<_Periodo>(
          context: context,
          builder: (_) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Período', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              for (final p in _Periodo.values)
                ListTile(
                  title: Text(p.label),
                  trailing: _periodo == p ? Icon(Icons.check, color: Colors.green.shade700) : null,
                  onTap: () => Navigator.pop(context, p),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
        if (picked == null || !mounted) return;
        if (picked == _Periodo.personalizado) {
          final range = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2020),
            lastDate: DateTime.now(),
            initialDateRange: _periodoPersonalizado,
          );
          if (range != null && mounted) {
            setState(() { _periodo = _Periodo.personalizado; _periodoPersonalizado = range; });
          }
        } else {
          setState(() { _periodo = picked; _periodoPersonalizado = null; });
        }
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Período',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          isDense: true,
        ),
        child: Row(children: [
          Expanded(child: Text(_periodoLabel, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          const Icon(Icons.arrow_drop_down, size: 20),
        ]),
      ),
    );
  }

  (DateTime?, DateTime?) get _periodoDates {
    final agora = DateTime.now();
    switch (_periodo) {
      case _Periodo.todos:
        return (null, null);
      case _Periodo.hoje:
        final hoje = DateTime(agora.year, agora.month, agora.day);
        return (hoje, hoje);
      case _Periodo.semana:
        return (agora.subtract(const Duration(days: 7)), agora);
      case _Periodo.mes:
        return (DateTime(agora.year, agora.month, 1), agora);
      case _Periodo.mesPassado:
        final inicio = DateTime(agora.year, agora.month - 1, 1);
        final fim = DateTime(agora.year, agora.month, 0);
        return (inicio, fim);
      case _Periodo.personalizado:
        return (_periodoPersonalizado?.start, _periodoPersonalizado?.end);
    }
  }

  Widget _buildExportarButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.download_outlined, size: 18),
        label: const Text('Exportar Silvicultura'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          side: BorderSide(color: Colors.green.shade700),
          foregroundColor: Colors.green.shade700,
        ),
        onPressed: () {
          final (di, df) = _periodoDates;
          _exportService.exportarOperacoesSilviComFiltros(
            context,
            fazendas: _fazendasFiltro.isNotEmpty ? Set.from(_fazendasFiltro) : null,
            talhoes: _talhoesFiltro.isNotEmpty ? Set.from(_talhoesFiltro) : null,
            tipos: _tiposFiltro.isNotEmpty ? Set.from(_tiposFiltro) : null,
            lideres: _lideresFiltro.isNotEmpty ? Set.from(_lideresFiltro) : null,
            dataInicio: di,
            dataFim: df,
          );
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());

    if (_centroides.isEmpty && _operacoes.isEmpty) return _buildEmpty();

    final fazendas = _fazendas;
    final plan = _totalPlanGlobal;
    final aplic = _totalAplicGlobal;
    final pct = plan > 0 ? (aplic / plan).clamp(0.0, 1.0) : null;
    final tipos = _tiposDisponiveis.toList()..sort();

    return RefreshIndicator(
      onRefresh: _carregar,
      child: CustomScrollView(
        slivers: [
          // ── Filtros ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: _buildFiltros(),
            ),
          ),

          // ── KPIs globais ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: Column(children: [
                _buildKpisGlobais(plan, aplic, pct),
                const SizedBox(height: 8),
                if (tipos.isNotEmpty) _buildKpisTipo(tipos),
              ]),
            ),
          ),

          // ── Botão mapa geral + Exportar + toggle ordem ───────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(children: [
                _buildMapaBanner(),
                const SizedBox(height: 8),
                _buildExportarButton(),
                const SizedBox(height: 8),
                _buildToggleOrdem(),
              ]),
            ),
          ),

          // ── Divisor ───────────────────────────────────────────────────────
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Divider(height: 1),
            ),
          ),

          // ── Lista de fazendas ─────────────────────────────────────────────
          fazendas.isEmpty
              ? const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nenhum talhão encontrado com os filtros selecionados.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _buildFazendaCard(fazendas[i]),
                      childCount: fazendas.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  // ── Seções ────────────────────────────────────────────────────────────────

  Widget _buildKpisGlobais(double plan, double aplic, double? pct) {
    final pctColor = pct == null
        ? Colors.grey
        : pct >= 0.9
            ? Colors.green.shade700
            : pct >= 0.6
                ? Colors.orange.shade700
                : Colors.red.shade600;
    return Row(children: [
      _KpiCard(label: 'Planejado', value: '${plan.toStringAsFixed(1)} ha', icon: Icons.map_outlined, color: Colors.blue.shade700),
      const SizedBox(width: 8),
      _KpiCard(label: 'Executado', value: '${aplic.toStringAsFixed(1)} ha', icon: Icons.check_circle_outline, color: Colors.green.shade700),
      const SizedBox(width: 8),
      _KpiCard(label: 'Avanço', value: pct != null ? '${(pct * 100).toStringAsFixed(1)}%' : '—', icon: Icons.bar_chart_outlined, color: pctColor),
    ]);
  }

  Widget _buildKpisTipo(List<String> tipos) {
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: tipos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final tipo = tipos[i];
          final t = OperacaoSilviTipo.fromString(tipo);
          final plan = _totalPlan(tipo);
          final aplic = _totalAplic(tipo);
          final pct = plan > 0 ? (aplic / plan).clamp(0.0, 1.0) : null;
          final sel = _tiposFiltro.contains(tipo);
          return GestureDetector(
            onTap: () => setState(() { sel ? _tiposFiltro.remove(tipo) : _tiposFiltro.add(tipo); }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 148,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: sel
                    ? t.color.withValues(alpha: 0.14)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? t.color : Colors.transparent, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(children: [
                    Icon(t.icon, size: 13, color: t.color),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(t.label,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (sel) Icon(Icons.check_circle, size: 12, color: t.color),
                  ]),
                  const SizedBox(height: 3),
                  Text(
                    plan > 0
                        ? '${aplic.toStringAsFixed(1)} / ${plan.toStringAsFixed(1)} ha'
                        : '${aplic.toStringAsFixed(1)} ha exec.',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                  if (pct != null) ...[
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 5,
                        backgroundColor: Colors.grey.shade200,
                        color: t.color,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMapaBanner() {
    final comPoligono = _operacoes.where((o) => o.areaGeoJson != null).length;
    return FilledButton.tonalIcon(
      onPressed: comPoligono == 0
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SilviMapaGeralPage(operacoes: _operacoes, centroides: _centroides),
                ),
              ),
      icon: const Icon(Icons.map_outlined),
      label: Text(comPoligono == 0 ? 'Nenhuma área desenhada ainda' : 'Mapa geral · $comPoligono área(s)'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 44),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey.shade100,
        disabledForegroundColor: Colors.grey,
      ),
    );
  }

  Widget _buildToggleOrdem() {
    return GestureDetector(
      onTap: () => setState(() => _invertOrdem = !_invertOrdem),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(_invertOrdem ? Icons.arrow_downward : Icons.arrow_upward, size: 15, color: Colors.green.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _invertOrdem ? 'Sem início no topo  ·  iniciados abaixo' : 'Iniciados no topo  ·  sem início abaixo',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Text('Inverter', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _buildFazendaCard(_FazendaData fazenda) {
    double planFaz = 0, aplicFaz = 0;
    for (final t in fazenda.talhoes) {
      for (final op in t.centroide.operacoesPlanejadas) {
        if (_tiposFiltro.isEmpty || _tiposFiltro.contains(op.tipo)) planFaz += op.areaHa ?? 0;
      }
      aplicFaz += t.operacoesFiltradas.fold(0.0, (s, o) => s + (o.areaAplicadaHa ?? 0));
    }
    final pct = planFaz > 0 ? (aplicFaz / planFaz).clamp(0.0, 1.0) : null;
    final iniciados = fazenda.talhoes.where((t) => t.todasOperacoes.isNotEmpty).length;
    final total = fazenda.talhoes.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade50,
          child: Icon(Icons.domain_outlined, color: Colors.green.shade700),
        ),
        title: Text(fazenda.nome.isNotEmpty ? fazenda.nome : 'Fazenda desconhecida',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('$total talhão(ões) · $iniciados iniciado(s)', style: const TextStyle(fontSize: 12)),
        trailing: pct != null ? _ProgressChip(pct: pct) : null,
        children: fazenda.talhoes.map(_buildTalhaoExpansion).toList(),
      ),
    );
  }

  Widget _buildTalhaoExpansion(_TalhaoData t) {
    final ops = t.operacoesFiltradas;
    final iniciado = t.todasOperacoes.isNotEmpty;
    final areaTotalHa = t.centroide.areaTotalHa;

    double planTal = 0;
    for (final op in t.centroide.operacoesPlanejadas) {
      if (_tiposFiltro.isEmpty || _tiposFiltro.contains(op.tipo)) planTal += op.areaHa ?? 0;
    }
    final aplicTal = ops.fold(0.0, (s, o) => s + (o.areaAplicadaHa ?? 0));
    final pct = planTal > 0 ? (aplicTal / planTal).clamp(0.0, 1.0) : null;

    final ultimaOp = ops.isNotEmpty ? ops.first : null;
    final dataUltima = ultimaOp?.dataExecucao != null
        ? DateFormat('dd/MM/yy').format(DateTime.tryParse(ultimaOp!.dataExecucao!) ?? DateTime.now())
        : null;

    return ExpansionTile(
      tilePadding: const EdgeInsets.only(left: 56, right: 16),
      leading: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: iniciado ? Colors.green.shade500 : Colors.grey.shade300,
        ),
      ),
      title: Text(t.centroide.nomeTalhao, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (areaTotalHa != null)
            Text('${areaTotalHa.toStringAsFixed(0)} ha total', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (!iniciado)
            const Text('Sem operações registradas', style: TextStyle(fontSize: 11, color: Colors.grey))
          else
            Text(
              '${ops.length} op(s)${dataUltima != null ? "  ·  última $dataUltima" : ""}',
              style: const TextStyle(fontSize: 11),
            ),
          if (pct != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 5,
                  backgroundColor: Colors.grey.shade200,
                  color: pct >= 1.0 ? Colors.green : Colors.green.shade600,
                ),
              ),
            ),
        ],
      ),
      trailing: pct != null
          ? Text(
              '${(pct * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: pct >= 1.0 ? Colors.green.shade700 : Colors.orange.shade700,
              ),
            )
          : null,
      children: ops.isEmpty
          ? [
              const ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 72),
                dense: true,
                title: Text('Nenhuma operação registrada.', style: TextStyle(color: Colors.grey, fontSize: 12)),
              )
            ]
          : ops.map(_buildOpRow).toList(),
    );
  }

  Widget _buildOpRow(OperacaoSilvi op) {
    final t = OperacaoSilviTipo.fromString(op.tipo);
    final dt = op.dataExecucao != null ? DateTime.tryParse(op.dataExecucao!) : null;
    final dataStr = dt != null ? DateFormat('dd/MM/yyyy').format(dt) : '—';
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 72, right: 16),
      dense: true,
      leading: Icon(t.icon, color: t.color, size: 17),
      title: Text(t.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      subtitle: Text(dataStr, style: const TextStyle(fontSize: 11)),
      trailing: op.areaAplicadaHa != null
          ? Text(
              '${op.areaAplicadaHa!.toStringAsFixed(2)} ha',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.color),
            )
          : null,
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.eco_outlined, size: 64, color: Colors.green.shade200),
          const SizedBox(height: 12),
          const Text('Nenhuma OS de silvicultura importada.', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
            'Importe um arquivo CSV de OS Silvicultura para começar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// ── Data helpers ──────────────────────────────────────────────────────────────

class _TalhaoData {
  final CentroideSilvi centroide;
  final List<OperacaoSilvi> todasOperacoes;
  final List<OperacaoSilvi> operacoesFiltradas;

  _TalhaoData({required this.centroide, required this.todasOperacoes, required this.operacoesFiltradas});
}

class _FazendaData {
  final String nome;
  final List<_TalhaoData> talhoes;
  _FazendaData({required this.nome, required this.talhoes});
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;

  const _KpiCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          ),
        ),
      );
}

class _ProgressChip extends StatelessWidget {
  final double pct;
  const _ProgressChip({required this.pct});

  @override
  Widget build(BuildContext context) {
    final color = pct >= 1.0
        ? Colors.green.shade700
        : pct >= 0.6
            ? Colors.orange.shade700
            : Colors.red.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${(pct * 100).toStringAsFixed(0)}%',
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}

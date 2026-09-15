import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geoforestv1/data/repositories/estoque_repository.dart';
import 'package:geoforestv1/data/repositories/pilha_repository.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/models/estoque_saida_model.dart';
import 'package:geoforestv1/models/pilha_madeira_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/pages/pilhas/estoque_saida_page.dart';
import 'package:geoforestv1/pages/pilhas/pilhas_map_page.dart';
import 'package:geoforestv1/services/export_service.dart';

enum _Periodo {
  todos, hoje, semana, mes, mesPassado, personalizado;

  String get label => const {
    _Periodo.todos: 'Todos',
    _Periodo.hoje: 'Hoje',
    _Periodo.semana: 'Últimos 7 dias',
    _Periodo.mes: 'Este mês',
    _Periodo.mesPassado: 'Mês passado',
    _Periodo.personalizado: 'Personalizado',
  }[this]!;
}

class PilhasDashboardPage extends StatefulWidget {
  const PilhasDashboardPage({super.key});

  @override
  State<PilhasDashboardPage> createState() => _PilhasDashboardPageState();
}

class _PilhasDashboardPageState extends State<PilhasDashboardPage> {
  final _repo = PilhaRepository();
  final _estoqueRepo = EstoqueRepository();
  final _talhaoRepo = TalhaoRepository();
  final _projetoRepo = ProjetoRepository();
  final _exportService = ExportService();
  final _nf2 = NumberFormat('0.00', 'pt_BR');
  final _nf0 = NumberFormat('0', 'pt_BR');
  final _nf1 = NumberFormat('0.0', 'pt_BR');

  List<PilhaMadeira> _pilhas = [];
  List<EstoqueSaida> _estoques = [];
  Map<int, CentroidePilha> _centroidesMap = {};
  Map<int, String> _talhaoProjetoNome = {};
  bool _loading = true;

  final Set<String> _projetosFiltro = {};
  final Set<String> _sortimentosFiltro = {};
  final Set<String> _fazendasFiltro = {};
  final Set<String> _talhoesFiltro = {};
  final Set<String> _lideresFiltro = {};
  final Set<String> _caminhoesFiltro = {};
  List<String> _lideresDoDb = [];
  _Periodo _periodo = _Periodo.todos;
  DateTimeRange? _periodoPersonalizado;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _repo.getPilhasPorLideres(apenasNaoExportadas: false),
      _estoqueRepo.getTodosEstoques(),
      _repo.getTodosCentroides(),
      _projetoRepo.getTodosOsProjetosParaGerente(),
      _talhaoRepo.getTodosOsTalhoes(),
      _repo.getDistinctLideres(),
    ]);
    final todas = results[0] as List<PilhaMadeira>;
    final todosEstoques = results[1] as List<EstoqueSaida>;
    final todosCentroides = results[2] as List<CentroidePilha>;
    final projetos = results[3] as List;
    final talhoes = results[4] as List;
    final lideresDb = (results[5] as Set<String>).toList()..sort();

    final projetoMap = {for (final p in projetos) if ((p as dynamic).id != null) p.id as int: p.nome as String};

    final talhaoProjetoNome = <int, String>{};
    for (final t in talhoes) {
      final td = t as dynamic;
      if (td.id != null && td.projetoId != null) {
        talhaoProjetoNome[td.id as int] = projetoMap[td.projetoId] ?? '';
      }
    }
    final centroidesMap = <int, CentroidePilha>{
      for (final c in todosCentroides)
        if (c.talhaoId != null) c.talhaoId!: c,
    };

    if (mounted) {
      setState(() {
        _pilhas = todas;
        _estoques = todosEstoques;
        _centroidesMap = centroidesMap;
        _talhaoProjetoNome = talhaoProjetoNome;
        _lideresDoDb = lideresDb;
        _loading = false;
      });
    }
  }

  bool _dataPassaPeriodo(DateTime d) {
    final agora = DateTime.now();
    switch (_periodo) {
      case _Periodo.todos: return true;
      case _Periodo.hoje: return d.year == agora.year && d.month == agora.month && d.day == agora.day;
      case _Periodo.semana: return d.isAfter(agora.subtract(const Duration(days: 7)));
      case _Periodo.mes: return d.year == agora.year && d.month == agora.month;
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

  bool _pilhaPassaFiltros(PilhaMadeira p) {
    if (_projetosFiltro.isNotEmpty) {
      final proj = p.talhaoId != null ? (_talhaoProjetoNome[p.talhaoId] ?? '') : '';
      if (!_projetosFiltro.contains(proj)) return false;
    }
    if (_sortimentosFiltro.isNotEmpty && !_sortimentosFiltro.contains(p.sortimento)) return false;
    if (_caminhoesFiltro.isNotEmpty && !_caminhoesFiltro.contains(p.sortimento)) return false;
    if (_fazendasFiltro.isNotEmpty && !_fazendasFiltro.contains(p.nomeFazenda ?? '')) return false;
    if (_talhoesFiltro.isNotEmpty && !_talhoesFiltro.contains(p.nomeTalhao ?? '')) return false;
    if (_lideresFiltro.isNotEmpty && !_lideresFiltro.contains(p.nomeLider ?? '')) return false;
    if (_periodo != _Periodo.todos) {
      if (p.dataColeta == null || !_dataPassaPeriodo(p.dataColeta!)) return false;
    }
    return true;
  }

  bool _estoquePassaFiltros(EstoqueSaida e) {
    if (_projetosFiltro.isNotEmpty) {
      final proj = e.talhaoId != null ? (_talhaoProjetoNome[e.talhaoId] ?? '') : '';
      if (!_projetosFiltro.contains(proj)) return false;
    }
    if (_sortimentosFiltro.isNotEmpty && !_sortimentosFiltro.contains(e.sortimento)) return false;
    if (_fazendasFiltro.isNotEmpty && !_fazendasFiltro.contains(e.nomeFazenda)) return false;
    if (_talhoesFiltro.isNotEmpty && !_talhoesFiltro.contains(e.nomeTalhao)) return false;
    if (_caminhoesFiltro.isNotEmpty && !_caminhoesFiltro.contains(e.sortimento)) return false;
    return true;
  }

  List<PilhaMadeira> get _pilhasFiltradas => _pilhas.where(_pilhaPassaFiltros).toList();
  List<EstoqueSaida> get _estoquesFiltrados => _estoques.where(_estoquePassaFiltros).toList();

  List<String> get _projetosDisponiveis {
    final nomes = <String>{};
    for (final p in _pilhas) {
      final nome = p.talhaoId != null ? (_talhaoProjetoNome[p.talhaoId] ?? '') : '';
      if (nome.isNotEmpty) nomes.add(nome);
    }
    return nomes.toList()..sort();
  }

  List<String> get _sortimentosDisponiveis {
    final nomes = <String>{};
    for (final p in _pilhas) {
      if (_projetosFiltro.isNotEmpty) {
        final proj = p.talhaoId != null ? (_talhaoProjetoNome[p.talhaoId] ?? '') : '';
        if (!_projetosFiltro.contains(proj)) continue;
      }
      if (p.sortimento.isNotEmpty) nomes.add(p.sortimento);
    }
    for (final e in _estoques) {
      if (_projetosFiltro.isNotEmpty) {
        final proj = e.talhaoId != null ? (_talhaoProjetoNome[e.talhaoId] ?? '') : '';
        if (!_projetosFiltro.contains(proj)) continue;
      }
      if (e.sortimento.isNotEmpty) nomes.add(e.sortimento);
    }
    return nomes.toList()..sort();
  }

  List<String> get _sortimentosEstoque {
    final nomes = <String>{};
    for (final e in _estoques) {
      if (e.sortimento.isNotEmpty) nomes.add(e.sortimento);
    }
    return nomes.toList()..sort();
  }

  List<String> get _fazendasDisponiveis {
    final nomes = <String>{};
    for (final p in _pilhas) {
      if (_projetosFiltro.isNotEmpty) {
        final proj = p.talhaoId != null ? (_talhaoProjetoNome[p.talhaoId] ?? '') : '';
        if (!_projetosFiltro.contains(proj)) continue;
      }
      if (_sortimentosFiltro.isNotEmpty && !_sortimentosFiltro.contains(p.sortimento)) continue;
      if (p.nomeFazenda != null && p.nomeFazenda!.isNotEmpty) nomes.add(p.nomeFazenda!);
    }
    for (final e in _estoques) {
      if (_projetosFiltro.isNotEmpty) {
        final proj = e.talhaoId != null ? (_talhaoProjetoNome[e.talhaoId] ?? '') : '';
        if (!_projetosFiltro.contains(proj)) continue;
      }
      if (e.nomeFazenda.isNotEmpty) nomes.add(e.nomeFazenda);
    }
    return nomes.toList()..sort();
  }

  List<String> get _talhoesDisponiveis {
    final nomes = <String>{};
    for (final p in _pilhas) {
      if (_projetosFiltro.isNotEmpty) {
        final proj = p.talhaoId != null ? (_talhaoProjetoNome[p.talhaoId] ?? '') : '';
        if (!_projetosFiltro.contains(proj)) continue;
      }
      if (_sortimentosFiltro.isNotEmpty && !_sortimentosFiltro.contains(p.sortimento)) continue;
      if (_fazendasFiltro.isNotEmpty && !_fazendasFiltro.contains(p.nomeFazenda ?? '')) continue;
      if (p.nomeTalhao != null && p.nomeTalhao!.isNotEmpty) nomes.add(p.nomeTalhao!);
    }
    return nomes.toList()..sort();
  }

  List<String> get _lideresDisponiveis {
    final nomes = <String>{..._lideresDoDb};
    for (final p in _pilhas) {
      if (_fazendasFiltro.isNotEmpty && !_fazendasFiltro.contains(p.nomeFazenda ?? '')) continue;
      if (_talhoesFiltro.isNotEmpty && !_talhoesFiltro.contains(p.nomeTalhao ?? '')) continue;
      if (p.nomeLider != null && p.nomeLider!.isNotEmpty) nomes.add(p.nomeLider!);
    }
    return nomes.toList()..sort();
  }

  List<String> get _fazendas => _fazendasDisponiveis;

  SortimentoConfig? _getSortimentoConfig(PilhaMadeira p) {
    if (p.talhaoId == null) return null;
    final centroide = _centroidesMap[p.talhaoId];
    if (centroide == null) return null;
    try {
      return centroide.sortimentos.firstWhere((s) => s.nome == p.sortimento);
    } catch (_) {
      return null;
    }
  }

  double? _getVolEsperado(int? talhaoId, String sortimento) {
    if (talhaoId == null) return null;
    final centroide = _centroidesMap[talhaoId];
    if (centroide == null) return null;
    try {
      return centroide.sortimentos.firstWhere((s) => s.nome == sortimento).volumeEsperadoM3;
    } catch (_) {
      return null;
    }
  }

  // Agrupa por fazenda+talhão+sortimento (pilhas + estoques)
  Map<String, _ResumoSortimento> get _resumoPorSortimento {
    final map = <String, _ResumoSortimento>{};
    for (final p in _pilhasFiltradas) {
      final key = '${p.nomeFazenda ?? ''}|${p.nomeTalhao ?? ''}|${p.sortimento}';
      map.putIfAbsent(key, () => _ResumoSortimento(
        fazenda: p.nomeFazenda ?? '—',
        talhao: p.nomeTalhao ?? '—',
        sortimento: p.sortimento,
        volumeEsperado: _getSortimentoConfig(p)?.volumeEsperadoM3,
      ));
      map[key]!.adicionar(p);
    }
    for (final e in _estoquesFiltrados) {
      final key = '${e.nomeFazenda}|${e.nomeTalhao}|${e.sortimento}';
      map.putIfAbsent(key, () => _ResumoSortimento(
        fazenda: e.nomeFazenda.isEmpty ? '—' : e.nomeFazenda,
        talhao: e.nomeTalhao.isEmpty ? '—' : e.nomeTalhao,
        sortimento: e.sortimento,
        volumeEsperado: _getVolEsperado(e.talhaoId, e.sortimento),
      ));
      map[key]!.adicionarEstoque(e);
    }
    return map;
  }

  // Agrupa por fazenda, somando volume esperado de cada talhão+sortimento único
  Map<String, _ResumoFazenda> get _resumoPorFazenda {
    final map = <String, _ResumoFazenda>{};
    final vistos = <String>{};
    for (final p in _pilhasFiltradas) {
      final fazKey = p.nomeFazenda ?? '—';
      map.putIfAbsent(fazKey, () => _ResumoFazenda(fazenda: fazKey));
      map[fazKey]!.adicionarPilha(p);
      final sortKey = '$fazKey|${p.talhaoId}|${p.sortimento}';
      if (vistos.add(sortKey)) {
        final vol = _getSortimentoConfig(p)?.volumeEsperadoM3;
        if (vol != null && vol > 0) map[fazKey]!.volumeEsperado += vol;
      }
    }
    for (final e in _estoquesFiltrados) {
      final fazKey = e.nomeFazenda.isEmpty ? '—' : e.nomeFazenda;
      map.putIfAbsent(fazKey, () => _ResumoFazenda(fazenda: fazKey));
      map[fazKey]!.adicionarEstoque(e);
      final sortKey = '$fazKey|${e.talhaoId}|${e.sortimento}';
      if (vistos.add(sortKey)) {
        final vol = _getVolEsperado(e.talhaoId, e.sortimento);
        if (vol != null && vol > 0) map[fazKey]!.volumeEsperado += vol;
      }
    }
    return map;
  }

  // ── Sortimento cards ──────────────────────────────────────────────────────

  bool _pilhaPassaFiltrosSemSortimento(PilhaMadeira p) {
    if (_projetosFiltro.isNotEmpty) {
      final proj = p.talhaoId != null ? (_talhaoProjetoNome[p.talhaoId] ?? '') : '';
      if (!_projetosFiltro.contains(proj)) return false;
    }
    if (_fazendasFiltro.isNotEmpty && !_fazendasFiltro.contains(p.nomeFazenda ?? '')) return false;
    if (_talhoesFiltro.isNotEmpty && !_talhoesFiltro.contains(p.nomeTalhao ?? '')) return false;
    if (_lideresFiltro.isNotEmpty && !_lideresFiltro.contains(p.nomeLider ?? '')) return false;
    if (_periodo != _Periodo.todos) {
      if (p.dataColeta == null || !_dataPassaPeriodo(p.dataColeta!)) return false;
    }
    return true;
  }

  bool _estoquePassaFiltrosSemSortimento(EstoqueSaida e) {
    if (_projetosFiltro.isNotEmpty) {
      final proj = e.talhaoId != null ? (_talhaoProjetoNome[e.talhaoId] ?? '') : '';
      if (!_projetosFiltro.contains(proj)) return false;
    }
    if (_fazendasFiltro.isNotEmpty && !_fazendasFiltro.contains(e.nomeFazenda)) return false;
    if (_talhoesFiltro.isNotEmpty && !_talhoesFiltro.contains(e.nomeTalhao)) return false;
    return true;
  }

  Set<String> get _sortimentosTodos {
    final s = <String>{};
    for (final p in _pilhas) {
      if (_pilhaPassaFiltrosSemSortimento(p) && p.sortimento.isNotEmpty) s.add(p.sortimento);
    }
    return s;
  }

  double _solidoPilhasPorSortimento(String s) => _pilhas
      .where((p) => _pilhaPassaFiltrosSemSortimento(p) && p.sortimento == s)
      .fold(0.0, (acc, p) => acc + p.calcularVolumesolido());

  double _solidoEstoquePorSortimento(String s) => _estoques
      .where((e) => _estoquePassaFiltrosSemSortimento(e) && e.sortimento == s)
      .fold(0.0, (acc, e) => acc + e.volumeM3);

  double? _esperadoPorSortimento(String s) {
    final seen = <String>{};
    double total = 0;
    for (final p in _pilhas) {
      if (!_pilhaPassaFiltrosSemSortimento(p)) continue;
      if (p.sortimento != s || p.talhaoId == null) continue;
      final key = '${p.talhaoId}|$s';
      if (seen.add(key)) {
        final vol = _getVolEsperado(p.talhaoId, s);
        if (vol != null && vol > 0) total += vol;
      }
    }
    return total > 0 ? total : null;
  }

  Widget _buildCaminhaoCards() {
    final sortimentos = _sortimentosEstoque;
    if (sortimentos.isEmpty) return const SizedBox.shrink();
    final cor = Colors.orange.shade700;
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: sortimentos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sort = sortimentos[i];
          final saidas = _estoques.where((e) => e.sortimento == sort).toList();
          final totalCaminhoes = saidas.fold(0, (s, e) => s + e.numeroCaminhoes);
          final vol = saidas.fold(0.0, (s, e) => s + e.volumeM3);
          final sel = _caminhoesFiltro.contains(sort);
          return GestureDetector(
            onTap: () => setState(() => sel ? _caminhoesFiltro.remove(sort) : _caminhoesFiltro.add(sort)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 148,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? cor.withValues(alpha: 0.14) : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? cor : Colors.transparent, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(children: [
                    Icon(Icons.local_shipping_outlined, size: 13, color: cor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(sort,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (sel) Icon(Icons.check_circle, size: 12, color: cor),
                  ]),
                  const SizedBox(height: 3),
                  Text('${saidas.length} saída${saidas.length != 1 ? 's' : ''}',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  if (totalCaminhoes > 0)
                    Text('$totalCaminhoes caminhão${totalCaminhoes != 1 ? 'ões' : ''}',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  Text('${_nf1.format(vol)} m³',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSortimentoCards() {
    final sortimentos = _sortimentosTodos.toList()..sort();
    if (sortimentos.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: sortimentos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sort = sortimentos[i];
          final solidoPilhas = _solidoPilhasPorSortimento(sort);
          final solidoEstoque = _solidoEstoquePorSortimento(sort);
          final total = solidoPilhas + solidoEstoque;
          final esperado = _esperadoPorSortimento(sort);
          final pct = esperado != null && esperado > 0 ? (total / esperado).clamp(0.0, 1.0) : null;
          final sel = _sortimentosFiltro.contains(sort);
          final cor = Colors.brown.shade700;
          return GestureDetector(
            onTap: () => setState(() => sel ? _sortimentosFiltro.remove(sort) : _sortimentosFiltro.add(sort)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 152,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: sel ? cor.withValues(alpha: 0.14) : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? cor : Colors.transparent, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(children: [
                    Icon(Icons.layers_outlined, size: 13, color: cor),
                    const SizedBox(width: 4),
                    Expanded(child: Text(sort, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (sel) Icon(Icons.check_circle, size: 12, color: cor),
                  ]),
                  const SizedBox(height: 2),
                  Text('${_nf1.format(solidoPilhas)} m³ pilha', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  Text('${_nf1.format(solidoEstoque)} m³ est.', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  if (pct != null) ...[
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(value: pct, minHeight: 5, backgroundColor: Colors.grey.shade200, color: cor),
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

  Widget _buildFiltros() {
    return Column(children: [
      Row(children: [
        Expanded(child: _buildChip('Projeto', _projetosDisponiveis, _projetosFiltro, onChanged: () {
          _sortimentosFiltro.removeWhere((s) => !_sortimentosDisponiveis.contains(s));
          _fazendasFiltro.removeWhere((f) => !_fazendasDisponiveis.contains(f));
          _talhoesFiltro.removeWhere((t) => !_talhoesDisponiveis.contains(t));
        })),
        const SizedBox(width: 8),
        Expanded(child: _buildChip('Fazenda', _fazendasDisponiveis, _fazendasFiltro, onChanged: () {
          _talhoesFiltro.removeWhere((t) => !_talhoesDisponiveis.contains(t));
          _lideresFiltro.removeWhere((l) => !_lideresDisponiveis.contains(l));
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
    ]);
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
                  trailing: _periodo == p ? Icon(Icons.check, color: Colors.brown.shade700) : null,
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

  Widget _buildChip(String label, List<String> disponiveis, Set<String> selecionados, {VoidCallback? onChanged}) {
    if (disponiveis.isEmpty) return const SizedBox.shrink();
    final txt = selecionados.isEmpty
        ? 'Todos'
        : selecionados.length == 1 ? selecionados.first : '${selecionados.length} selecionados';
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        final tmp = Set<String>.from(selecionados);
        showDialog<void>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDlg) => AlertDialog(
              title: Text('Filtrar por $label'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    CheckboxListTile(
                      title: const Text('Todos', style: TextStyle(fontWeight: FontWeight.bold)),
                      value: tmp.isEmpty,
                      onChanged: (_) => setDlg(() => tmp.clear()),
                    ),
                    const Divider(height: 1),
                    ...disponiveis.map((v) => CheckboxListTile(
                      title: Text(v),
                      value: tmp.contains(v),
                      onChanged: (on) => setDlg(() => on == true ? tmp.add(v) : tmp.remove(v)),
                    )),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () { setState(() { selecionados.clear(); onChanged?.call(); }); Navigator.pop(ctx); },
                  child: const Text('Limpar'),
                ),
                FilledButton(
                  onPressed: () { setState(() { selecionados..clear()..addAll(tmp); onChanged?.call(); }); Navigator.pop(ctx); },
                  child: const Text('Aplicar'),
                ),
              ],
            ),
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final filtradas = _pilhasFiltradas;
    final totalEstereo = filtradas.fold(0.0, (s, p) => s + p.calcularVolumeBruto());
    final totalSolidoPilhas = filtradas.fold(0.0, (s, p) => s + p.calcularVolumesolido());
    final totalSolidoEstoques = _estoquesFiltrados.fold(0.0, (s, e) => s + e.volumeM3);
    final totalSolido = totalSolidoPilhas + totalSolidoEstoques;
    final naoExportadas = filtradas.where((p) => !p.exportada).length;
    final resumoSort = _resumoPorSortimento;
    final resumoFaz = _resumoPorFazenda;
    final talhoesCt = filtradas.map((p) => '${p.nomeFazenda}|${p.nomeTalhao}').toSet().length;

    final temVolEsperado = resumoSort.values.any((r) => r.volumeEsperado != null && r.volumeEsperado! > 0);
    final temVolEsperadoFaz = resumoFaz.values.any((r) => r.volumeEsperado > 0);

    const headerStyle = TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold);

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Filtros ────────────────────────────────────────────────────
          if (_fazendas.isNotEmpty)
            _buildFiltros(),

          const SizedBox(height: 16),

          // ── KPIs ───────────────────────────────────────────────────────
          Row(children: [
            _kpi('Pilhas', '${filtradas.length}', Icons.layers_outlined, Colors.brown),
            const SizedBox(width: 12),
            _kpi('Saídas Est.', '${_estoquesFiltrados.length}', Icons.local_shipping_outlined, Colors.orange.shade700),
            const SizedBox(width: 12),
            _kpi('Sólido', '${_nf2.format(totalSolido)} m³', Icons.forest_outlined, Colors.green.shade700),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _kpi('Estéreo', '${_nf0.format(totalEstereo)} st', Icons.inventory_2_outlined, Colors.brown.shade400),
            const SizedBox(width: 12),
            _kpi('Pendentes', '$naoExportadas', Icons.pending_outlined,
                naoExportadas > 0 ? Colors.red.shade600 : Colors.grey),
            const SizedBox(width: 12),
            _kpi('Talhões', '$talhoesCt', Icons.grid_view_outlined, Colors.teal),
          ]),

          // ── Sortimento cards (filtro) ────────────────────────────────────
          if (_sortimentosTodos.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildSortimentoCards(),
          ],

          // ── Caminhão cards (filtro por sortimento de saída) ─────────────
          if (_sortimentosEstoque.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildCaminhaoCards(),
          ],

          const SizedBox(height: 24),

          // ── Por fazenda ────────────────────────────────────────────────
          if (resumoFaz.isNotEmpty) ...[
            Text('Por fazenda', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 16,
                  headingRowColor: WidgetStateProperty.resolveWith((_) {
                    final isDark = Theme.of(context).brightness == Brightness.dark;
                    return isDark ? Colors.brown.shade800 : Colors.brown.shade700;
                  }),
                  columns: [
                    DataColumn(label: Text('Fazenda', style: headerStyle)),
                    DataColumn(label: Text('Pilhas', style: headerStyle), numeric: true),
                    DataColumn(label: Text('Estéreo (st)', style: headerStyle), numeric: true),
                    DataColumn(label: Text('Sólido (m³)', style: headerStyle), numeric: true),
                    if (temVolEsperadoFaz)
                      DataColumn(label: Text('Esperado (m³)', style: headerStyle), numeric: true),
                    if (temVolEsperadoFaz)
                      DataColumn(label: Text('% Realiz.', style: headerStyle), numeric: true),
                    DataColumn(label: Text('Pendentes', style: headerStyle), numeric: true),
                  ],
                  rows: resumoFaz.values.map((r) {
                    final pct = r.volumeEsperado > 0 ? (r.solido / r.volumeEsperado) * 100 : null;
                    final pctColor = _pctColor(pct);
                    return DataRow(cells: [
                      DataCell(Text(r.fazenda, style: const TextStyle(fontSize: 12))),
                      DataCell(Text('${r.total}', style: const TextStyle(fontSize: 12))),
                      DataCell(Text(_nf0.format(r.estereo), style: const TextStyle(fontSize: 12))),
                      DataCell(Text(_nf2.format(r.solido), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                      if (temVolEsperadoFaz)
                        DataCell(Text(r.volumeEsperado > 0 ? _nf2.format(r.volumeEsperado) : '—',
                            style: const TextStyle(fontSize: 12, color: Colors.grey))),
                      if (temVolEsperadoFaz)
                        DataCell(Text(pct != null ? '${_nf1.format(pct)}%' : '—',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: pctColor))),
                      DataCell(Text('${r.pendentes}',
                          style: TextStyle(fontSize: 12, color: r.pendentes > 0 ? Colors.red : Colors.grey))),
                    ]);
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ── Por talhão / sortimento ────────────────────────────────────
          if (resumoSort.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Nenhuma pilha coletada ainda.', style: TextStyle(color: Colors.grey)),
              ),
            )
          else ...[
            Text('Por talhão / sortimento',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 16,
                  headingRowColor: WidgetStateProperty.resolveWith((_) {
                    final isDark = Theme.of(context).brightness == Brightness.dark;
                    return isDark ? Colors.brown.shade800 : Colors.brown.shade700;
                  }),
                  columns: [
                    DataColumn(label: Text('Fazenda', style: headerStyle)),
                    DataColumn(label: Text('Talhão', style: headerStyle)),
                    DataColumn(label: Text('Sortimento', style: headerStyle)),
                    DataColumn(label: Text('Pilhas', style: headerStyle), numeric: true),
                    DataColumn(label: Text('Estéreo (st)', style: headerStyle), numeric: true),
                    DataColumn(label: Text('Sólido (m³)', style: headerStyle), numeric: true),
                    if (temVolEsperado)
                      DataColumn(label: Text('Esperado (m³)', style: headerStyle), numeric: true),
                    if (temVolEsperado)
                      DataColumn(label: Text('% Realiz.', style: headerStyle), numeric: true),
                    DataColumn(label: Text('Pendentes', style: headerStyle), numeric: true),
                  ],
                  rows: resumoSort.values.map((r) {
                    final pct = (r.volumeEsperado != null && r.volumeEsperado! > 0)
                        ? (r.solido / r.volumeEsperado!) * 100
                        : null;
                    final pctColor = _pctColor(pct);
                    return DataRow(cells: [
                      DataCell(Text(r.fazenda, style: const TextStyle(fontSize: 12))),
                      DataCell(Text(r.talhao, style: const TextStyle(fontSize: 12))),
                      DataCell(Text(r.sortimento, style: const TextStyle(fontSize: 12))),
                      DataCell(Text('${r.total}', style: const TextStyle(fontSize: 12))),
                      DataCell(Text(_nf0.format(r.estereo), style: const TextStyle(fontSize: 12))),
                      DataCell(Text(_nf2.format(r.solido),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                      if (temVolEsperado)
                        DataCell(Text(
                          r.volumeEsperado != null && r.volumeEsperado! > 0
                              ? _nf2.format(r.volumeEsperado)
                              : '—',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        )),
                      if (temVolEsperado)
                        DataCell(Text(pct != null ? '${_nf1.format(pct)}%' : '—',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: pctColor))),
                      DataCell(Text('${r.pendentes}',
                          style: TextStyle(fontSize: 12, color: r.pendentes > 0 ? Colors.red : Colors.grey))),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // ── Nova Saída de Estoque ──────────────────────────────────────
          OutlinedButton.icon(
            icon: Icon(Icons.local_shipping_outlined, color: Colors.orange.shade700),
            label: Text('Nova Saída de Estoque', style: TextStyle(color: Colors.orange.shade800)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: Colors.orange.shade600, width: 1.5),
            ),
            onPressed: () => _selecionarCentroideParaEstoque(),
          ),

          const SizedBox(height: 12),

          // ── Mapa Geral ─────────────────────────────────────────────────
          OutlinedButton.icon(
            icon: const Icon(Icons.map_outlined),
            label: const Text('Mapa Geral de Pilhas'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: Colors.brown.shade600, width: 1.5),
              foregroundColor: Colors.brown.shade700,
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PilhasMapPage()),
            ),
          ),

          const SizedBox(height: 12),

          // ── Exportar ───────────────────────────────────────────────────
          ElevatedButton.icon(
            icon: const Icon(Icons.download_outlined),
            label: const Text('Exportar Pilhas'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.brown.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () => _exportService.exportarNovasPilhas(context),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _selecionarCentroideParaEstoque() async {
    CentroidePilha? centroide;

    if (_centroidesMap.isNotEmpty) {
      // Caminho normal: centroides da OS já importada
      final centroides = _centroidesMap.values.toList()
        ..sort((a, b) {
          final faz = a.nomeFazenda.compareTo(b.nomeFazenda);
          return faz != 0 ? faz : a.nomeTalhao.compareTo(b.nomeTalhao);
        });
      centroide = await _mostrarPickerCentroides(centroides);
    } else {
      // Fallback: sem OS importada — monta centroide sintético a partir dos talhões
      final talhoes = await _talhaoRepo.getTodosOsTalhoes();
      if (!mounted) return;
      if (talhoes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum talhão encontrado. Importe um projeto primeiro.')),
        );
        return;
      }
      final talhao = await _mostrarPickerTalhoes(talhoes);
      if (talhao == null) return;
      // Centroide sintético: sem ID nem sortimentos (form aceita entrada manual)
      centroide = CentroidePilha(
        talhaoId: talhao.id,
        fazendaId: talhao.fazendaId,
        nomeFazenda: talhao.fazendaNome ?? 'Fazenda',
        nomeTalhao: talhao.nome,
        latitude: 0,
        longitude: 0,
        sortimentos: [],
      );
    }

    if (centroide == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EstoqueSaidaPage(centroide: centroide!)),
    );
    _carregar();
  }

  Future<CentroidePilha?> _mostrarPickerCentroides(List<CentroidePilha> centroides) {
    return showModalBottomSheet<CentroidePilha>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        builder: (_, ctrl) => _pickerSheet(
          ctrl,
          centroides.length,
          (i) {
            final c = centroides[i];
            return ListTile(
              leading: const Icon(Icons.forest_outlined, color: Colors.brown),
              title: Text(c.nomeTalhao, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(c.nomeFazenda),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, c),
            );
          },
        ),
      ),
    );
  }

  Future<Talhao?> _mostrarPickerTalhoes(List<Talhao> talhoes) {
    return showModalBottomSheet<Talhao>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        builder: (_, ctrl) => _pickerSheet(
          ctrl,
          talhoes.length,
          (i) {
            final t = talhoes[i];
            return ListTile(
              leading: const Icon(Icons.grid_view_outlined, color: Colors.brown),
              title: Text(t.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(t.fazendaNome ?? ''),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, t),
            );
          },
        ),
      ),
    );
  }

  Widget _pickerSheet(
    ScrollController ctrl,
    int itemCount,
    Widget Function(int) itemBuilder,
  ) {
    return Column(
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
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Selecione o talhão',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            controller: ctrl,
            itemCount: itemCount,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
            itemBuilder: (_, i) => itemBuilder(i),
          ),
        ),
      ],
    );
  }

  Color _pctColor(double? pct) {
    if (pct == null) return Colors.grey;
    if (pct >= 90) return Colors.green.shade700;
    if (pct >= 60) return Colors.orange.shade700;
    return Colors.red.shade600;
  }

  Widget _kpi(String label, String value, IconData icon, Color color) => Expanded(
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 4),
                Text(value,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color),
                    textAlign: TextAlign.center),
                Text(label,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
}

class _ResumoSortimento {
  final String fazenda;
  final String talhao;
  final String sortimento;
  final double? volumeEsperado;
  int total = 0;
  int pendentes = 0;
  double estereo = 0;
  double solido = 0;

  _ResumoSortimento({
    required this.fazenda,
    required this.talhao,
    required this.sortimento,
    this.volumeEsperado,
  });

  void adicionar(PilhaMadeira p) {
    total++;
    if (!p.exportada) pendentes++;
    estereo += p.calcularVolumeBruto();
    solido += p.calcularVolumesolido();
  }

  void adicionarEstoque(EstoqueSaida e) {
    solido += e.volumeM3;
  }
}

class _ResumoFazenda {
  final String fazenda;
  int total = 0;
  int pendentes = 0;
  double estereo = 0;
  double solido = 0;
  double volumeEsperado = 0;

  _ResumoFazenda({required this.fazenda});

  void adicionarPilha(PilhaMadeira p) {
    total++;
    if (!p.exportada) pendentes++;
    estereo += p.calcularVolumeBruto();
    solido += p.calcularVolumesolido();
  }

  void adicionarEstoque(EstoqueSaida e) {
    solido += e.volumeM3;
  }
}

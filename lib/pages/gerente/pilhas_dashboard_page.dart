import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geoforestv1/data/repositories/pilha_repository.dart';
import 'package:geoforestv1/models/pilha_madeira_model.dart';
import 'package:geoforestv1/services/export_service.dart';

class PilhasDashboardPage extends StatefulWidget {
  const PilhasDashboardPage({super.key});

  @override
  State<PilhasDashboardPage> createState() => _PilhasDashboardPageState();
}

class _PilhasDashboardPageState extends State<PilhasDashboardPage> {
  final _repo = PilhaRepository();
  final _exportService = ExportService();
  final _nf2 = NumberFormat('0.00', 'pt_BR');
  final _nf0 = NumberFormat('0', 'pt_BR');
  final _nf1 = NumberFormat('0.0', 'pt_BR');

  List<PilhaMadeira> _pilhas = [];
  Map<int, CentroidePilha> _centroidesMap = {};
  bool _loading = true;
  String? _fazendaFiltro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final todas = await _repo.getPilhasPorLideres(apenasNaoExportadas: false);

    final talhaoIds = todas.map((p) => p.talhaoId).whereType<int>().toSet();
    final centroidesMap = <int, CentroidePilha>{};
    for (final id in talhaoIds) {
      final c = await _repo.getCentroideParaTalhao(id);
      if (c != null) centroidesMap[id] = c;
    }

    if (mounted) {
      setState(() {
        _pilhas = todas;
        _centroidesMap = centroidesMap;
        _loading = false;
      });
    }
  }

  List<PilhaMadeira> get _pilhasFiltradas => _fazendaFiltro == null
      ? _pilhas
      : _pilhas.where((p) => p.nomeFazenda == _fazendaFiltro).toList();

  List<String> get _fazendas =>
      _pilhas.map((p) => p.nomeFazenda ?? '').where((f) => f.isNotEmpty).toSet().toList()..sort();

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

  // Agrupa por fazenda+talhão+sortimento
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
    return map;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final filtradas = _pilhasFiltradas;
    final totalEstereo = filtradas.fold(0.0, (s, p) => s + p.calcularVolumeBruto());
    final totalSolido = filtradas.fold(0.0, (s, p) => s + p.calcularVolumesolido());
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
          // ── Filtro de fazenda ──────────────────────────────────────────
          if (_fazendas.isNotEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: DropdownButton<String?>(
                  value: _fazendaFiltro,
                  isExpanded: true,
                  hint: const Text('Todas as fazendas'),
                  underline: const SizedBox(),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Todas as fazendas')),
                    ..._fazendas.map((f) => DropdownMenuItem(value: f, child: Text(f))),
                  ],
                  onChanged: (v) => setState(() => _fazendaFiltro = v),
                ),
              ),
            ),

          const SizedBox(height: 16),

          // ── KPIs ───────────────────────────────────────────────────────
          Row(children: [
            _kpi('Pilhas', '${filtradas.length}', Icons.layers_outlined, Colors.brown),
            const SizedBox(width: 12),
            _kpi('Estéreo', '${_nf0.format(totalEstereo)} st', Icons.inventory_2_outlined, Colors.orange.shade700),
            const SizedBox(width: 12),
            _kpi('Sólido', '${_nf2.format(totalSolido)} m³', Icons.forest_outlined, Colors.green.shade700),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _kpi('Exportadas', '${filtradas.where((p) => p.exportada).length}', Icons.check_circle_outline, Colors.blue),
            const SizedBox(width: 12),
            _kpi('Pendentes', '$naoExportadas', Icons.pending_outlined,
                naoExportadas > 0 ? Colors.red.shade600 : Colors.grey),
            const SizedBox(width: 12),
            _kpi('Talhões', '$talhoesCt', Icons.grid_view_outlined, Colors.teal),
          ]),

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
}

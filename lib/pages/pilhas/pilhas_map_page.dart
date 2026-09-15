import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geoforestv1/data/repositories/estoque_repository.dart';
import 'package:geoforestv1/data/repositories/pilha_repository.dart';
import 'package:geoforestv1/models/pilha_madeira_model.dart';
import 'package:latlong2/latlong.dart';
import 'package:pie_chart/pie_chart.dart';

// ── Modelos internos ────────────────────────────────────────────────────────

class _SortProgresso {
  final String nome;
  final double esperado;
  final double coletado;

  _SortProgresso({required this.nome, required this.esperado, required this.coletado});

  double get pct => esperado > 0 ? (coletado / esperado).clamp(0.0, 1.0) : 0.0;
}

class _FazendaData {
  final String nome;
  final LatLng center;
  final double totEsperado;
  final double totColetado;
  final List<_SortProgresso> sortimentos;

  _FazendaData({
    required this.nome,
    required this.center,
    required this.totEsperado,
    required this.totColetado,
    required this.sortimentos,
  });

  double get progresso =>
      totEsperado > 0 ? (totColetado / totEsperado).clamp(0.0, 1.0) : 0.0;
}

// ── Página ──────────────────────────────────────────────────────────────────

class PilhasMapPage extends StatefulWidget {
  const PilhasMapPage({super.key});

  @override
  State<PilhasMapPage> createState() => _PilhasMapPageState();
}

class _PilhasMapPageState extends State<PilhasMapPage> {
  final _repo = PilhaRepository();
  final _mapController = MapController();

  bool _loading = true;
  List<_FazendaData> _fazendas = [];
  bool _useSatelite = true;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _loading = true);

    final pilhas = await _repo.getPilhasPorLideres(apenasNaoExportadas: false);
    final estoques = await EstoqueRepository().getTodosEstoques();

    // Centroides para todos os talhões que têm pilhas ou estoques
    final talhaoIds = {
      ...pilhas.map((p) => p.talhaoId).whereType<int>(),
      ...estoques.map((e) => e.talhaoId).whereType<int>(),
    };
    final centroidesMap = <int, CentroidePilha>{};
    for (final id in talhaoIds) {
      final c = await _repo.getCentroideParaTalhao(id);
      if (c != null) centroidesMap[id] = c;
    }

    final espMap = <String, Map<String, double>>{};
    final colMap = <String, Map<String, double>>{};
    final pointsFaz = <String, List<LatLng>>{};

    // Volume esperado: um por centroide (talhão)
    for (final centroide in centroidesMap.values) {
      final faz = centroide.nomeFazenda;
      espMap.putIfAbsent(faz, () => {});
      for (final s in centroide.sortimentos) {
        final vol = s.volumeEsperadoM3 ?? 0;
        espMap[faz]![s.nome] = (espMap[faz]![s.nome] ?? 0) + vol;
      }
      pointsFaz.putIfAbsent(faz, () => []).add(LatLng(centroide.latitude, centroide.longitude));
    }

    // Volume coletado: pilhas
    for (final p in pilhas) {
      final faz = p.nomeFazenda ?? 'Desconhecida';
      colMap.putIfAbsent(faz, () => {});
      colMap[faz]![p.sortimento] = (colMap[faz]![p.sortimento] ?? 0) + p.calcularVolumesolido();
      if (p.latitude != null && p.longitude != null) {
        pointsFaz.putIfAbsent(faz, () => []).add(LatLng(p.latitude!, p.longitude!));
      }
    }

    // Volume coletado: estoques de saída somam ao coletado por sortimento
    for (final e in estoques) {
      final faz = e.nomeFazenda.isNotEmpty ? e.nomeFazenda : 'Desconhecida';
      colMap.putIfAbsent(faz, () => {});
      colMap[faz]![e.sortimento] = (colMap[faz]![e.sortimento] ?? 0) + e.volumeM3;
    }

    // Monta lista de fazendas
    final fazendas = <_FazendaData>[];
    for (final faz in pointsFaz.keys) {
      final points = pointsFaz[faz]!;
      if (points.isEmpty) continue;

      final bounds = LatLngBounds.fromPoints(points);
      final center = bounds.center;

      final espFaz = espMap[faz] ?? {};
      final colFaz = colMap[faz] ?? {};

      final allSorts = {...espFaz.keys, ...colFaz.keys};
      final sortimentos = allSorts.map((nome) {
        return _SortProgresso(
          nome: nome,
          esperado: espFaz[nome] ?? 0,
          coletado: colFaz[nome] ?? 0,
        );
      }).toList()
        ..sort((a, b) => a.nome.compareTo(b.nome));

      final totEsp = sortimentos.fold(0.0, (s, e) => s + e.esperado);
      final totCol = sortimentos.fold(0.0, (s, e) => s + e.coletado);

      fazendas.add(_FazendaData(
        nome: faz,
        center: center,
        totEsperado: totEsp,
        totColetado: totCol,
        sortimentos: sortimentos,
      ));
    }

    if (mounted) {
      setState(() {
        _fazendas = fazendas;
        _loading = false;
      });

      if (fazendas.isNotEmpty) {
        final allPoints = fazendas.map((f) => f.center).toList();
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!mounted) return;
          if (allPoints.length > 1) {
            _mapController.fitCamera(CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(allPoints),
              padding: const EdgeInsets.all(60),
            ));
          } else {
            _mapController.move(allPoints.first, 11);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de Pilhas — Por Fazenda'),
        actions: [
          IconButton(
            icon: Icon(_useSatelite ? Icons.map_outlined : Icons.satellite_alt_outlined),
            tooltip: 'Mudar camada',
            onPressed: () => setState(() => _useSatelite = !_useSatelite),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _fazendas.isEmpty
              ? const Center(
                  child: Text('Nenhuma pilha coletada ainda.',
                      style: TextStyle(color: Colors.grey)),
                )
              : FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(
                    initialCenter: LatLng(-15.7, -47.8),
                    initialZoom: 4,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _useSatelite
                          ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                          : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.geoforestv1',
                    ),
                    MarkerLayer(
                      markers: _fazendas.map((f) {
                        return Marker(
                          width: 130,
                          height: 130,
                          point: f.center,
                          child: _PilhaClusterMarker(
                            label: f.nome,
                            volColetado: f.totColetado,
                            volEsperado: f.totEsperado,
                            progresso: f.progresso,
                            onTap: () => _showFazendaSheet(f),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
    );
  }

  void _showFazendaSheet(_FazendaData f) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, scrollCtrl) => Column(
          children: [
            // Alça
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 8),
            // Cabeçalho
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.forest, color: Colors.brown),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(f.nome,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                  if (f.totEsperado > 0)
                    Text(
                      '${(f.progresso * 100).toStringAsFixed(1)}% total',
                      style: TextStyle(
                          fontSize: 13,
                          color: _corProgresso(f.progresso),
                          fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
            const Divider(height: 16),
            // Lista por sortimento
            Expanded(
              child: f.sortimentos.isEmpty
                  ? const Center(child: Text('Sem dados de sortimento.'))
                  : ListView.separated(
                      controller: scrollCtrl,
                      itemCount: f.sortimentos.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 16),
                      itemBuilder: (_, i) {
                        final s = f.sortimentos[i];
                        final cor = _corProgresso(s.pct);
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(s.nome,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14)),
                                  ),
                                  Text(
                                    '${(s.pct * 100).toStringAsFixed(1)}%',
                                    style: TextStyle(
                                        color: cor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: s.pct,
                                  minHeight: 8,
                                  backgroundColor: Colors.grey.shade200,
                                  color: cor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Coletado: ${s.coletado.toStringAsFixed(2)} m³',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700),
                                  ),
                                  if (s.esperado > 0)
                                    Text(
                                      'Esperado: ${s.esperado.toStringAsFixed(2)} m³',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Color _corProgresso(double pct) {
    if (pct >= 0.9) return Colors.green.shade700;
    if (pct >= 0.6) return Colors.orange.shade700;
    return Colors.red.shade600;
  }
}

// ── Widget marcador de fazenda ───────────────────────────────────────────────

class _PilhaClusterMarker extends StatelessWidget {
  final String label;
  final double volColetado;
  final double volEsperado;
  final double progresso;
  final VoidCallback onTap;

  const _PilhaClusterMarker({
    required this.label,
    required this.volColetado,
    required this.volEsperado,
    required this.progresso,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color ringColor;
    if (progresso >= 1.0) {
      ringColor = Colors.green.shade600;
    } else if (progresso > 0) {
      ringColor = Colors.orange.shade700;
    } else {
      ringColor = Colors.grey.shade500;
    }

    final pctText = volEsperado > 0
        ? '${(progresso * 100).toStringAsFixed(1)}%'
        : '${volColetado.toStringAsFixed(1)} m³';

    const size = 110.0;
    const fontSize = 11.0;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              dataMap: {
                'coletado': progresso > 0 ? progresso : 0.001,
                'restante': progresso < 1.0
                    ? (1.0 - progresso).clamp(0.001, 1.0)
                    : 0.001,
              },
              animationDuration: const Duration(milliseconds: 600),
              chartType: ChartType.ring,
              ringStrokeWidth: 9,
              chartRadius: size,
              colorList: [ringColor, Colors.black26],
              legendOptions: const LegendOptions(showLegends: false),
              chartValuesOptions: const ChartValuesOptions(showChartValues: false),
            ),
            Container(
              width: size * 0.70,
              height: size * 0.70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).cardColor.withValues(alpha: 0.95),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pctText,
                        style: TextStyle(
                          fontSize: fontSize + 1,
                          fontWeight: FontWeight.w900,
                          color: ringColor,
                        ),
                      ),
                      if (volEsperado > 0)
                        Text(
                          '${volColetado.toStringAsFixed(1)}/${volEsperado.toStringAsFixed(1)}',
                          style: TextStyle(
                            fontSize: fontSize - 1,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

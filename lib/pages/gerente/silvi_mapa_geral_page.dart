import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geoforestv1/models/silvi_model.dart';
import 'package:geoforestv1/providers/map_provider.dart';
import 'package:geoforestv1/services/pdf_tile_provider.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

class SilviMapaGeralPage extends StatefulWidget {
  final List<OperacaoSilvi> operacoes;
  final List<CentroideSilvi> centroides;

  const SilviMapaGeralPage({
    super.key,
    required this.operacoes,
    required this.centroides,
  });

  @override
  State<SilviMapaGeralPage> createState() => _SilviMapaGeralPageState();
}

class _SilviMapaGeralPageState extends State<SilviMapaGeralPage> {
  final _mapController = MapController();
  bool _satellite = true;
  bool _mapReady = false;
  bool _filtroExpandido = false;

  // null = visão de fazendas (clusters); String = fazenda selecionada mostrando polígonos
  String? _fazendaSelecionada;

  final Set<String> _tiposFiltro = {};

  static const _satUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const _osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  // ── Computed ──────────────────────────────────────────────────────────────

  /// Centroides agrupados por fazenda — um representante por fazenda.
  Map<String, CentroideSilvi> get _centroidePorFazenda {
    final map = <String, CentroideSilvi>{};
    for (final c in widget.centroides) {
      map.putIfAbsent(c.nomeFazenda, () => c);
    }
    return map;
  }

  /// Polígonos da fazenda selecionada (filtrados por tipo se houver).
  List<_PolData> get _poligonosFazenda {
    if (_fazendaSelecionada == null) return [];
    return widget.operacoes.where((op) {
      if ((op.nomeFazenda ?? '') != _fazendaSelecionada) return false;
      if (op.areaGeoJson == null) return false;
      if (_tiposFiltro.isNotEmpty && !_tiposFiltro.contains(op.tipo)) {
        return false;
      }
      return true;
    }).map((op) {
      final pts = _parseGeoJson(op.areaGeoJson!);
      if (pts.isEmpty) return null;
      return _PolData(
          op: op, pontos: pts, cor: OperacaoSilviTipo.fromString(op.tipo).color);
    }).whereType<_PolData>().toList();
  }

  Set<String> get _tiposNaFazenda {
    if (_fazendaSelecionada == null) return {};
    return widget.operacoes
        .where((o) =>
            (o.nomeFazenda ?? '') == _fazendaSelecionada &&
            o.areaGeoJson != null)
        .map((o) => o.tipo)
        .toSet();
  }

  /// Número de áreas desenhadas por fazenda.
  Map<String, int> get _areasPorFazenda {
    final map = <String, int>{};
    for (final op in widget.operacoes) {
      if (op.areaGeoJson == null) continue;
      final f = op.nomeFazenda ?? '—';
      map[f] = (map[f] ?? 0) + 1;
    }
    return map;
  }

  List<LatLng> _parseGeoJson(String geoJson) {
    try {
      final decoded = jsonDecode(geoJson) as Map<String, dynamic>;
      final coords = (decoded['geometry']['coordinates'][0] as List)
          .map((c) =>
              LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      if (coords.length > 1 &&
          coords.last.latitude == coords.first.latitude &&
          coords.last.longitude == coords.first.longitude) {
        coords.removeLast();
      }
      return coords;
    } catch (_) {
      return [];
    }
  }

  void _fitFazenda(String nomeFazenda) {
    if (!_mapReady) return;
    final pols = widget.operacoes
        .where((op) =>
            (op.nomeFazenda ?? '') == nomeFazenda && op.areaGeoJson != null)
        .expand((op) => _parseGeoJson(op.areaGeoJson!))
        .toList();

    if (pols.isNotEmpty) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(pols),
          padding: const EdgeInsets.all(50),
        ),
      );
    } else {
      // Sem polígono: centraliza no centroide da fazenda
      final c = _centroidePorFazenda[nomeFazenda];
      if (c != null) {
        _mapController.move(LatLng(c.latitude, c.longitude), 15);
      }
    }
  }

  void _fitTudo() {
    if (!_mapReady) return;
    final pts = widget.centroides
        .map((c) => LatLng(c.latitude, c.longitude))
        .toList();
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _mapController.move(pts.first, 13);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(60),
      ),
    );
  }

  void _selecionarFazenda(String nome) {
    setState(() {
      _fazendaSelecionada = nome;
      _tiposFiltro.clear();
    });
    _fitFazenda(nome);
  }

  void _voltarParaClusters() {
    setState(() {
      _fazendaSelecionada = null;
      _tiposFiltro.clear();
      _filtroExpandido = false;
    });
    Future.microtask(_fitTudo);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mapProvider = context.watch<MapProvider>();
    final temPdf = mapProvider.pdfTilesDir != null;
    final emClusters = _fazendaSelecionada == null;
    final pols = _poligonosFazenda;
    final tipos = _tiposNaFazenda.toList()..sort();
    final temFiltro = _tiposFiltro.isNotEmpty;
    final areasPorFaz = _areasPorFazenda;
    final centroidePorFaz = _centroidePorFazenda;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        leading: emClusters
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _voltarParaClusters,
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              emClusters ? 'Mapa Geral' : _fazendaSelecionada!,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            Text(
              emClusters
                  ? 'Silvicultura · ${centroidePorFaz.length} fazenda(s)'
                  : 'Toque em "←" para voltar às fazendas',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          // Filtro (só visível na visão de fazenda)
          if (!emClusters) ...[
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: () =>
                      setState(() => _filtroExpandido = !_filtroExpandido),
                ),
                if (temFiltro)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          color: Colors.orange, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
          ],
          IconButton(
            icon: Icon(
              temPdf ? Icons.picture_as_pdf : Icons.picture_as_pdf_outlined,
              color: temPdf && mapProvider.showPdfOverlay
                  ? Colors.orange
                  : Colors.white,
            ),
            tooltip: temPdf
                ? (mapProvider.showPdfOverlay ? 'Ocultar PDF' : 'Mostrar PDF')
                : 'Importar PDF de referência',
            onPressed: () => temPdf
                ? mapProvider.togglePdfOverlay()
                : mapProvider.importPdfOverlay(context),
          ),
          IconButton(
            icon: Icon(_satellite ? Icons.map_outlined : Icons.satellite_alt),
            onPressed: () => setState(() => _satellite = !_satellite),
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen),
            onPressed: emClusters
                ? _fitTudo
                : () => _fitFazenda(_fazendaSelecionada!),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Filtro por tipo (visão de fazenda) ───────────────────────
          if (!emClusters)
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: _filtroExpandido && tipos.isNotEmpty
                  ? _buildFiltroTipo(tipos, temFiltro)
                  : const SizedBox.shrink(),
            ),

          // ── Barra de info ─────────────────────────────────────────────
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(children: [
              Icon(
                emClusters ? Icons.domain_outlined : Icons.layers_outlined,
                size: 14,
                color: Colors.green.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                emClusters
                    ? 'Toque em uma fazenda para ver as operações'
                    : '${pols.length} área(s) com polígono',
                style: const TextStyle(fontSize: 12),
              ),
              const Spacer(),
              if (!emClusters)
                Text(
                  '${pols.fold(0.0, (s, p) => s + (p.op.areaAplicadaHa ?? 0)).toStringAsFixed(1)} ha',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
            ]),
          ),

          // ── Mapa ──────────────────────────────────────────────────────
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.centroides.isNotEmpty
                    ? LatLng(widget.centroides.first.latitude,
                        widget.centroides.first.longitude)
                    : const LatLng(-15, -50),
                initialZoom: 11,
                minZoom: 3,
                maxZoom: 19,
                onMapReady: () {
                  setState(() => _mapReady = true);
                  Future.microtask(_fitTudo);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: _satellite ? _satUrl : _osmUrl,
                  userAgentPackageName: 'com.example.geoforestv1',
                ),
                if (temPdf &&
                    mapProvider.showPdfOverlay &&
                    mapProvider.pdfOverlayBounds != null)
                  Opacity(
                    opacity: mapProvider.pdfOverlayOpacity,
                    child: TileLayer(
                      tileProvider: PdfTileProvider(
                          tilesBasePath: mapProvider.pdfTilesDir!),
                      tileBounds: mapProvider.pdfOverlayBounds,
                      minNativeZoom: 13,
                      maxNativeZoom: 17,
                      tileDimension: 256,
                      userAgentPackageName: 'com.example.geoforestv1',
                    ),
                  ),

                // Polígonos da fazenda selecionada
                if (!emClusters && pols.isNotEmpty)
                  PolygonLayer(
                    polygons: pols
                        .map((p) => Polygon(
                              points: p.pontos,
                              color: p.cor.withValues(alpha: 0.35),
                              borderColor: p.cor,
                              borderStrokeWidth: 2,
                              label: _labelPol(p.op),
                              labelStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                      color: Colors.black54, blurRadius: 4)
                                ],
                              ),
                            ))
                        .toList(),
                  ),

                // Marcadores de cluster (visão de fazendas)
                if (emClusters)
                  MarkerLayer(
                    markers: centroidePorFaz.entries.map((e) {
                      final nome = e.key;
                      final c = e.value;
                      final count = areasPorFaz[nome] ?? 0;
                      return Marker(
                        point: LatLng(c.latitude, c.longitude),
                        width: 80,
                        height: 80,
                        child: GestureDetector(
                          onTap: () => _selecionarFazenda(nome),
                          child: _FazendaClusterMarker(
                            nomeFazenda: nome,
                            numAreas: count,
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                // Centroides individuais (visão de fazenda selecionada)
                if (!emClusters)
                  MarkerLayer(
                    markers: widget.centroides
                        .where((c) => c.nomeFazenda == _fazendaSelecionada)
                        .map((c) => Marker(
                              point: LatLng(c.latitude, c.longitude),
                              width: 22,
                              height: 22,
                              child: Icon(Icons.location_pin,
                                  color:
                                      Colors.red.withValues(alpha: 0.7),
                                  size: 22),
                            ))
                        .toList(),
                  ),

                RichAttributionWidget(
                  alignment: AttributionAlignment.bottomLeft,
                  attributions: [
                    TextSourceAttribution(
                      _satellite
                          ? '© Esri, Maxar, Earthstar Geographics'
                          : '© OpenStreetMap contributors',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Legenda / lista de fazendas ───────────────────────────────
          if (emClusters)
            _buildListaFazendas(centroidePorFaz, areasPorFaz)
          else if (tipos.isNotEmpty)
            _buildLegendaTipos(tipos),
        ],
      ),
    );
  }

  // ── Widgets auxiliares ────────────────────────────────────────────────────

  String _labelPol(OperacaoSilvi op) {
    final parts = <String>[];
    if ((op.nomeTalhao ?? '').isNotEmpty) parts.add(op.nomeTalhao!);
    if (op.dataExecucao != null) {
      final dt = DateTime.tryParse(op.dataExecucao!);
      if (dt != null) parts.add(DateFormat('dd/MM').format(dt));
    }
    return parts.join(' · ');
  }

  Widget _buildFiltroTipo(List<String> tipos, bool temFiltro) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Filtrar por operação:',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (temFiltro)
              TextButton(
                onPressed: () =>
                    setState(() => _tiposFiltro.clear()),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(60, 28)),
                child: const Text('Limpar',
                    style: TextStyle(fontSize: 11)),
              ),
          ]),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: tipos.map((tipo) {
              final t = OperacaoSilviTipo.fromString(tipo);
              final sel = _tiposFiltro.contains(tipo);
              return FilterChip(
                avatar: Icon(t.icon, size: 14, color: t.color),
                label: Text(t.label,
                    style: const TextStyle(fontSize: 11)),
                selected: sel,
                onSelected: (v) => setState(() {
                  v
                      ? _tiposFiltro.add(tipo)
                      : _tiposFiltro.remove(tipo);
                }),
                selectedColor: t.color.withValues(alpha: 0.2),
                checkmarkColor: t.color,
                padding:
                    const EdgeInsets.symmetric(horizontal: 4),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildListaFazendas(
      Map<String, CentroideSilvi> centroidePorFaz,
      Map<String, int> areasPorFaz) {
    final fazendas = centroidePorFaz.keys.toList()..sort();
    return Container(
      color: Theme.of(context).colorScheme.surface,
      constraints: const BoxConstraints(maxHeight: 120),
      child: ListView.separated(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: fazendas.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final nome = fazendas[i];
          final count = areasPorFaz[nome] ?? 0;
          return GestureDetector(
            onTap: () => _selecionarFazenda(nome),
            child: Card(
              color: Colors.green.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.green.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.domain_outlined,
                            size: 14,
                            color: Colors.green.shade700),
                        const SizedBox(width: 4),
                        Text(nome,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count > 0
                          ? '$count área(s) desenhada(s)'
                          : 'Sem áreas desenhadas',
                      style: TextStyle(
                          fontSize: 11,
                          color: count > 0
                              ? Colors.green.shade700
                              : Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text('Toque para ver →',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLegendaTipos(List<String> tipos) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: tipos.map((tipo) {
          final t = OperacaoSilviTipo.fromString(tipo);
          final area = widget.operacoes
              .where((o) =>
                  o.tipo == tipo &&
                  o.areaGeoJson != null &&
                  (o.nomeFazenda ?? '') == _fazendaSelecionada)
              .fold(0.0, (s, o) => s + (o.areaAplicadaHa ?? 0));
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: t.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text('${t.label}  ${area.toStringAsFixed(1)} ha',
                  style: const TextStyle(fontSize: 11)),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── Marker de cluster por fazenda ─────────────────────────────────────────────

class _FazendaClusterMarker extends StatelessWidget {
  final String nomeFazenda;
  final int numAreas;

  const _FazendaClusterMarker({
    required this.nomeFazenda,
    required this.numAreas,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.green.shade700,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.domain_outlined,
                  color: Colors.white, size: 16),
              if (numAreas > 0)
                Text(
                  '$numAreas',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Container(
          constraints: const BoxConstraints(maxWidth: 80),
          padding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.green.shade700.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            nomeFazenda,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _PolData {
  final OperacaoSilvi op;
  final List<LatLng> pontos;
  final Color cor;
  _PolData({required this.op, required this.pontos, required this.cor});
}

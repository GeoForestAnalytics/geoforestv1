import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geoforestv1/models/silvi_model.dart';
import 'package:geoforestv1/pages/silvicultura/desenhar_area_silvi_page.dart';
import 'package:geoforestv1/data/repositories/silvi_repository.dart';
import 'package:geoforestv1/providers/map_provider.dart';
import 'package:geoforestv1/services/pdf_tile_provider.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

class VisualizarAreasSilviPage extends StatefulWidget {
  final List<OperacaoSilvi> operacoes;
  final CentroideSilvi centroide;

  const VisualizarAreasSilviPage({
    super.key,
    required this.operacoes,
    required this.centroide,
  });

  @override
  State<VisualizarAreasSilviPage> createState() =>
      _VisualizarAreasSilviPageState();
}

class _VisualizarAreasSilviPageState extends State<VisualizarAreasSilviPage> {
  final _mapController = MapController();
  final _repo = SilviRepository();

  bool _satellite = true;
  bool _mapReady = false;
  bool _filtroExpandido = false;

  late List<OperacaoSilvi> _todasOperacoes;

  // Filtros ativos
  final Set<String> _tiposFiltrados = {};   // vazio = todos
  final Set<String> _mesesFiltrados = {};   // "MM/yyyy" vazio = todos

  static const _satUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const _osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static const _palette = [
    Color(0xFF81C784),
    Color(0xFF4CAF50),
    Color(0xFF388E3C),
    Color(0xFF1B5E20),
    Color(0xFF00BCD4),
    Color(0xFF0097A7),
  ];

  @override
  void initState() {
    super.initState();
    _todasOperacoes = List.from(widget.operacoes);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<OperacaoSilvi> get _operacoesFiltradas {
    return _todasOperacoes.where((op) {
      if (_tiposFiltrados.isNotEmpty && !_tiposFiltrados.contains(op.tipo)) {
        return false;
      }
      if (_mesesFiltrados.isNotEmpty) {
        final mes = _mesAno(op.dataExecucao);
        if (!_mesesFiltrados.contains(mes)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => (a.dataExecucao ?? '').compareTo(b.dataExecucao ?? ''));
  }

  List<_AreaData> get _areas {
    final comPoligono = _operacoesFiltradas
        .where((op) => op.areaGeoJson != null && op.areaGeoJson!.isNotEmpty)
        .toList();
    return comPoligono.asMap().entries.map((e) {
      final color = _palette[e.key % _palette.length];
      return _AreaData(
        op: e.value,
        pontos: _parseGeoJson(e.value.areaGeoJson!),
        color: color,
      );
    }).toList();
  }

  Set<String> get _tiposDisponiveis =>
      _todasOperacoes.map((o) => o.tipo).toSet();

  Set<String> get _mesesDisponiveis =>
      _todasOperacoes.map((o) => _mesAno(o.dataExecucao)).toSet();

  String _mesAno(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    return dt != null ? DateFormat('MM/yyyy').format(dt) : '—';
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

  void _fitBounds() {
    if (!_mapReady) return;
    final allPts = _areas.expand((a) => a.pontos).toList();
    if (allPts.isEmpty) {
      _mapController.move(
        LatLng(widget.centroide.latitude, widget.centroide.longitude),
        15,
      );
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(allPts),
        padding: const EdgeInsets.all(40),
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    return dt != null ? DateFormat('dd/MM/yy').format(dt) : iso;
  }

  double _somarAreaFiltrada(String tipo) {
    return _operacoesFiltradas
        .where((op) => op.tipo == tipo && op.areaAplicadaHa != null)
        .fold(0.0, (sum, op) => sum + op.areaAplicadaHa!);
  }

  // ── Editar área de uma operação ───────────────────────────────────────────

  Future<void> _editarArea(OperacaoSilvi op) async {
    final pontosAtuais = op.areaGeoJson != null
        ? _parseGeoJson(op.areaGeoJson!)
        : <LatLng>[];

    final resultado = await Navigator.push<ResultadoAreaSilvi>(
      context,
      MaterialPageRoute(
        builder: (_) => DesenharAreaSilviPage(
          centroide: widget.centroide,
          pontosIniciais: pontosAtuais.isNotEmpty ? pontosAtuais : null,
        ),
      ),
    );

    if (resultado != null && mounted) {
      final atualizada = OperacaoSilvi(
        id: op.id,
        centroideId: op.centroideId,
        talhaoId: op.talhaoId,
        fazendaId: op.fazendaId,
        nomeFazenda: op.nomeFazenda,
        nomeTalhao: op.nomeTalhao,
        tipo: op.tipo,
        areaAplicadaHa: resultado.areaHa,
        areaGeoJson: resultado.geoJson,
        dataExecucao: op.dataExecucao,
        status: op.status,
        observacoes: op.observacoes,
        nomeLider: op.nomeLider,
        fotos: op.fotos,
        latitude: op.latitude,
        longitude: op.longitude,
        exportada: op.exportada,
        isSynced: false,
        lastModified: DateTime.now().toIso8601String(),
      );
      await _repo.atualizarOperacao(atualizada);
      setState(() {
        final idx = _todasOperacoes.indexWhere((o) => o.id == op.id);
        if (idx != -1) _todasOperacoes[idx] = atualizada;
      });
      Future.microtask(_fitBounds);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mapProvider = context.watch<MapProvider>();
    final areas = _areas;
    final tiposVisiveis = _tiposFiltrados.isEmpty
        ? _tiposDisponiveis
        : _tiposFiltrados;
    final areaTotalHa = widget.centroide.areaTotalHa;
    final temFiltroAtivo = _tiposFiltrados.isNotEmpty || _mesesFiltrados.isNotEmpty;
    final temPdf = mapProvider.pdfTilesDir != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.centroide.nomeFazenda,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            Text(widget.centroide.nomeTalhao,
                style:
                    const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          // Filtro
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filtrar',
                onPressed: () =>
                    setState(() => _filtroExpandido = !_filtroExpandido),
              ),
              if (temFiltroAtivo)
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
            onPressed: () {
              if (temPdf) {
                mapProvider.togglePdfOverlay();
              } else {
                mapProvider.importPdfOverlay(context);
              }
            },
          ),
          IconButton(
            icon: Icon(_satellite ? Icons.map_outlined : Icons.satellite_alt),
            tooltip: _satellite ? 'Modo ruas' : 'Modo satélite',
            onPressed: () => setState(() => _satellite = !_satellite),
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen),
            tooltip: 'Ajustar à área',
            onPressed: _fitBounds,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Painel de filtro (expansível) ─────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: _filtroExpandido
                ? _buildFiltroPanel()
                : const SizedBox.shrink(),
          ),

          // ── Barra de progresso por tipo ───────────────────────────────
          if (tiposVisiveis.isNotEmpty)
            Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...tiposVisiveis.map((tipo) {
                    final tipoEnum = OperacaoSilviTipo.fromString(tipo);
                    final executado = _somarAreaFiltrada(tipo);
                    final pct = areaTotalHa != null && areaTotalHa > 0
                        ? (executado / areaTotalHa).clamp(0.0, 1.0)
                        : null;
                    // Extras deste tipo vindos do planejamento (espécie, produto, etc.)
                    final planejado = widget.centroide.operacoesPlanejadas
                        .where((p) => p.tipo == tipo)
                        .firstOrNull;
                    final extras = planejado?.extras ?? {};
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(tipoEnum.icon, color: tipoEnum.color, size: 15),
                              const SizedBox(width: 6),
                              SizedBox(
                                  width: 76,
                                  child: Text(tipoEnum.label,
                                      style: const TextStyle(fontSize: 12))),
                              Expanded(
                                child: pct != null
                                    ? LinearProgressIndicator(
                                        value: pct,
                                        backgroundColor: Colors.grey.shade300,
                                        color: tipoEnum.color,
                                        minHeight: 7,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                areaTotalHa != null
                                    ? '${executado.toStringAsFixed(1)} / ${areaTotalHa.toStringAsFixed(0)} ha'
                                    : '${executado.toStringAsFixed(1)} ha',
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          if (extras.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 21, top: 1, bottom: 1),
                              child: Text(
                                extras.entries
                                    .map((e) => '${e.key}: ${e.value}')
                                    .join('  ·  '),
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey.shade600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  // Linha de área total do talhão (quando não há progresso por tipo)
                  if (areaTotalHa != null && tiposVisiveis.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'Área total talhão: ${areaTotalHa.toStringAsFixed(2)} ha',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                      ),
                    ),
                ],
              ),
            ),

          // ── Mapa ──────────────────────────────────────────────────────
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(
                    widget.centroide.latitude, widget.centroide.longitude),
                initialZoom: 15,
                minZoom: 3,
                maxZoom: 19,
                onMapReady: () {
                  setState(() => _mapReady = true);
                  Future.microtask(_fitBounds);
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
                if (areas.isNotEmpty)
                  PolygonLayer(
                    polygons: areas
                        .map((a) => Polygon(
                              points: a.pontos,
                              color: a.color.withValues(alpha: 0.35),
                              borderColor: a.color,
                              borderStrokeWidth: 2.5,
                              label: _formatDate(a.op.dataExecucao),
                              labelStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(color: Colors.black54, blurRadius: 4)
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(widget.centroide.latitude,
                          widget.centroide.longitude),
                      width: 30,
                      height: 30,
                      child: Icon(Icons.location_pin,
                          color: Colors.red.shade700, size: 30),
                    ),
                  ],
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

          // ── Legenda / cards de operações ──────────────────────────────
          Container(
            color: Theme.of(context).colorScheme.surface,
            constraints: const BoxConstraints(maxHeight: 130),
            child: areas.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Nenhuma operação com área desenhada.\nUse o filtro ou adicione áreas nas operações.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    scrollDirection: Axis.horizontal,
                    itemCount: areas.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final a = areas[i];
                      final tipoEnum =
                          OperacaoSilviTipo.fromString(a.op.tipo);
                      return GestureDetector(
                        onTap: () => _mostrarOpcoesCard(a),
                        child: Card(
                          color: a.color.withValues(alpha: 0.12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                                color: a.color.withValues(alpha: 0.4)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                            color: a.color,
                                            shape: BoxShape.circle)),
                                    const SizedBox(width: 5),
                                    Text(tipoEnum.label,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(_formatDate(a.op.dataExecucao),
                                    style:
                                        const TextStyle(fontSize: 11)),
                                if (a.op.areaAplicadaHa != null)
                                  Text(
                                    '${a.op.areaAplicadaHa!.toStringAsFixed(2)} ha',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: a.color),
                                  ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit_outlined,
                                        size: 12, color: Colors.grey.shade500),
                                    const SizedBox(width: 3),
                                    Text('Editar área',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade500)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Painel de filtro ───────────────────────────────────────────────────────

  Widget _buildFiltroPanel() {
    final tipos = _tiposDisponiveis.toList()..sort();
    final meses = _mesesDisponiveis.toList()..sort();
    final temFiltro = _tiposFiltrados.isNotEmpty || _mesesFiltrados.isNotEmpty;

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Filtrar por:',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (temFiltro)
                TextButton(
                  onPressed: () => setState(() {
                    _tiposFiltrados.clear();
                    _mesesFiltrados.clear();
                  }),
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(60, 28)),
                  child: const Text('Limpar filtros',
                      style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
          // Chips de tipo
          if (tipos.isNotEmpty) ...[
            const Text('Operação',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: tipos.map((tipo) {
                final tipoEnum = OperacaoSilviTipo.fromString(tipo);
                final selecionado = _tiposFiltrados.contains(tipo);
                return FilterChip(
                  avatar:
                      Icon(tipoEnum.icon, size: 14, color: tipoEnum.color),
                  label: Text(tipoEnum.label,
                      style: const TextStyle(fontSize: 11)),
                  selected: selecionado,
                  onSelected: (v) => setState(() {
                    v
                        ? _tiposFiltrados.add(tipo)
                        : _tiposFiltrados.remove(tipo);
                  }),
                  selectedColor: tipoEnum.color.withValues(alpha: 0.2),
                  checkmarkColor: tipoEnum.color,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                );
              }).toList(),
            ),
          ],
          // Chips de mês/ano
          if (meses.length > 1) ...[
            const SizedBox(height: 6),
            const Text('Data',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: meses.map((mes) {
                final selecionado = _mesesFiltrados.contains(mes);
                return FilterChip(
                  label: Text(mes, style: const TextStyle(fontSize: 11)),
                  selected: selecionado,
                  onSelected: (v) => setState(() {
                    v
                        ? _mesesFiltrados.add(mes)
                        : _mesesFiltrados.remove(mes);
                  }),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ── Bottom sheet do card ───────────────────────────────────────────────────

  void _mostrarOpcoesCard(_AreaData a) {
    final tipoEnum = OperacaoSilviTipo.fromString(a.op.tipo);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: a.color.withValues(alpha: 0.15),
                child: Icon(tipoEnum.icon, color: a.color),
              ),
              title: Text(tipoEnum.label,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${_formatDate(a.op.dataExecucao)}'
                '${a.op.areaAplicadaHa != null ? "  •  ${a.op.areaAplicadaHa!.toStringAsFixed(2)} ha" : ""}',
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.draw_outlined),
              title: const Text('Editar área no mapa'),
              subtitle: const Text('Ajuste o polígono desenhado'),
              onTap: () {
                Navigator.pop(context);
                _editarArea(a.op);
              },
            ),
            ListTile(
              leading: const Icon(Icons.center_focus_strong_outlined),
              title: const Text('Centralizar no mapa'),
              onTap: () {
                Navigator.pop(context);
                if (a.pontos.isNotEmpty) {
                  _mapController.fitCamera(
                    CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(a.pontos),
                      padding: const EdgeInsets.all(50),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _AreaData {
  final OperacaoSilvi op;
  final List<LatLng> pontos;
  final Color color;

  const _AreaData({
    required this.op,
    required this.pontos,
    required this.color,
  });
}

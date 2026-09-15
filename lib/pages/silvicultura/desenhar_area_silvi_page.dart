import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:geoforestv1/models/silvi_model.dart';
import 'package:geoforestv1/providers/map_provider.dart';
import 'package:geoforestv1/services/pdf_tile_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

/// Resultado do desenho de área — retornado via Navigator.pop().
class ResultadoAreaSilvi {
  final double areaHa;
  final String geoJson;
  final List<LatLng> pontos;

  const ResultadoAreaSilvi({
    required this.areaHa,
    required this.geoJson,
    required this.pontos,
  });
}

/// Tela de desenho de polígono para delimitar a área de uma operação silvicultural.
///
/// • Toque no mapa → adiciona vértice
/// • Arraste um vértice → reposiciona (ajuste fino da área)
/// • Long press num vértice → remove aquele ponto
/// • Desfazer → remove o último ponto adicionado
/// • Limpar → apaga tudo
/// • Confirmar → retorna [ResultadoAreaSilvi]
class DesenharAreaSilviPage extends StatefulWidget {
  final CentroideSilvi centroide;

  /// Polígono já existente (modo edição) — null para novo desenho.
  final List<LatLng>? pontosIniciais;

  const DesenharAreaSilviPage({
    super.key,
    required this.centroide,
    this.pontosIniciais,
  });

  @override
  State<DesenharAreaSilviPage> createState() => _DesenharAreaSilviPageState();
}

class _DesenharAreaSilviPageState extends State<DesenharAreaSilviPage> {
  final _mapController = MapController();
  final List<LatLng> _pontos = [];

  bool _satellite = true;
  bool _isDragging = false;

  // GPS
  Position? _currentPosition;
  bool _followingUser = false;
  StreamSubscription<Position>? _positionSub;

  static const _satUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const _osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  @override
  void initState() {
    super.initState();
    if (widget.pontosIniciais != null) {
      _pontos.addAll(widget.pontosIniciais!);
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  // ── Área (Shoelace projetado em metros) ────────────────────────────────────

  double _calcularAreaM2(List<LatLng> pts) {
    if (pts.length < 3) return 0;
    final centerLat =
        pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
    const latScale = 111319.9;
    final lonScale = 111319.9 * cos(centerLat * pi / 180);
    final local = pts
        .map((p) => [
              (p.longitude - pts.first.longitude) * lonScale,
              (p.latitude - pts.first.latitude) * latScale,
            ])
        .toList();
    double area = 0;
    for (int i = 0; i < local.length; i++) {
      final j = (i + 1) % local.length;
      area += local[i][0] * local[j][1];
      area -= local[j][0] * local[i][1];
    }
    return area.abs() / 2;
  }

  // ── GeoJSON ────────────────────────────────────────────────────────────────

  String _toGeoJson(List<LatLng> pts) {
    final coords = [
      ...pts.map((p) => [p.longitude, p.latitude]),
      [pts.first.longitude, pts.first.latitude],
    ];
    return jsonEncode({
      'type': 'Feature',
      'geometry': {
        'type': 'Polygon',
        'coordinates': [coords],
      },
      'properties': {
        'nomeFazenda': widget.centroide.nomeFazenda,
        'nomeTalhao': widget.centroide.nomeTalhao,
      },
    });
  }

  // ── GPS ────────────────────────────────────────────────────────────────────

  Future<void> _toggleGps() async {
    if (_followingUser) {
      await _positionSub?.cancel();
      _positionSub = null;
      setState(() => _followingUser = false);
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GPS desabilitado. Ative nas configurações.')),
      );
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissão de GPS negada permanentemente.')),
      );
      return;
    }

    // Primeira posição imediata
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _followingUser = true;
      });
      _mapController.move(
        LatLng(pos.latitude, pos.longitude),
        _mapController.camera.zoom,
      );
    } catch (_) {}

    // Stream contínuo
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() => _currentPosition = pos);
      if (_followingUser) {
        _mapController.move(
          LatLng(pos.latitude, pos.longitude),
          _mapController.camera.zoom,
        );
      }
    });
  }

  // ── Ações ──────────────────────────────────────────────────────────────────

  void _onMapTap(TapPosition _, LatLng ponto) {
    if (_isDragging) return;
    setState(() => _pontos.add(ponto));
  }

  void _removerPonto(int index) {
    if (_pontos.length <= 1) {
      setState(() => _pontos.clear());
      return;
    }
    setState(() => _pontos.removeAt(index));
  }

  void _desfazer() {
    if (_pontos.isNotEmpty) setState(() => _pontos.removeLast());
  }

  void _limpar() => setState(() => _pontos.clear());

  void _salvar() {
    if (_pontos.length < 3) return;
    final areaM2 = _calcularAreaM2(_pontos);
    Navigator.pop(
      context,
      ResultadoAreaSilvi(
        areaHa: areaM2 / 10000,
        geoJson: _toGeoJson(_pontos),
        pontos: List.from(_pontos),
      ),
    );
  }

  // ── PDF controls ───────────────────────────────────────────────────────────

  Widget _buildPdfControls(MapProvider mapProvider) {
    if (!mapProvider.showPdfOverlay || mapProvider.pdfTilesDir == null) {
      return const SizedBox.shrink();
    }
    return Positioned(
      top: 10,
      right: 10,
      child: Card(
        color: Colors.black.withValues(alpha: 0.65),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.opacity, color: Colors.white, size: 16),
              SizedBox(
                width: 110,
                child: Slider(
                  value: mapProvider.pdfOverlayOpacity,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  onChanged: (v) =>
                      context.read<MapProvider>().setPdfOpacity(v),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Remover PDF?'),
                      content: const Text(
                          'O PDF de referência será removido do mapa.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Remover'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && mounted) {
                    context.read<MapProvider>().clearPdfOverlay();
                  }
                },
                child: const Icon(Icons.delete_outline,
                    color: Colors.redAccent, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Drag marker builders ───────────────────────────────────────────────────

  List<DragMarker> _buildDragMarkers() {
    return _pontos.asMap().entries.map((e) {
      final idx = e.key;
      final isFirst = idx == 0;

      return DragMarker(
        point: e.value,
        size: const Size(28, 28),
        onDragStart: (_, __) => setState(() => _isDragging = true),
        onDragUpdate: (_, newPt) => setState(() => _pontos[idx] = newPt),
        onDragEnd: (_, newPt) {
          setState(() {
            _pontos[idx] = newPt;
            Future.delayed(const Duration(milliseconds: 150),
                () => _isDragging = false);
          });
        },
        onLongPress: (_) => _removerPonto(idx),
        builder: (ctx, pos, isDragging) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: isFirst
                ? Colors.green.shade700
                : isDragging
                    ? Colors.orange.shade600
                    : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isFirst
                  ? Colors.white
                  : isDragging
                      ? Colors.orange.shade800
                      : Colors.green.shade700,
              width: isDragging ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDragging ? 0.4 : 0.25),
                blurRadius: isDragging ? 8 : 3,
              )
            ],
          ),
          child: isDragging
              ? Icon(Icons.open_with, size: 14, color: Colors.orange.shade900)
              : null,
        ),
      );
    }).toList();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mapProvider = context.watch<MapProvider>();
    final areaM2 = _calcularAreaM2(_pontos);
    final areaHa = areaM2 / 10000;
    final temPoligono = _pontos.length >= 3;
    final temPdf = mapProvider.pdfTilesDir != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.centroide.nomeFazenda,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            Text(widget.centroide.nomeTalhao,
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          // Botão PDF
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
          // Satélite / ruas
          IconButton(
            icon: Icon(_satellite ? Icons.map_outlined : Icons.satellite_alt),
            tooltip: _satellite ? 'Modo ruas' : 'Modo satélite',
            onPressed: () => setState(() => _satellite = !_satellite),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(
                widget.centroide.latitude,
                widget.centroide.longitude,
              ),
              initialZoom: 16,
              minZoom: 3,
              maxZoom: 19,
              onTap: _onMapTap,
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && _followingUser) {
                  setState(() => _followingUser = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _satellite ? _satUrl : _osmUrl,
                userAgentPackageName: 'com.example.geoforestv1',
              ),

              // PDF overlay
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

              // Polígono em construção
              if (temPoligono)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _pontos,
                      color: Colors.green.withValues(alpha: 0.25),
                      borderColor: Colors.green.shade600,
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),

              // Linhas antes de fechar o polígono
              if (_pontos.length >= 2 && !temPoligono)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _pontos,
                      color: Colors.orange,
                      strokeWidth: 2,
                    ),
                  ],
                ),

              // Vértices arrastáveis
              DragMarkers(markers: _buildDragMarkers()),

              // Centróide de referência
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
                  // Posição GPS do usuário
                  if (_currentPosition != null)
                    Marker(
                      point: LatLng(_currentPosition!.latitude,
                          _currentPosition!.longitude),
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.shade600,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4)
                          ],
                        ),
                      ),
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

          // Controles de opacidade + remover PDF
          _buildPdfControls(mapProvider),

          // FABs à esquerda (GPS + centralizar no PDF)
          Positioned(
            top: 10,
            left: 10,
            child: Column(
              children: [
                // GPS follow
                FloatingActionButton(
                  heroTag: 'silvi_gps_fab',
                  onPressed: _toggleGps,
                  tooltip: _followingUser ? 'Parar GPS' : 'Minha localização',
                  backgroundColor:
                      _followingUser ? Colors.blue : Colors.green.shade700,
                  foregroundColor: Colors.white,
                  child: Icon(_followingUser
                      ? Icons.gps_fixed
                      : Icons.gps_not_fixed),
                ),
                // Centralizar no PDF (só quando PDF visível)
                if (temPdf &&
                    mapProvider.showPdfOverlay &&
                    mapProvider.pdfOverlayBounds != null) ...[
                  const SizedBox(height: 10),
                  FloatingActionButton(
                    heroTag: 'silvi_pdf_center_fab',
                    mini: true,
                    onPressed: () {
                      _mapController.fitCamera(CameraFit.bounds(
                        bounds: mapProvider.pdfOverlayBounds!,
                        padding: const EdgeInsets.all(40),
                      ));
                    },
                    tooltip: 'Centralizar no PDF',
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    child: const Icon(Icons.picture_as_pdf),
                  ),
                ],
              ],
            ),
          ),

          // Instrução flutuante
          Positioned(
            top: 8,
            left: 70,
            right: 10,
            child: Center(
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Text(
                    _pontos.isEmpty
                        ? 'Toque no mapa para adicionar pontos'
                        : _pontos.length < 3
                            ? 'Mín. 3 pontos para fechar a área'
                            : '${_pontos.length} pts · ${areaHa.toStringAsFixed(2)} ha  •  arraste para ajustar',
                    style:
                        const TextStyle(color: Colors.white, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),

          // Dica de long press
          if (_pontos.isNotEmpty)
            Positioned(
              bottom: 76,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Text(
                      'Segure um ponto para removê-lo',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),

      // Barra de controles
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 64,
          color: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              IconButton(
                onPressed: _pontos.isNotEmpty ? _desfazer : null,
                icon: const Icon(Icons.undo),
                tooltip: 'Desfazer último ponto',
              ),
              IconButton(
                onPressed: _pontos.isNotEmpty ? _limpar : null,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Limpar tudo',
                color: Colors.red,
              ),
              const Spacer(),
              if (temPoligono)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${areaHa.toStringAsFixed(2)} ha',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.green.shade700),
                      ),
                      Text(
                        '${areaM2.toStringAsFixed(0)} m²',
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              FilledButton.icon(
                onPressed: temPoligono ? _salvar : null,
                icon: const Icon(Icons.check),
                label: const Text('Confirmar'),
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

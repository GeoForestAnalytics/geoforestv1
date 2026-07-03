// lib/providers/map_provider.dart

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/imported_feature_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/sample_point.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/services/activity_optimizer_service.dart';
import 'package:geoforestv1/services/export_service.dart';
import 'package:geoforestv1/services/geojson_service.dart';
import 'package:geoforestv1/services/sampling_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/fazenda_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/utils/app_config.dart';

enum MapLayerType { ruas, satelite, sateliteMapbox }

class MapProvider with ChangeNotifier {
  final _geoJsonService = GeoJsonService();
  final _dbHelper = DatabaseHelper.instance;
  final _samplingService = SamplingService();
  late final ActivityOptimizerService _optimizerService;
  final _exportService = ExportService();
  
  final _parcelaRepository = ParcelaRepository();
  final _fazendaRepository = FazendaRepository();
  final _talhaoRepository = TalhaoRepository();
  
  static final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

  List<ImportedPolygonFeature> _importedPolygons = [];
  List<SamplePoint> _samplePoints = [];
  bool _isLoading = false;
  Atividade? _currentAtividade;
  MapLayerType _currentLayer = MapLayerType.satelite;
  Position? _currentUserPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isFollowingUser = false;
  bool _isDrawing = false;
  final List<LatLng> _drawnPoints = [];

  MapProvider() {
    _optimizerService = ActivityOptimizerService(dbHelper: _dbHelper);
    _loadSavedPdfPath();
  }

  // Getters
  bool get isDrawing => _isDrawing;
  List<LatLng> get drawnPoints => _drawnPoints;
  List<Polygon> get polygons => _importedPolygons.map((f) => f.polygon).toList();
  List<SamplePoint> get samplePoints => _samplePoints;
  bool get isLoading => _isLoading;
  Atividade? get currentAtividade => _currentAtividade;
  MapLayerType get currentLayer => _currentLayer;
  Position? get currentUserPosition => _currentUserPosition;
  bool get isFollowingUser => _isFollowingUser;

  // <<< INÍCIO DAS NOVAS ADIÇÕES >>>

  SamplePoint? _goToTarget; // Armazena a amostra de destino no modo "Ir para"
  bool _followingIniciadoPeloGoTo = false; // Controla se fomos nós que ligamos o GPS ao entrar no "Ir para"

  SamplePoint? get goToTarget => _goToTarget;
  bool get isGoToModeActive => _goToTarget != null;

  /// Inicia o modo de navegação "Ir para" (linha reta), garantindo que o GPS
  /// fique acompanhando continuamente mesmo que o usuário não tenha apertado
  /// o botão "Minha Localização" antes.
  void startGoTo(SamplePoint target) {
    _goToTarget = target;
    if (!_isFollowingUser) {
      toggleFollowingUser();
      _followingIniciadoPeloGoTo = true;
    }
    notifyListeners(); // Avisa a UI que o modo mudou
  }

  /// Para o modo de navegação "Ir para".
  void stopGoTo() {
    _goToTarget = null;
    if (_followingIniciadoPeloGoTo && _isFollowingUser) {
      toggleFollowingUser();
    }
    _followingIniciadoPeloGoTo = false;
    notifyListeners(); // Avisa a UI que o modo mudou
  }

  /// Abre um aplicativo de mapa externo (Google Maps) para navegar até o ponto.
  Future<void> launchNavigation(LatLng destination) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}';
    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // Lança uma exceção ou mostra um erro se não conseguir abrir
      throw 'Não foi possível abrir o aplicativo de mapas.';
    }
  }

  /// Retorna as informações de distância e direção para a UI.
  Map<String, String> getGoToInfo() {
    if (!isGoToModeActive || _currentUserPosition == null) {
      return {'distance': '- m', 'bearing': '- °'};
    }

    const distance = Distance();
    final start = LatLng(_currentUserPosition!.latitude, _currentUserPosition!.longitude);
    final end = _goToTarget!.position;

    final distanceInMeters = distance.as(LengthUnit.Meter, start, end);
    
    // <<< CORREÇÃO APLICADA AQUI >>>
    // O nome correto do método é 'bearing'
    final bearing = distance.bearing(start, end);

    return {
      'distance': '${distanceInMeters.toStringAsFixed(0)} m',
      'bearing': '${bearing.toStringAsFixed(0)}° ${_formatBearing(bearing)}'
    };
  }

  /// Função auxiliar para converter o ângulo em uma direção cardinal (N, NE, S, etc.)
  String _formatBearing(double bearing) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'N'];
    return directions[((bearing % 360) / 45).round()];
  }

  // <<< FIM DAS NOVAS ADIÇÕES >>>

  // --- PDF de Referência (Overlay Georreferenciado) ---
  String? _importedPdfPath;
  String? _pdfTilesDir;
  LatLngBounds? _pdfOverlayBounds;
  double _pdfOverlayOpacity = 0.7;
  bool _showPdfOverlay = false;

  String? get importedPdfPath => _importedPdfPath;
  String? get pdfTilesDir => _pdfTilesDir;
  LatLngBounds? get pdfOverlayBounds => _pdfOverlayBounds;
  double get pdfOverlayOpacity => _pdfOverlayOpacity;
  bool get showPdfOverlay => _showPdfOverlay;

  Future<void> _loadSavedPdfPath() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('pdf_overlay_path');
    final swLat = prefs.getDouble('pdf_sw_lat');
    final swLon = prefs.getDouble('pdf_sw_lon');
    final neLat = prefs.getDouble('pdf_ne_lat');
    final neLon = prefs.getDouble('pdf_ne_lon');

    if (savedPath != null && await File(savedPath).exists() &&
        swLat != null && swLon != null && neLat != null && neLon != null) {
      final bounds = LatLngBounds(LatLng(swLat, swLon), LatLng(neLat, neLon));
      final pdfId = '${savedPath.hashCode.abs().toRadixString(16)}_v2';
      final tempDir = await getTemporaryDirectory();
      final tilesDir = '${tempDir.path}/geoforest_pdf_tiles/$pdfId';
      if (await File('$tilesDir/.done').exists()) {
        _importedPdfPath = savedPath;
        _pdfTilesDir = tilesDir;
        _pdfOverlayBounds = bounds;
        _showPdfOverlay = true;
        notifyListeners();
      } else {
        await prefs.remove('pdf_overlay_path');
      }
    } else if (savedPath != null) {
      await prefs.remove('pdf_overlay_path');
    }
  }

  // Helpers de conversão tile ↔ lat/lon (Web Mercator)
  int _lonToTileX(double lon, int z) => ((lon + 180.0) / 360.0 * (1 << z)).floor();
  int _latToTileY(double lat, int z) {
    final r = lat * math.pi / 180.0;
    return ((1.0 - math.log(math.tan(r) + 1.0 / math.cos(r)) / math.pi) / 2.0 * (1 << z)).floor();
  }
  double _tileXToLon(int tx, int z) => tx / (1 << z) * 360.0 - 180.0;
  double _tileYToLat(int ty, int z) {
    final n = math.pi * (1.0 - 2.0 * ty / (1 << z));
    return 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  // Mercator Y usada para calcular fullH e py corretamente (projeção Web Mercator)
  double _latToMercY(double lat) {
    final r = lat * math.pi / 180.0;
    return math.log(math.tan(math.pi / 4.0 + r / 2.0));
  }

  Future<String> _generatePdfTiles(String filePath, LatLngBounds bounds) async {
    final pdfId = '${filePath.hashCode.abs().toRadixString(16)}_v2';
    final tempDir = await getTemporaryDirectory();
    final tilesDir = '${tempDir.path}/geoforest_pdf_tiles/$pdfId';
    final markerFile = File('$tilesDir/.done');
    if (await markerFile.exists()) return tilesDir;

    await Directory(tilesDir).create(recursive: true);

    final minLon = bounds.west;
    final maxLon = bounds.east;
    final minLat = bounds.south;
    final maxLat = bounds.north;

    final mercYMax = _latToMercY(maxLat);
    final mercYMin = _latToMercY(minLat);

    final doc = await PdfDocument.openFile(filePath);
    try {
      final page = doc.pages[0];

      for (int z = 13; z <= 17; z++) {
        // fullW: baseado na longitude (linear em Mercator) ✓
        final fullW = (maxLon - minLon) / 360.0 * (1 << z) * 256.0;
        // fullH: baseado na projeção Mercator do intervalo de latitude ✓
        final fullH = (mercYMax - mercYMin) / (2 * math.pi) * (1 << z) * 256.0;

        final x0 = _lonToTileX(minLon, z);
        final x1 = _lonToTileX(maxLon, z);
        final y0 = _latToTileY(maxLat, z);
        final y1 = _latToTileY(minLat, z);

        for (int tx = x0; tx <= x1; tx++) {
          for (int ty = y0; ty <= y1; ty++) {
            final lonL = _tileXToLon(tx, z);
            final latT = _tileYToLat(ty, z);
            final mercYT = _latToMercY(latT);
            // px: longitude é linear em Mercator ✓
            final px = ((lonL - minLon) / (maxLon - minLon) * fullW).round();
            // py: usa Mercator Y para projeção correta (sem deformação) ✓
            final py = ((mercYMax - mercYT) / (mercYMax - mercYMin) * fullH).round();

            final img = await page.render(
              x: px,
              y: py,
              width: 256,
              height: 256,
              fullWidth: fullW,
              fullHeight: fullH,
              backgroundColor: 0x00000000,
            );

            if (img != null) {
              final uiImg = await img.createImage();
              final bd = await uiImg.toByteData(format: ui.ImageByteFormat.png);
              uiImg.dispose();
              if (bd != null) {
                final tileDir = Directory('$tilesDir/$z');
                await tileDir.create(recursive: true);
                await File('$tilesDir/$z/${tx}_$ty.png').writeAsBytes(bd.buffer.asUint8List());
              }
            }
            await Future.delayed(Duration.zero);
          }
        }
      }
      await markerFile.writeAsString('done');
    } finally {
      await doc.dispose();
    }
    return tilesDir;
  }

  /// Tenta extrair as coordenadas geográficas embutidas no PDF (formato GeoPDF/Adobe).
  Future<LatLngBounds?> _tryExtractPdfGeoBounds(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      // Converte para string ignorando bytes binários (>127)
      final content = String.fromCharCodes(bytes.map((b) => b < 128 ? b : 32));

      final match = RegExp(r'/GPTS\s*\[([^\]]+)\]').firstMatch(content);
      if (match == null) return null;

      final nums = match
          .group(1)!
          .trim()
          .split(RegExp(r'[\s,]+'))
          .where((s) => s.isNotEmpty)
          .map(double.parse)
          .toList();

      if (nums.length < 8) return null;

      // Formato GPTS: [lat1 lon1 lat2 lon2 lat3 lon3 lat4 lon4]
      final lats = [for (int i = 0; i < nums.length; i += 2) nums[i]];
      final lons = [for (int i = 1; i < nums.length; i += 2) nums[i]];

      final south = lats.reduce((a, b) => a < b ? a : b);
      final north = lats.reduce((a, b) => a > b ? a : b);
      final west = lons.reduce((a, b) => a < b ? a : b);
      final east = lons.reduce((a, b) => a > b ? a : b);

      // Sanidade: valores válidos de lat/lon
      if (south < -90 || north > 90 || west < -180 || east > 180) return null;
      if (north - south < 0.0001 || east - west < 0.0001) return null;

      return LatLngBounds(LatLng(south, west), LatLng(north, east));
    } catch (e) {
      debugPrint('Auto-extract PDF geo bounds failed: $e');
      return null;
    }
  }

  Future<void> importPdfOverlay(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.single.path == null) return;
    if (!context.mounted) return;

    final filePath = result.files.single.path!;

    // Tenta extrair coordenadas automaticamente
    _setLoading(true);
    LatLngBounds? autoBounds;
    try {
      autoBounds = await _tryExtractPdfGeoBounds(filePath);
    } catch (_) {}
    _setLoading(false);

    LatLngBounds bounds;

    if (autoBounds != null) {
      bounds = autoBounds;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Coordenadas lidas automaticamente do PDF!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      // Fallback: pede as coordenadas manualmente
      if (!context.mounted) return;
      final boundsData = await _showPdfBoundsDialog(context);
      if (boundsData == null) return;

      final zone = boundsData['zone'] as int;
      final epsg = 31978 + (zone - 18);
      final projUTM = proj4.Projection.get('EPSG:$epsg') ??
          proj4.Projection.parse(proj4Definitions[epsg]!);
      final projWGS84 = proj4.Projection.get('EPSG:4326')!;

      final sw = projUTM.transform(projWGS84,
          proj4.Point(x: boundsData['swE'] as double, y: boundsData['swN'] as double));
      final ne = projUTM.transform(projWGS84,
          proj4.Point(x: boundsData['neE'] as double, y: boundsData['neN'] as double));

      bounds = LatLngBounds(LatLng(sw.y, sw.x), LatLng(ne.y, ne.x));
    }

    _setLoading(true);
    try {
      final tilesDir = await _generatePdfTiles(filePath, bounds);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pdf_overlay_path', filePath);
      await prefs.setDouble('pdf_sw_lat', bounds.south);
      await prefs.setDouble('pdf_sw_lon', bounds.west);
      await prefs.setDouble('pdf_ne_lat', bounds.north);
      await prefs.setDouble('pdf_ne_lon', bounds.east);

      _importedPdfPath = filePath;
      _pdfTilesDir = tilesDir;
      _pdfOverlayBounds = bounds;
      _showPdfOverlay = true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao processar PDF: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<Map<String, dynamic>?> _showPdfBoundsDialog(BuildContext context) {
    final swECtrl = TextEditingController();
    final swNCtrl = TextEditingController();
    final neECtrl = TextEditingController();
    final neNCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    int selectedZone = 22;

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Coordenadas do Mapa PDF'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Copie os valores numéricos das margens do mapa PDF.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: selectedZone,
                    decoration: const InputDecoration(labelText: 'Zona UTM Sul'),
                    items: List.generate(8, (i) => i + 18)
                        .map((z) => DropdownMenuItem(value: z, child: Text('Zona ${z}S')))
                        .toList(),
                    onChanged: (v) => setState(() => selectedZone = v!),
                  ),
                  const SizedBox(height: 16),
                  const Text('Canto SW — inferior esquerdo',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: swECtrl,
                        decoration: const InputDecoration(labelText: 'Leste (E)', hintText: '713500'),
                        keyboardType: TextInputType.number,
                        validator: (v) => v == null || v.isEmpty ? 'Obrigatório' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: swNCtrl,
                        decoration: const InputDecoration(labelText: 'Norte (N)', hintText: '7406000'),
                        keyboardType: TextInputType.number,
                        validator: (v) => v == null || v.isEmpty ? 'Obrigatório' : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  const Text('Canto NE — superior direito',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: neECtrl,
                        decoration: const InputDecoration(labelText: 'Leste (E)', hintText: '721500'),
                        keyboardType: TextInputType.number,
                        validator: (v) => v == null || v.isEmpty ? 'Obrigatório' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: neNCtrl,
                        decoration: const InputDecoration(labelText: 'Norte (N)', hintText: '7411500'),
                        keyboardType: TextInputType.number,
                        validator: (v) => v == null || v.isEmpty ? 'Obrigatório' : null,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, {
                    'swE': double.parse(swECtrl.text.replaceAll(',', '.')),
                    'swN': double.parse(swNCtrl.text.replaceAll(',', '.')),
                    'neE': double.parse(neECtrl.text.replaceAll(',', '.')),
                    'neN': double.parse(neNCtrl.text.replaceAll(',', '.')),
                    'zone': selectedZone,
                  });
                }
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  void togglePdfOverlay() {
    _showPdfOverlay = !_showPdfOverlay;
    notifyListeners();
  }

  void setPdfOpacity(double opacity) {
    _pdfOverlayOpacity = opacity;
    notifyListeners();
  }

  Future<void> clearPdfOverlay() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pdf_overlay_path');
    await prefs.remove('pdf_sw_lat');
    await prefs.remove('pdf_sw_lon');
    await prefs.remove('pdf_ne_lat');
    await prefs.remove('pdf_ne_lon');
    if (_pdfTilesDir != null) {
      final dir = Directory(_pdfTilesDir!);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    _importedPdfPath = null;
    _pdfTilesDir = null;
    _pdfOverlayBounds = null;
    _showPdfOverlay = false;
    notifyListeners();
  }
  // --- Fim PDF de Referência ---


  final Map<MapLayerType, String> _tileUrls = {
    MapLayerType.ruas: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    MapLayerType.satelite: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    MapLayerType.sateliteMapbox: 'https://api.mapbox.com/styles/v1/mapbox/satellite-v9/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}',
  };

  String get currentTileUrl {
    String url = _tileUrls[_currentLayer]!;
    if (url.contains('{accessToken}')) {
      final token = AppConfig.mapboxAccessToken;
      if (token.isEmpty) return _tileUrls[MapLayerType.satelite]!;
      return url.replaceAll('{accessToken}', token);
    }
    return url;
  }
  
  void switchMapLayer() {
    _currentLayer = MapLayerType.values[(_currentLayer.index + 1) % MapLayerType.values.length];
    notifyListeners();
  }

  void startDrawing() {
    if (!_isDrawing) {
      _isDrawing = true;
      _drawnPoints.clear();
      notifyListeners();
    }
  }

  void cancelDrawing() {
    if (_isDrawing) {
      _isDrawing = false;
      _drawnPoints.clear();
      notifyListeners();
    }
  }

  void addDrawnPoint(LatLng point) {
    if (_isDrawing) {
      _drawnPoints.add(point);
      notifyListeners();
    }
  }

  void undoLastDrawnPoint() {
    if (_isDrawing && _drawnPoints.isNotEmpty) {
      _drawnPoints.removeLast();
      notifyListeners();
    }
  }
  
  Future<void> saveDrawnPolygon(BuildContext context) async {
    if (_drawnPoints.length < 3 || _currentAtividade == null) {
      cancelDrawing();
      return;
    }
  
    final Map<String, String>? dadosDoFormulario = await _showDadosAmostragemDialog(context);
  
    if (dadosDoFormulario == null || !context.mounted) {
      cancelDrawing();
      return;
    }
  
    _setLoading(true);
  
    try {
      final nomeFazenda = dadosDoFormulario['nomeFazenda']!;
      final codigoFazenda = dadosDoFormulario['codigoFazenda']!;
      final nomeTalhao = dadosDoFormulario['nomeTalhao']!;
      final up = dadosDoFormulario['up']!;
      final hectaresPorAmostra = double.parse(dadosDoFormulario['hectares']!);
      final now = DateTime.now().toIso8601String();
  
      final talhaoSalvo = await _dbHelper.database.then((db) async {
        return await db.transaction((txn) async {
          final idFazenda = codigoFazenda.isNotEmpty ? codigoFazenda : nomeFazenda;
  
          Fazenda? fazenda = (await txn.query('fazendas', where: 'id = ? AND atividadeId = ?', whereArgs: [idFazenda, _currentAtividade!.id!])).map((e) => Fazenda.fromMap(e)).firstOrNull;
          if (fazenda == null) {
            fazenda = Fazenda(id: idFazenda, atividadeId: _currentAtividade!.id!, nome: nomeFazenda, municipio: 'N/I', estado: 'N/I');
            final map = fazenda.toMap();
            map['lastModified'] = now;
            await txn.insert('fazendas', map);
          }
  
          final novoTalhao = Talhao(
            fazendaId: fazenda.id,
            fazendaAtividadeId: fazenda.atividadeId,
            nome: nomeTalhao,
          );
          final map = novoTalhao.toMap();
          map['lastModified'] = now;
          final talhaoId = await txn.insert('talhoes', map);
          return novoTalhao.copyWith(id: talhaoId, fazendaNome: fazenda.nome);
        });
      });
  
      final newFeature = ImportedPolygonFeature(
        polygon: Polygon(
          points: List.from(_drawnPoints), 
          color: const Color(0xFF617359).withAlpha(128), 
          borderColor: const Color(0xFF1D4333), 
          borderStrokeWidth: 2,
        ),
        properties: {
          'db_talhao_id': talhaoSalvo.id,
          'db_fazenda_nome': talhaoSalvo.fazendaNome,
          'fazenda_id': talhaoSalvo.fazendaId,
          'talhao_nome': talhaoSalvo.nome,
          'up': up,
          'municipio': 'N/I',
          'estado': 'N/I',
        },
      );
      _importedPolygons.add(newFeature);
  
      await gerarAmostrasParaAtividade(
        hectaresPerSample: hectaresPorAmostra,
        featuresParaProcessar: [newFeature],
      );
  
      _isDrawing = false;
      _drawnPoints.clear();

    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar e gerar amostras: $e'), backgroundColor: Colors.red));
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<Map<String, String>?> _showDadosAmostragemDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nomeFazendaController = TextEditingController();
    final codigoFazendaController = TextEditingController();
    final nomeTalhaoController = TextEditingController();
    final upController = TextEditingController();
    final hectaresController = TextEditingController();
  
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Dados da Amostragem'),
          content: SizedBox(
            width: double.maxFinite,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nomeFazendaController,
                      decoration: const InputDecoration(labelText: 'Nome da Fazenda'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
                    ),
                    TextFormField(
                      controller: codigoFazendaController,
                      decoration: const InputDecoration(labelText: 'Código da Fazenda (Opcional)'),
                    ),
                    TextFormField(
                      controller: upController,
                      decoration: const InputDecoration(labelText: 'UP / Unidade (Opcional)'),
                    ),
                    TextFormField(
                      controller: nomeTalhaoController,
                      decoration: const InputDecoration(labelText: 'Nome do Talhão'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
                    ),
                    TextFormField(
                      controller: hectaresController,
                      decoration: const InputDecoration(labelText: 'Hectares por amostra', suffixText: 'ha'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () {
              nomeFazendaController.dispose();
              codigoFazendaController.dispose();
              nomeTalhaoController.dispose();
              upController.dispose();
              hectaresController.dispose();
              Navigator.pop(context);
            }, child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final result = {
                    'nomeFazenda': nomeFazendaController.text.trim(),
                    'codigoFazenda': codigoFazendaController.text.trim(),
                    'nomeTalhao': nomeTalhaoController.text.trim(),
                    'up': upController.text.trim(),
                    'hectares': hectaresController.text.replaceAll(',', '.'),
                  };
                  nomeFazendaController.dispose();
                  codigoFazendaController.dispose();
                  nomeTalhaoController.dispose();
  
                  upController.dispose();
                  hectaresController.dispose();
                  Navigator.pop(context, result);
                }
              },
              child: const Text('Gerar'),
            ),
          ],
        );
      },
    );
  }
  
  Future<String?> showDensityDialogAndGenerateSamples(BuildContext context) async {
    final density = await _showDensityDialog(context);
    if (density == null) return null;
    return await gerarAmostrasParaAtividade(hectaresPerSample: density);
  }

  Future<double?> _showDensityDialog(BuildContext context) {
    final densityController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Densidade da Amostragem'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: densityController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Hectares por amostra', suffixText: 'ha'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Campo obrigatório';
              if (double.tryParse(value.replaceAll(',', '.')) == null) return 'Número inválido';
              return null;
            }
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, double.parse(densityController.text.replaceAll(',', '.')));
              }
            },
            child: const Text('Gerar'),
          ),
        ],
      ),
    );
  }

  Future<String> gerarAmostrasParaAtividade({
    required double hectaresPerSample,
    List<ImportedPolygonFeature>? featuresParaProcessar,
  }) async {
    final poligonos = featuresParaProcessar ?? _importedPolygons;
    if (poligonos.isEmpty) return "Nenhum polígono de talhão carregado.";
    if (_currentAtividade == null) return "Erro: Atividade atual não definida.";
  
    _setLoading(true);
  
    final pontosGerados = _samplingService.generateMultiTalhaoSamplePoints(
      importedFeatures: poligonos,
      hectaresPerSample: hectaresPerSample,
    );
  
    if (pontosGerados.isEmpty) {
      _setLoading(false);
      return "Nenhum ponto de amostra pôde ser gerado.";
    }
  
    final List<Parcela> parcelasParaSalvar = [];
    int pointIdCounter = 1;
    
    final int? idDoProjetoAtual = _currentAtividade?.projetoId;
  
    for (final ponto in pontosGerados) {
      final props = ponto.properties;
      final talhaoIdSalvo = props['db_talhao_id'] as int?;
      if (talhaoIdSalvo != null) {
         parcelasParaSalvar.add(Parcela(
          talhaoId: talhaoIdSalvo,
          idParcela: pointIdCounter.toString(), 
          areaMetrosQuadrados: 0,
          latitude: ponto.position.latitude, 
          longitude: ponto.position.longitude,
          status: StatusParcela.pendente, 
          dataColeta: DateTime.now(),
          nomeFazenda: props['db_fazenda_nome']?.toString(),
          idFazenda: props['fazenda_id']?.toString(),
          nomeTalhao: props['talhao_nome']?.toString(),
          up: props['up']?.toString(),
          projetoId: idDoProjetoAtual,
          municipio: props['municipio']?.toString(),
          estado: props['estado']?.toString(),
        ));
        pointIdCounter++;
      }
    }
  
    if (parcelasParaSalvar.isNotEmpty) {
      await _parcelaRepository.saveBatchParcelas(parcelasParaSalvar);
      await loadSamplesParaAtividade();
    }
    
    // Se não for uma importação de um novo talhão (desenhado), otimiza a atividade inteira
    if (featuresParaProcessar == null) {
      // A chamada principal ao serviço de otimização acontece aqui!
      final int talhoesRemovidos = await _optimizerService.otimizarAtividade(_currentAtividade!.id!);
      _setLoading(false);
      String mensagemFinal = "${parcelasParaSalvar.length} amostras foram geradas e salvas.";
      // Adiciona o resultado da otimização à mensagem para o usuário
      if (talhoesRemovidos > 0) {
        mensagemFinal += " $talhoesRemovidos talhões vazios foram otimizados.";
      }
      return mensagemFinal;
    } else {
      // Se foi de um novo talhão desenhado, não precisa otimizar a atividade inteira
      _setLoading(false);
      return "${parcelasParaSalvar.length} amostras foram geradas e salvas para o novo talhão.";
    }
  }

  Future<String> _processarPlanoDeAmostragemImportado(List<ImportedPointFeature> pontosImportados, BuildContext context) async {
    _importedPolygons = []; 
    _samplePoints = []; 
    notifyListeners();
  
    final db = await _dbHelper.database;
    final List<Parcela> parcelasParaSalvar = [];
    int novasFazendas = 0;
    int novosTalhoes = 0;
    
    final int? idDoProjetoAtual = _currentAtividade?.projetoId;
    final now = DateTime.now().toIso8601String();
    
    int pointIdCounter = 1;
  
    await db.transaction((txn) async {
      for (final ponto in pontosImportados) {
        final props = ponto.properties;
        
        final fazendaId = (props['fazenda_id'] ?? props['id_fazenda'] ?? props['Fazenda'])?.toString();
        final nomeTalhao = (props['talhao_nome'] ?? props['talhao_id'] ?? props['Talhão'])?.toString();
        
        if (fazendaId == null || nomeTalhao == null) {
          debugPrint("Aviso: Ponto pulado por falta de 'fazenda' ou 'talhao' nas propriedades.");
          continue;
        }
  
        Fazenda? fazenda = (await txn.query('fazendas', where: 'id = ? AND atividadeId = ?', whereArgs: [fazendaId, _currentAtividade!.id!])).map((e) => Fazenda.fromMap(e)).firstOrNull;
        
        if (fazenda == null) {
          final nomeDaFazenda = props['fazenda_nome']?.toString() ?? props['Fazenda']?.toString() ?? fazendaId;
          final municipio = props['municipio']?.toString() ?? 'N/I';
          final estado = props['estado']?.toString() ?? 'N/I';
          fazenda = Fazenda(id: fazendaId, atividadeId: _currentAtividade!.id!, nome: nomeDaFazenda, municipio: municipio, estado: estado);
          final map = fazenda.toMap();
          map['lastModified'] = now;
          await txn.insert('fazendas', map);
          novasFazendas++;
        }
  
        Talhao? talhao = (await txn.query('talhoes', where: 'nome = ? AND fazendaId = ? AND fazendaAtividadeId = ?', whereArgs: [nomeTalhao, fazenda.id, fazenda.atividadeId])).map((e) => Talhao.fromMap(e)).firstOrNull;
        
        // Captura todos os dados do talhão do arquivo
        final areaHaDoArquivo = (props['area_talhao_ha'] as num?)?.toDouble() ?? (props['AreaTalhao'] as num?)?.toDouble();
        final especieDoArquivo = (props['especie'] ?? props['Espécie'])?.toString();
        final espacamentoDoArquivo = (props['espacamento'] ?? props['Espaçament'])?.toString();
        final materialDoArquivo = (props['material'] ?? props['Material'])?.toString();
        final plantioDoArquivo = (props['plantio'] ?? props['Plantio'])?.toString();
        final blocoDoArquivo = (props['bloco'] ?? props['Bloco'])?.toString();
        final rfDoArquivo = (props['rf'] ?? props['RF'])?.toString();
  
        if (talhao == null) {
          // Cria um novo talhão com todos os dados se não existir
          talhao = Talhao(
            fazendaId: fazenda.id, 
            fazendaAtividadeId: fazenda.atividadeId, 
            nome: nomeTalhao,
            areaHa: areaHaDoArquivo,
            especie: especieDoArquivo,
            espacamento: espacamentoDoArquivo,
            materialGenetico: materialDoArquivo,
            dataPlantio: plantioDoArquivo,
            bloco: blocoDoArquivo,
            up: rfDoArquivo,
          );
          final map = talhao.toMap();
          map['lastModified'] = now;
          final talhaoId = await txn.insert('talhoes', map);
          talhao = talhao.copyWith(id: talhaoId);
          novosTalhoes++;
        } else {
          // Se o talhão já existe, verifica se algum campo pode ser atualizado (ex: área)
          final talhaoAtualizado = talhao.copyWith(
            areaHa: (talhao.areaHa == null || talhao.areaHa == 0) ? areaHaDoArquivo : talhao.areaHa,
            especie: talhao.especie ?? especieDoArquivo,
            espacamento: talhao.espacamento ?? espacamentoDoArquivo,
            materialGenetico: talhao.materialGenetico ?? materialDoArquivo,
            dataPlantio: talhao.dataPlantio ?? plantioDoArquivo,
            bloco: talhao.bloco ?? blocoDoArquivo,
            up: talhao.up ?? rfDoArquivo,
          );
          final map = talhaoAtualizado.toMap();
          map['lastModified'] = now;
          await txn.update('talhoes', map, where: 'id = ?', whereArgs: [talhao.id!]);
          talhao = talhaoAtualizado;
        }
        
        parcelasParaSalvar.add(Parcela(
          talhaoId: talhao.id,
          idParcela: pointIdCounter.toString(), 
          areaMetrosQuadrados: (props['area_parcela_m2'] as num?)?.toDouble() ?? (props['ÁreaParcela'] as num?)?.toDouble() ?? 0.0,
          latitude: ponto.position.latitude, 
          longitude: ponto.position.longitude,
          status: StatusParcela.pendente,
          dataColeta: DateTime.now(),
          nomeFazenda: fazenda.nome, 
          idFazenda: fazenda.id, 
          nomeTalhao: talhao.nome,
          up: rfDoArquivo,
          referenciaRf: rfDoArquivo,
          tipoParcela: (props['tipo'] ?? props['Tipo'])?.toString(),
          ciclo: (props['ciclo'] ?? props['Ciclo'])?.toString(),
          rotacao: (props['rotacao'] ?? props['Rotação'] as num?)?.toInt(),
          lado1: (props['lado1'] as num?)?.toDouble(),
          lado2: (props['lado2'] as num?)?.toDouble(),
          observacao: (props['observacao'] ?? props['Observação'])?.toString(),
          altitude: (props['alt_z'] as num?)?.toDouble(),
          projetoId: idDoProjetoAtual,
          municipio: fazenda.municipio,
          estado: fazenda.estado,
        ));
        
        pointIdCounter++;
      }
    });
    
    if (parcelasParaSalvar.isNotEmpty) {
      await _parcelaRepository.saveBatchParcelas(parcelasParaSalvar);
      await loadSamplesParaAtividade();
    }
  
    return "Plano importado: ${parcelasParaSalvar.length} amostras salvas. Novas Fazendas: $novasFazendas, Novos Talhões: $novosTalhoes.";
  }
  
  void clearAllMapData() {
    _importedPolygons = [];
    _samplePoints = [];
    _currentAtividade = null;
    if (_isFollowingUser) toggleFollowingUser();
    if (_isDrawing) cancelDrawing();
    notifyListeners();
  }

  void setCurrentAtividade(Atividade atividade) {
    _currentAtividade = atividade;
  }
  
  Future<String> processarImportacaoDeArquivo({required bool isPlanoDeAmostragem, required BuildContext context}) async {
    if (_currentAtividade == null) {
      return "Erro: Nenhuma atividade selecionada para o planejamento.";
    }
    _setLoading(true);

    try {
      if (isPlanoDeAmostragem) {
        final pontosImportados = await _geoJsonService.importPoints();
        if (pontosImportados.isNotEmpty) {
          return await _processarPlanoDeAmostragemImportado(pontosImportados, context);
        }
      } else {
        final poligonosImportados = await _geoJsonService.importPolygons();
        if (poligonosImportados.isNotEmpty) {
          return await _processarCargaDeTalhoesImportada(poligonosImportados, context);
        }
      }
      
      return "Nenhum dado válido foi encontrado no arquivo selecionado.";
    
    } on GeoJsonParseException catch (e) {
      return e.toString();
    } catch (e) {
      return 'Ocorreu um erro inesperado: ${e.toString()}';
    } finally {
      _setLoading(false);
    }
  }
  
  Future<String> _processarCargaDeTalhoesImportada(List<ImportedPolygonFeature> features, BuildContext context) async {
    _importedPolygons = [];
    _samplePoints = [];
    notifyListeners();

    int fazendasCriadas = 0;
    int talhoesCriados = 0;
    final now = DateTime.now().toIso8601String();
    
    await _dbHelper.database.then((db) async => await db.transaction((txn) async {
      for (final feature in features) {
        final props = feature.properties;
        final fazendaId = (props['id_fazenda'] ?? props['fazenda_id'] ?? props['fazenda_nome'] ?? props['fazenda'])?.toString();
        final nomeTalhao = (props['talhao_nome'] ?? props['talhao_id'] ?? props['talhao'])?.toString();
        
        if (fazendaId == null || nomeTalhao == null) continue;

        Fazenda? fazenda = (await txn.query('fazendas', where: 'id = ? AND atividadeId = ?', whereArgs: [fazendaId, _currentAtividade!.id!])).map((e) => Fazenda.fromMap(e)).firstOrNull;
        if (fazenda == null) {
          final nomeDaFazenda = props['fazenda_nome']?.toString() ?? props['fazenda']?.toString() ?? fazendaId;
          final municipio = props['municipio']?.toString() ?? 'N/I';
          final estado = props['estado']?.toString() ?? 'N/I';
          fazenda = Fazenda(id: fazendaId, atividadeId: _currentAtividade!.id!, nome: nomeDaFazenda, municipio: municipio, estado: estado);
          final map = fazenda.toMap();
          map['lastModified'] = now;
          await txn.insert('fazendas', map);
          fazendasCriadas++;
        }
        
        Talhao? talhao = (await txn.query('talhoes', where: 'nome = ? AND fazendaId = ? AND fazendaAtividadeId = ?', whereArgs: [nomeTalhao, fazenda.id, fazenda.atividadeId])).map((e) => Talhao.fromMap(e)).firstOrNull;
        if (talhao == null) {
          talhao = Talhao(
            fazendaId: fazenda.id, fazendaAtividadeId: fazenda.atividadeId, nome: nomeTalhao,
            especie: props['especie']?.toString(), areaHa: (props['area_ha'] as num?)?.toDouble(),
          );
          final map = talhao.toMap();
          map['lastModified'] = now;
          final talhaoId = await txn.insert('talhoes', map);
          talhao = talhao.copyWith(id: talhaoId);
          talhoesCriados++;
        }
        
        feature.properties['db_talhao_id'] = talhao.id;
        feature.properties['db_fazenda_nome'] = fazenda.nome;
        feature.properties['talhao_nome'] = talhao.nome;
        feature.properties['fazenda_id'] = talhao.fazendaId;
        feature.properties['municipio'] = fazenda.municipio;
        feature.properties['estado'] = fazenda.estado;
      }
    }));
    
    _importedPolygons = features;
    notifyListeners();

    if (context.mounted) {
      final density = await _showDensityDialog(context);
      if (density != null && density > 0) {
        return await gerarAmostrasParaAtividade(
          hectaresPerSample: density,
          featuresParaProcessar: features,
        );
      }
    }
    
    return "Carga concluída: ${features.length} polígonos, $fazendasCriadas novas fazendas e $talhoesCriados novos talhões criados. Nenhuma amostra foi gerada.";
  }
  
  Future<void> loadSamplesParaAtividade() async {
    if (_currentAtividade == null) return;
    
    _setLoading(true);
    _samplePoints.clear();
    final fazendas = await _fazendaRepository.getFazendasDaAtividade(_currentAtividade!.id!);
    for (final fazenda in fazendas) {
      final talhoes = await _talhaoRepository.getTalhoesDaFazenda(fazenda.id, _currentAtividade!.id!);
      for (final talhao in talhoes) {
        final parcelas = await _parcelaRepository.getParcelasDoTalhao(talhao.id!);
        for (final p in parcelas) {
           _samplePoints.add(SamplePoint(
              id: int.tryParse(p.idParcela) ?? 0,
              position: LatLng(p.latitude ?? 0, p.longitude ?? 0),
              status: _getSampleStatus(p),
              data: {'dbId': p.dbId}
          ));
        }
      }
    }
    _setLoading(false);
  }

  void toggleFollowingUser() {
    if (_isFollowingUser) {
      _positionStreamSubscription?.cancel();
      _isFollowingUser = false;
    } else {
      const locationSettings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 1);
      _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
        _currentUserPosition = position;
        notifyListeners();
      });
      _isFollowingUser = true;
    }
    notifyListeners();
  }

  void updateUserPosition(Position position) {
    _currentUserPosition = position;
    notifyListeners();
  }
  
  // ✅ MÉTODO `dispose` ATUALIZADO E CORRIGIDO
  @override
  void dispose() { 
    // Cancela a inscrição ao stream de posição para evitar vazamentos de memória
    _positionStreamSubscription?.cancel(); 
    
    // Otimiza a atividade para limpar talhões vazios quando o provider for descartado
    final atividadeId = _currentAtividade?.id;
    if (atividadeId != null) {
      _optimizerService.otimizarAtividade(atividadeId);
      debugPrint("Otimização da atividade $atividadeId agendada ao sair do mapa.");
    }
    
    super.dispose(); 
  }
  
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  SampleStatus _getSampleStatus(Parcela parcela) {
    if (parcela.exportada) {
      return SampleStatus.exported;
    }
    switch (parcela.status) {
      case StatusParcela.concluida:
        return SampleStatus.completed;
      case StatusParcela.emAndamento:
        return SampleStatus.open;
      case StatusParcela.pendente:
        return SampleStatus.untouched;
      case StatusParcela.exportada:
        return SampleStatus.exported;
    }
  }

  Future<void> exportarPlanoDeAmostragem(BuildContext context) async {
    final List<int> parcelaIds = samplePoints.map((p) => p.data['dbId'] as int).toList();

    if (parcelaIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nenhum plano de amostragem para exportar.'),
          backgroundColor: Colors.orange,
        ));
        return;
    }

    await _exportService.exportarPlanoDeAmostragem(
      context: context,
      parcelaIds: parcelaIds,
    );
  }
}

class LocationMarker extends StatefulWidget {
  const LocationMarker({super.key});
  @override
  State<LocationMarker> createState() => _LocationMarkerState();
}
class _LocationMarkerState extends State<LocationMarker> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat(reverse: false);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        FadeTransition(
          opacity: Tween<double>(begin: 1.0, end: 0.0).animate(_animation),
          child: ScaleTransition(
            scale: _animation,
            child: Container(
              width: 50.0,
              height: 50.0,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blue.withOpacity(0.4)),
            ),
          ),
        ),
        Container(
          width: 20.0,
          height: 20.0,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blue.shade700,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 5, offset: const Offset(0, 3))],
          ),
        ),
      ],
    );
  }
}
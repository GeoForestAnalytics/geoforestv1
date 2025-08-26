import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/sample_point.dart';
import 'package:geoforestv1/pages/amostra/coleta_dados_page.dart';
import 'package:geoforestv1/providers/map_provider.dart';
import 'package:geoforestv1/services/activity_optimizer_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';

class MapImportPage extends StatefulWidget {
  const MapImportPage({super.key});

  @override
  State<MapImportPage> createState() => _MapImportPageState();
}

class _MapImportPageState extends State<MapImportPage> with RouteAware {
  final _mapController = MapController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MapProvider.routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }
  
  @override
  void didPopNext() {
    super.didPopNext();
    debugPrint("Mapa visível novamente, recarregando os dados das amostras...");
    context.read<MapProvider>().loadSamplesParaAtividade();
  }

  @override
  void dispose() {
    MapProvider.routeObserver.unsubscribe(this);
    final mapProvider = Provider.of<MapProvider>(context, listen: false);

    // Otimiza a atividade ao sair da tela para limpar talhões vazios
    final atividadeId = mapProvider.currentAtividade?.id;
    if (atividadeId != null) {
      ActivityOptimizerService(dbHelper: DatabaseHelper.instance).otimizarAtividade(atividadeId);
      debugPrint("Otimização da atividade $atividadeId agendada ao sair do mapa.");
    }

    if (mapProvider.isFollowingUser) {
      mapProvider.toggleFollowingUser();
    }
    
    // <<< ADIÇÃO RECOMENDADA AQUI >>>
    // Para o modo "Ir para" se ele estiver ativo ao sair da tela
    if (mapProvider.isGoToModeActive) {
      mapProvider.stopGoTo();
    }
    // <<< FIM DA ADIÇÃO >>>

    super.dispose();
  }

  Color _getMarkerColor(SampleStatus status) {
    switch (status) {
      case SampleStatus.open: return Colors.orange.shade300;
      case SampleStatus.completed: return Colors.green;
      case SampleStatus.exported: return Colors.blue;
      case SampleStatus.untouched: return Colors.white;
    }
  }

  Color _getMarkerTextColor(SampleStatus status) {
    switch (status) {
      case SampleStatus.open: case SampleStatus.untouched: return Colors.black;
      case SampleStatus.completed: case SampleStatus.exported: return Colors.white;
    }
  }

  Future<void> _handleImport() async {
    final provider = context.read<MapProvider>();
    
    final bool? isPlano = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('O que você quer importar?'),
        content: const Text('Escolha o tipo de arquivo para importar para esta atividade.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Carga de Talhões (Polígonos)'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Plano de Amostragem (Pontos)'),
          ),
        ],
      ),
    );

    if (isPlano == null || !mounted) return;

    final resultMessage = await provider.processarImportacaoDeArquivo(isPlanoDeAmostragem: isPlano, context: context);
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resultMessage), duration: const Duration(seconds: 5)));
    
    if (provider.polygons.isNotEmpty) {
      _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(provider.polygons.expand((p) => p.points).toList()),
          padding: const EdgeInsets.all(50.0)));
    } else if (provider.samplePoints.isNotEmpty) {
      _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(provider.samplePoints.map((p) => p.position).toList()),
          padding: const EdgeInsets.all(50.0)));
    }
  }
  
  Future<void> _handleGenerateSamples() async {
    final provider = context.read<MapProvider>();
    if (provider.polygons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Importe ou desenhe os polígonos dos talhões primeiro.')));
      return;
    }

    final resultMessage = await provider.showDensityDialogAndGenerateSamples(context);
    
    if(mounted && resultMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resultMessage), duration: const Duration(seconds: 4)));
    }
  }

  Future<void> _handleLocationButtonPressed() async {
    final provider = context.read<MapProvider>();
    final currentZoom = _mapController.camera.zoom;

    if (provider.isFollowingUser) {
      final currentPosition = provider.currentUserPosition;
      if (currentPosition != null) {
        _mapController.move(LatLng(currentPosition.latitude, currentPosition.longitude), currentZoom);
      }
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Serviço de GPS desabilitado.')));
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permissão de localização negada.')));
        return;
      }
    }
    if (permission == LocationPermission.deniedForever && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permissão negada permanentemente.')));
      return;
    }

    try {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Buscando sua localização...')));
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      
      provider.updateUserPosition(position);
      provider.toggleFollowingUser();
      
      _mapController.move(LatLng(position.latitude, position.longitude), currentZoom);
      
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível obter a localização: $e')));
      }
    }
  }

  /// Exibe o menu de opções ao segurar um marcador.
  void _showMarkerOptions(BuildContext context, SamplePoint samplePoint) {
    final mapProvider = context.read<MapProvider>();

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Wrap(
        children: <Widget>[
          ListTile(
            title: Text('Amostra ${samplePoint.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Lat: ${samplePoint.position.latitude.toStringAsFixed(5)}, Lon: ${samplePoint.position.longitude.toStringAsFixed(5)}'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.navigation_outlined, color: Colors.blue),
            title: const Text('Navegar para amostra'),
            subtitle: const Text('Usar app de mapas (ex: Google Maps)'),
            onTap: () async {
              Navigator.pop(ctx); // Fecha o menu
              try {
                await mapProvider.launchNavigation(samplePoint.position);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.track_changes_outlined, color: Colors.green),
            title: const Text('Ir para'),
            subtitle: const Text('Navegação em linha reta (off-road)'),
            onTap: () {
              Navigator.pop(ctx); // Fecha o menu
              mapProvider.startGoTo(samplePoint);
            },
          ),
        ],
      ),
    );
  }

  /// Constrói a caixa de informações do modo "Ir para".
  Widget _buildGoToInfoCard(MapProvider mapProvider) {
    if (!mapProvider.isGoToModeActive) {
      return const SizedBox.shrink(); // Retorna um widget vazio se o modo não estiver ativo
    }

    final info = mapProvider.getGoToInfo();

    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Distância: ${info['distance']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Direção: ${info['bearing']}'),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                tooltip: 'Parar navegação',
                onPressed: () => mapProvider.stopGoTo(),
              )
            ],
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar(MapProvider mapProvider) {
    final atividadeTipo = mapProvider.currentAtividade?.tipo ?? 'Planejamento';

    return AppBar(
      title: Text('Planejamento: $atividadeTipo'),
      actions: [
        IconButton(
          icon: const Icon(Icons.share_outlined),
          onPressed: mapProvider.isLoading ? null : () => context.read<MapProvider>().exportarPlanoDeAmostragem(context),
          tooltip: 'Exportar Plano de Amostragem',
        ),
        if(mapProvider.polygons.isNotEmpty)
          IconButton(
              icon: const Icon(Icons.grid_on_sharp),
              onPressed: mapProvider.isLoading ? null : _handleGenerateSamples,
              tooltip: 'Gerar Amostras'),
        IconButton(
            icon: const Icon(Icons.edit_location_alt_outlined),
            onPressed: () => mapProvider.startDrawing(),
            tooltip: 'Desenhar Área'),
        IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: mapProvider.isLoading ? null : _handleImport,
            tooltip: 'Importar Arquivo'),
      ],
    );
  }

  AppBar _buildDrawingAppBar(MapProvider mapProvider) {
    return AppBar(
      backgroundColor: Colors.grey.shade800,
      title: const Text('Desenhando a Área'),
      leading: IconButton(icon: const Icon(Icons.close), onPressed: () => mapProvider.cancelDrawing(), tooltip: 'Cancelar Desenho'),
      actions: [
        IconButton(icon: const Icon(Icons.undo), onPressed: () => mapProvider.undoLastDrawnPoint(), tooltip: 'Desfazer Último Ponto'),
        IconButton(icon: const Icon(Icons.check), onPressed: () => mapProvider.saveDrawnPolygon(context), tooltip: 'Salvar Polígono'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapProvider = context.watch<MapProvider>();
    final currentUserPosition = mapProvider.currentUserPosition;
    final isDrawing = mapProvider.isDrawing;

    if (currentUserPosition != null && mapProvider.isFollowingUser) {
      _mapController.move(LatLng(currentUserPosition.latitude, currentUserPosition.longitude), _mapController.camera.zoom);
    }

    return Scaffold(
      appBar: isDrawing ? _buildDrawingAppBar(mapProvider) : _buildAppBar(mapProvider),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(-15.7, -47.8),
              initialZoom: 4,
              onPositionChanged: (position, hasGesture) {
                if(hasGesture && mapProvider.isFollowingUser) {
                  context.read<MapProvider>().toggleFollowingUser();
                }
              },
              onTap: (tapPosition, point) { if (isDrawing) mapProvider.addDrawnPoint(point); },
            ),
            children: [
              TileLayer(
                  urlTemplate: mapProvider.currentTileUrl,
                  userAgentPackageName: 'com.example.geoforestv1'),
              if (mapProvider.polygons.isNotEmpty)
                PolygonLayer(polygons: mapProvider.polygons),
              
              MarkerLayer(
                markers: mapProvider.samplePoints.map((samplePoint) {
                  final color = _getMarkerColor(samplePoint.status);
                  final textColor = _getMarkerTextColor(samplePoint.status);
                  return Marker(
                    width: 40.0, height: 40.0, point: samplePoint.position,
                    child: GestureDetector(
                      onTap: () async {
                        if (!mounted) return;
                        final dbId = samplePoint.data['dbId'] as int?;
                        if (dbId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro: ID da parcela não encontrado.')));
                          return;
                        }
                        
                        final parcela = await ParcelaRepository().getParcelaById(dbId);
                        
                        if (!mounted || parcela == null) return;

                        await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(builder: (context) => ColetaDadosPage(parcelaParaEditar: parcela))
                        );
                      },
                      onLongPress: () {
                        _showMarkerOptions(context, samplePoint);
                      },
                      child: Container(
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 4, offset: const Offset(2, 2))]),
                        child: Center(child: Text(samplePoint.id.toString(), style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14))),
                      ),
                    ),
                  );
                }).toList(),
              ),

              if (mapProvider.isGoToModeActive && currentUserPosition != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [
                        LatLng(currentUserPosition.latitude, currentUserPosition.longitude),
                        mapProvider.goToTarget!.position,
                      ],
                      strokeWidth: 3.0,
                      color: Colors.redAccent,                      
                    ),
                  ],
                ),
              
              if (isDrawing && mapProvider.drawnPoints.isNotEmpty)
                PolylineLayer(polylines: [ Polyline(points: mapProvider.drawnPoints, strokeWidth: 2.0, color: Colors.red.withOpacity(0.8)), ]),
              if (isDrawing)
                MarkerLayer(
                  markers: mapProvider.drawnPoints.map((point) {
                    return Marker(
                      point: point,
                      width: 12,
                      height: 12,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    );
                  }).toList(),
                ),

              if (currentUserPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 80.0,
                      height: 80.0,
                      point: LatLng(currentUserPosition.latitude, currentUserPosition.longitude),
                      child: const LocationMarker(),
                    ),
                  ],
                ),
            ],
          ),
          if (mapProvider.isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text("Processando...", style: TextStyle(color: Colors.white, fontSize: 16))
                  ]
                )
              )
            ),
          
          _buildGoToInfoCard(mapProvider),

          if (!isDrawing)
            Positioned(
              top: 10,
              left: 10,
              child: Column(
                children: [
                   FloatingActionButton(
                     onPressed: _handleLocationButtonPressed,
                     tooltip: 'Minha Localização',
                     heroTag: 'centerLocationFab',
                     backgroundColor: mapProvider.isFollowingUser ? Colors.blue : Theme.of(context).colorScheme.primary,
                     foregroundColor: Colors.white,
                     child: Icon(mapProvider.isFollowingUser ? Icons.gps_fixed : Icons.gps_not_fixed),
                   ),
                   const SizedBox(height: 10),
                   FloatingActionButton(
                     onPressed: () => context.read<MapProvider>().switchMapLayer(),
                     tooltip: 'Mudar Camada do Mapa',
                     heroTag: 'switchLayerFab',
                     mini: true,
                     child: Icon(mapProvider.currentLayer == MapLayerType.ruas
                         ? Icons.satellite_outlined
                         : (mapProvider.currentLayer == MapLayerType.satelite
                             ? Icons.terrain
                             : Icons.map_outlined)),
                   ),
                ],
              ),
            ),
        ],
      ),
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
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: false);

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
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
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withOpacity(0.4),
              ),
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
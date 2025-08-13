// lib/pages/gerente/gerente_map_page.dart (VERSÃO CORRIGIDA DOS ERROS DE COMPILAÇÃO)

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart'; // <<< CORREÇÃO 1: ADICIONAR ESTE IMPORT

class MapLayer {
  final String name;
  final IconData icon;
  final TileLayer tileLayer;

  MapLayer({required this.name, required this.icon, required this.tileLayer});
}


class GerenteMapPage extends StatefulWidget {
  const GerenteMapPage({super.key});

  @override
  State<GerenteMapPage> createState() => _GerenteMapPageState();
}

class _GerenteMapPageState extends State<GerenteMapPage> {
  final MapController _mapController = MapController();
  
  static final List<MapLayer> _mapLayers = [
    MapLayer(
      name: 'Ruas',
      icon: Icons.map_outlined,
      tileLayer: TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.example.geoforestv1',
      ),
    ),
    MapLayer(
      name: 'Satélite',
      icon: Icons.satellite_alt_outlined,
      tileLayer: TileLayer(
        urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        userAgentPackageName: 'com.example.geoforestv1',
      ),
    ),
  ];
  
  late MapLayer _currentLayer;
  Position? _currentUserPosition;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _currentLayer = _mapLayers[1];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerMapOnMarkers();
    });
  }

  void _centerMapOnMarkers() {
    final provider = context.read<GerenteProvider>();
    final parcelas = provider.parcelasFiltradas;
    if (parcelas.isNotEmpty) {
      final points = parcelas
          .where((p) => p.latitude != null && p.longitude != null)
          .map((p) => LatLng(p.latitude!, p.longitude!))
          .toList();
      
      if (points.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(50.0),
          ),
        );
      }
    }
  }

  Color _getMarkerColor(StatusParcela status) {
    switch (status) {
      case StatusParcela.concluida:
        return Colors.green;
      case StatusParcela.emAndamento:
        return Colors.orange.shade700;
      case StatusParcela.pendente:
        return Colors.grey.shade600;
      case StatusParcela.exportada:
        return Colors.blue;
    }
  }

  void _switchMapLayer() {
    setState(() {
      final currentIndex = _mapLayers.indexOf(_currentLayer);
      _currentLayer = _mapLayers[(currentIndex + 1) % _mapLayers.length];
    });
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'Serviço de GPS desabilitado.';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw 'Permissão de localização negada.';
      }
      if (permission == LocationPermission.deniedForever) throw 'Permissão de localização negada permanentemente.';

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      
      setState(() {
        _currentUserPosition = position;
      });

      _mapController.move(
        LatLng(position.latitude, position.longitude),
        15.0,
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao obter localização: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa Geral de Coletas'),
        actions: [
          IconButton(
            icon: Icon(_currentLayer.icon),
            onPressed: _switchMapLayer,
            tooltip: 'Mudar Camada do Mapa',
          ),
          IconButton(
            icon: const Icon(Icons.center_focus_strong_outlined),
            onPressed: _centerMapOnMarkers,
            tooltip: 'Centralizar nos Pontos',
          ),
        ],
      ),
      body: Consumer<GerenteProvider>(
        builder: (context, provider, child) {
          final parcelas = provider.parcelasFiltradas;

          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (parcelas.isEmpty) {
            return const Center(child: Text('Nenhuma parcela sincronizada para exibir no mapa.'));
          }

          final markers = parcelas
              .where((p) => p.latitude != null && p.longitude != null)
              .map<Marker>((parcela) {
            return Marker(
              width: 35.0,
              height: 35.0,
              point: LatLng(parcela.latitude!, parcela.longitude!),
              child: GestureDetector(
                onTap: () {
                  // <<< CORREÇÃO 2: A LÓGICA DE BUSCA FOI SUBSTITUÍDA AQUI >>>
                  final nomeProjeto = provider.projetosDisponiveis
                      .firstWhereOrNull((p) => p.id == parcela.projetoId)
                      ?.nome ?? 'Projeto não encontrado';
                  
                  final infoText = 
                      'Projeto: $nomeProjeto\n'
                      'Fazenda: ${parcela.nomeFazenda ?? 'N/A'}\n'
                      'Talhão: ${parcela.nomeTalhao ?? 'N/A'} | Parcela: ${parcela.idParcela}\n'
                      'Status: ${parcela.status.name}';

                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(infoText),
                    duration: const Duration(seconds: 4),
                  ));
                },
                child: Icon(
                  Icons.location_pin,
                  color: _getMarkerColor(parcela.status),
                  size: 35.0,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 5)],
                ),
              ),
            );
          }).toList();
          
          if (_currentUserPosition != null) {
            markers.add(
              Marker(
                point: LatLng(_currentUserPosition!.latitude, _currentUserPosition!.longitude),
                width: 80,
                height: 80,
                child: const LocationMarker(),
              ),
            );
          }

          return FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(-15.7, -47.8),
              initialZoom: 4,
            ),
            children: [
              _currentLayer.tileLayer,
              MarkerLayer(markers: markers),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLocating ? null : _getCurrentLocation,
        tooltip: 'Minha Localização',
        child: _isLocating
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
            : const Icon(Icons.my_location),
      ),
    );
  }
}

// O widget LocationMarker permanece o mesmo
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
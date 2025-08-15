// lib/pages/gerente/gerente_map_page.dart (VERSÃO FINAL COM ANEL DE PROGRESSO)

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:geoforestv1/providers/dashboard_metrics_provider.dart';
// <<< PASSO 3.1: IMPORTAR O NOVO WIDGET DO ANEL >>>
import 'package:geoforestv1/widgets/fazenda_progress_cluster.dart'; 


class MapLayer {
  final String name;
  final IconData icon;
  final TileLayer tileLayer;
  MapLayer({required this.name, required this.icon, required this.tileLayer});
}

class FazendaCluster {
  final String nome;
  final int parcelaCount;
  final LatLng center;
  final LatLngBounds bounds;
  // <<< Dados de progresso adicionados ao cluster >>>
  final int concluidas;
  final double progresso;

  FazendaCluster({
    required this.nome,
    required this.parcelaCount,
    required this.center,
    required this.bounds,
    required this.concluidas,
    required this.progresso,
  });
}

class GerenteMapPage extends StatefulWidget {
  const GerenteMapPage({super.key});

  @override
  State<GerenteMapPage> createState() => _GerenteMapPageState();
}

class _GerenteMapPageState extends State<GerenteMapPage> {
  final MapController _mapController = MapController();
  
  String? _fazendaSelecionada;

  static final List<MapLayer> _mapLayers = [
    MapLayer(name: 'Ruas', icon: Icons.map_outlined, tileLayer: TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.geoforestv1' )),
    MapLayer(name: 'Satélite', icon: Icons.satellite_alt_outlined, tileLayer: TileLayer(urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', userAgentPackageName: 'com.example.geoforestv1' )),
  ];
  
  late MapLayer _currentLayer;
  Position? _currentUserPosition;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _currentLayer = _mapLayers[1];
  }

  void _centerMapOnBounds(LatLngBounds bounds) {
    if (bounds.southWest != const LatLng(0,0) || bounds.northEast != const LatLng(0,0)) {
      try {
         _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50.0)));
      } catch(e) {
        debugPrint("Erro ao centralizar mapa: $e");
      }
    }
  }

  Color _getMarkerColor(StatusParcela status) {
    switch (status) {
      case StatusParcela.concluida: return Colors.green;
      case StatusParcela.emAndamento: return Colors.orange.shade700;
      case StatusParcela.pendente: return Colors.grey.shade600;
      case StatusParcela.exportada: return Colors.blue;
    }
  }

  void _switchMapLayer() {
    setState(() => _currentLayer = _mapLayers[(_mapLayers.indexOf(_currentLayer) + 1) % _mapLayers.length]);
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
      setState(() => _currentUserPosition = position);
      _mapController.move(LatLng(position.latitude, position.longitude), 15.0);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao obter localização: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_fazendaSelecionada == null ? 'Visão Geral por Fazenda' : 'Detalhes: $_fazendaSelecionada'),
        actions: [
          IconButton(icon: Icon(_currentLayer.icon), onPressed: _switchMapLayer, tooltip: 'Mudar Camada do Mapa'),
        ],
        leading: _fazendaSelecionada != null
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Voltar para Fazendas',
              onPressed: () => setState(() => _fazendaSelecionada = null),
            )
          : null,
      ),
      // <<< PASSO 3.2: O Consumer agora busca também o DashboardMetricsProvider >>>
      body: Consumer2<GerenteProvider, DashboardMetricsProvider>(
        builder: (context, gerenteProvider, metricsProvider, child) {
          if (gerenteProvider.isLoading) return const Center(child: CircularProgressIndicator());
          
          if (metricsProvider.parcelasFiltradas.isEmpty) return const Center(child: Text('Nenhuma parcela sincronizada para exibir no mapa.'));

          List<Marker> markersToShow = [];
          
          if (_fazendaSelecionada == null) {
            final parcelasPorFazenda = groupBy(metricsProvider.parcelasFiltradas, (Parcela p) => p.nomeFazenda ?? 'Fazenda Desconhecida');
            final List<FazendaCluster> fazendaClusters = [];

            // <<< PASSO 3.3: LÓGICA DE CRIAÇÃO DO CLUSTER ATUALIZADA >>>
            // Busca os dados de progresso calculados pelo MetricsProvider
            final progressoData = metricsProvider.progressoPorFazenda;

            parcelasPorFazenda.forEach((nomeFazenda, parcelas) {
              final points = parcelas.where((p) => p.latitude != null && p.longitude != null).map((p) => LatLng(p.latitude!, p.longitude!)).toList();
              if (points.isNotEmpty) {
                final bounds = LatLngBounds.fromPoints(points);
                
                // Encontra os dados de progresso para esta fazenda específica
                final progressoInfo = progressoData.firstWhere(
                  (p) => p.nome == nomeFazenda, 
                  orElse: () => ProgressoFazenda(nome: nomeFazenda, totalParcelas: parcelas.length, concluidas: 0, progresso: 0.0)
                );

                fazendaClusters.add(FazendaCluster(
                  nome: nomeFazenda,
                  parcelaCount: progressoInfo.totalParcelas,
                  concluidas: progressoInfo.concluidas,
                  progresso: progressoInfo.progresso,
                  center: bounds.center,
                  bounds: bounds,
                ));
              }
            });

            // <<< PASSO 3.4: USA O NOVO WIDGET FazendaProgressCluster PARA CRIAR OS MARCADORES >>>
            markersToShow = fazendaClusters.map((cluster) {
              return Marker(
                width: 120, height: 120, // Aumenta o tamanho para o anel
                point: cluster.center,
                child: FazendaProgressCluster(
                  nomeFazenda: cluster.nome,
                  totalParcelas: cluster.parcelaCount,
                  concluidas: cluster.concluidas,
                  progresso: cluster.progresso,
                  onTap: () {
                    setState(() => _fazendaSelecionada = cluster.nome);
                    Future.delayed(const Duration(milliseconds: 100), () => _centerMapOnBounds(cluster.bounds));
                  },
                )
              );
            }).toList();

          } else {
            final parcelasVisiveis = metricsProvider.parcelasFiltradas.where((p) => p.nomeFazenda == _fazendaSelecionada).toList();
            
            markersToShow = parcelasVisiveis.map<Marker?>((parcela) {
              if(parcela.latitude == null || parcela.longitude == null) return null;
              
              return Marker(
                width: 35.0, height: 35.0,
                point: LatLng(parcela.latitude!, parcela.longitude!),
                child: GestureDetector(
                  onTap: () {
                    final nomeProjeto = gerenteProvider.projetos.firstWhereOrNull((p) => p.id == parcela.projetoId)?.nome ?? 'N/A';
                    final infoText = 
                        'Projeto: $nomeProjeto\n'
                        'Fazenda: ${parcela.nomeFazenda ?? 'N/A'}\n'
                        'Talhão: ${parcela.nomeTalhao ?? 'N/A'} | Parcela: ${parcela.idParcela}\n'
                        'Status: ${parcela.status.name}';
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(infoText), duration: const Duration(seconds: 4)));
                  },
                  child: Icon(Icons.location_pin, color: _getMarkerColor(parcela.status), size: 35.0, shadows: const [Shadow(color: Colors.black, blurRadius: 5)]),
                ),
              );
            }).whereType<Marker>().toList();
          }

          if (_currentUserPosition != null) {
            markersToShow.add(Marker(
              point: LatLng(_currentUserPosition!.latitude, _currentUserPosition!.longitude),
              width: 80, height: 80,
              child: const LocationMarker(),
            ));
          }

          return FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(-15.7, -47.8),
              initialZoom: 4,
            ),
            children: [
              _currentLayer.tileLayer,
              MarkerLayer(markers: markersToShow),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLocating ? null : _getCurrentLocation,
        tooltip: 'Minha Localização',
        child: _isLocating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) : const Icon(Icons.my_location),
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
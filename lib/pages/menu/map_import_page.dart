import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geoforestv1/services/pdf_tile_provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/sample_point.dart';
import 'package:geoforestv1/pages/amostra/coleta_dados_page.dart';
import 'package:geoforestv1/pages/pilhas/coleta_pilha_page.dart';
import 'package:geoforestv1/pages/pilhas/detalhe_pilha_page.dart';
import 'package:geoforestv1/pages/pilhas/estoque_saida_page.dart';
import 'package:geoforestv1/pages/silvicultura/coleta_silvi_page.dart';
import 'package:geoforestv1/pages/silvicultura/visualizar_areas_silvi_page.dart';
import 'package:geoforestv1/models/pilha_madeira_model.dart';
import 'package:geoforestv1/models/silvi_model.dart';
import 'package:geoforestv1/providers/map_provider.dart';
import 'package:geoforestv1/data/repositories/silvi_repository.dart';
import 'package:geoforestv1/services/activity_optimizer_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/pilha_repository.dart';

class MapImportPage extends StatefulWidget {
  const MapImportPage({super.key});

  @override
  State<MapImportPage> createState() => _MapImportPageState();
}

class _MapImportPageState extends State<MapImportPage> with RouteAware {
  final _mapController = MapController();
  final _pilhaRepo = PilhaRepository();
  final _silviRepo = SilviRepository();
  List<CentroideSilvi> _centroidesSilvi = [];

  bool _centroidesSilviCarregados = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MapProvider.routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
    if (!_centroidesSilviCarregados) {
      _centroidesSilviCarregados = true;
      _carregarCentroidesSilvi();
    }
  }
  
  @override
  void didPopNext() {
    super.didPopNext();
    debugPrint("Mapa visível novamente, recarregando os dados das amostras...");
    context.read<MapProvider>().loadSamplesParaAtividade();
    _carregarCentroidesSilvi();
  }

  Future<void> _carregarCentroidesSilvi() async {
    final atividadeId = context.read<MapProvider>().currentAtividade?.id;
    if (atividadeId == null) return;
    final lista = await _silviRepo.getCentroidesParaAtividade(atividadeId);
    if (mounted) setState(() => _centroidesSilvi = lista);
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

  Future<void> _showCentroideSilviOptions(BuildContext context, CentroideSilvi centroide) async {
    final ops = await _silviRepo.getOperacoesDoTalhao(centroide.talhaoId ?? 0);
    final totalPlan = centroide.operacoesPlanejadas.fold(0.0, (s, o) => s + (o.areaHa ?? 0));
    final totalAplic = ops.fold(0.0, (s, o) => s + (o.areaAplicadaHa ?? 0));
    if (!mounted) return;

    showModalBottomSheet(
      context: this.context,
      builder: (ctx) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.eco_outlined, color: Colors.green),
            title: Text(centroide.nomeTalhao, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${centroide.nomeFazenda}  •  ${centroide.operacoesPlanejadas.length} operação(ões) planejada(s)'),
          ),
          if (totalPlan > 0 || totalAplic > 0) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Executado: ${totalAplic.toStringAsFixed(2)} ha${totalPlan > 0 ? '  /  Planejado: ${totalPlan.toStringAsFixed(2)} ha' : ''}',
                      style: const TextStyle(fontSize: 13)),
                  if (totalPlan > 0) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (totalAplic / totalPlan).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          totalAplic >= totalPlan ? Colors.green.shade600 : Colors.green.shade400),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: Colors.green),
            title: const Text('Registrar Operação'),
            onTap: () async {
              Navigator.pop(ctx);
              final salvo = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => ColetaSilviPage(centroide: centroide)),
              );
              if (salvo == true && mounted) _carregarCentroidesSilvi();
            },
          ),
          if (ops.isNotEmpty)
            ListTile(
              leading: Icon(Icons.layers_outlined, color: Colors.green.shade700),
              title: const Text('Ver operações no mapa'),
              subtitle: Text(
                '${ops.where((o) => o.areaGeoJson != null).length} com área desenhada',
              ),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VisualizarAreasSilviPage(
                      operacoes: ops,
                      centroide: centroide,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  /// Abre o menu de opções ao tocar em um marcador de centróide de pilha.
  Future<void> _showCentroideOptions(BuildContext context, CentroidePilha centroide) async {
    final mapProvider = context.read<MapProvider>();
    final isVisualizando = mapProvider.talhaoVisualizandoPilhas == centroide.talhaoId;

    // Calcula volumes esperado (JSON) e coletado (campo) antes de abrir o sheet
    final double volEsperado = centroide.sortimentos
        .fold(0.0, (sum, s) => sum + (s.volumeEsperadoM3 ?? 0));

    double volColetado = 0;
    if (centroide.talhaoId != null) {
      final pilhas = await _pilhaRepo.getPilhasDoTalhao(centroide.talhaoId!);
      volColetado = pilhas.fold(0.0, (sum, p) => sum + p.calcularVolumesolido());
    }

    if (!mounted) return;

    final nf2 = volEsperado > 0 ? volEsperado.toStringAsFixed(2) : null;
    final pct = volEsperado > 0 ? (volColetado / volEsperado * 100) : null;

    showModalBottomSheet(
      context: this.context,
      builder: (ctx) => Wrap(
        children: [
          ListTile(
            title: Text(
              'Talhão: ${centroide.nomeTalhao}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${centroide.nomeFazenda}  •  ${centroide.sortimentos.length} sortimento(s)'),
          ),
          if (volEsperado > 0 || volColetado > 0) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.bar_chart_outlined, color: Colors.brown, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Coletado: ${volColetado.toStringAsFixed(2)} m³'
                          '${nf2 != null ? '  /  Esperado: $nf2 m³' : ''}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        if (pct != null)
                          Text(
                            '${pct.toStringAsFixed(1)}% realizado',
                            style: TextStyle(
                              fontSize: 12,
                              color: pct >= 90
                                  ? Colors.green.shade700
                                  : pct >= 60
                                      ? Colors.orange.shade700
                                      : Colors.red.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: Colors.brown),
            title: const Text('Adicionar Pilha'),
            onTap: () async {
              Navigator.pop(ctx);
              final salvo = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => ColetaPilhaPage(centroide: centroide)),
              );
              if (salvo == true && mounted) {
                mapProvider.recarregarPilhasVisiveis();
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.local_shipping_outlined, color: Colors.orange.shade700),
            title: const Text('Saída de Estoque'),
            subtitle: const Text('Volume declarado sem medição de seções'),
            onTap: () async {
              Navigator.pop(ctx);
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => EstoqueSaidaPage(centroide: centroide)),
              );
              if (mounted) mapProvider.recarregarPilhasVisiveis();
            },
          ),
          ListTile(
            leading: Icon(
              isVisualizando ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: Colors.orange.shade700,
            ),
            title: Text(isVisualizando ? 'Ocultar Pilhas do Talhão' : 'Visualizar Pilhas do Talhão'),
            onTap: () {
              Navigator.pop(ctx);
              if (centroide.talhaoId != null) {
                mapProvider.toggleVisualizarPilhasTalhao(centroide.talhaoId!);
              }
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
    final hasPdf = mapProvider.importedPdfPath != null;

    return AppBar(
      title: Text('Planejamento: $atividadeTipo'),
      actions: [
        IconButton(
          icon: Icon(
            hasPdf ? Icons.picture_as_pdf : Icons.picture_as_pdf_outlined,
            color: hasPdf
                ? (mapProvider.showPdfOverlay ? Colors.orange : Colors.greenAccent)
                : null,
          ),
          onPressed: hasPdf
              ? () => context.read<MapProvider>().togglePdfOverlay()
              : () => context.read<MapProvider>().importPdfOverlay(context),
          tooltip: hasPdf
              ? (mapProvider.showPdfOverlay ? 'Ocultar PDF' : 'Mostrar PDF')
              : 'Importar PDF de Referência',
        ),
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
                  onChanged: (v) => context.read<MapProvider>().setPdfOpacity(v),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Remover PDF?'),
                      content: const Text('O PDF de referência será removido do mapa.'),
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
                child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
              ),
            ],
          ),
        ),
      ),
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

    if (currentUserPosition != null && mapProvider.isFollowingUser && !mapProvider.isLockedOnPdf) {
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
                if (hasGesture && mapProvider.isLockedOnPdf) {
                  mapProvider.unlockFromPdf();
                }
              },
              onTap: (tapPosition, point) { if (isDrawing) mapProvider.addDrawnPoint(point); },
            ),
            children: [
              TileLayer(
                  urlTemplate: mapProvider.currentTileUrl,
                  userAgentPackageName: 'com.example.geoforestv1'),
              if (mapProvider.showPdfOverlay &&
                  mapProvider.pdfTilesDir != null &&
                  mapProvider.pdfOverlayBounds != null)
                Opacity(
                  opacity: mapProvider.pdfOverlayOpacity,
                  child: TileLayer(
                    tileProvider: PdfTileProvider(tilesBasePath: mapProvider.pdfTilesDir!),
                    tileBounds: mapProvider.pdfOverlayBounds,
                    minNativeZoom: 13,
                    maxNativeZoom: 17,
                    tileDimension: 256,
                  ),
                ),
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

              // ── Centróides de Pilhas ──────────────────────────────────
              if (mapProvider.centroidesPilha.isNotEmpty)
                MarkerLayer(
                  markers: mapProvider.centroidesPilha.map((c) {
                    final isActive = mapProvider.talhaoVisualizandoPilhas == c.talhaoId;
                    return Marker(
                      width: 44,
                      height: 44,
                      point: LatLng(c.latitude, c.longitude),
                      child: GestureDetector(
                        onTap: () => _showCentroideOptions(context, c),
                        onLongPress: () => _showCentroideOptions(context, c),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isActive ? Colors.orange.shade700 : Colors.brown.shade600,
                            shape: BoxShape.rectangle,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(2, 2))],
                          ),
                          child: const Icon(Icons.layers, color: Colors.white, size: 22),
                        ),
                      ),
                    );
                  }).toList(),
                ),

              // ── Centróides de Silvicultura ────────────────────────────
              if (_centroidesSilvi.isNotEmpty)
                MarkerLayer(
                  markers: _centroidesSilvi.map((c) => Marker(
                    width: 44,
                    height: 44,
                    point: LatLng(c.latitude, c.longitude),
                    child: GestureDetector(
                      onTap: () => _showCentroideSilviOptions(context, c),
                      onLongPress: () => _showCentroideSilviOptions(context, c),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.green.shade600,
                          shape: BoxShape.rectangle,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(2, 2))],
                        ),
                        child: const Icon(Icons.eco_outlined, color: Colors.white, size: 22),
                      ),
                    ),
                  )).toList(),
                ),

              // ── Pilhas GPS visíveis do talhão selecionado ─────────────
              if (mapProvider.pilhasVisiveis.isNotEmpty)
                MarkerLayer(
                  markers: mapProvider.pilhasVisiveis
                      .where((p) => p.latitude != null && p.longitude != null)
                      .map((p) => Marker(
                            width: 38,
                            height: 38,
                            point: LatLng(p.latitude!, p.longitude!),
                            child: GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => DetalhePilhaPage(pilha: p),
                                ));
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade300,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.brown.shade800, width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                    p.numeroPilhaFormatado,
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.brown.shade900),
                                  ),
                                ),
                              ),
                            ),
                          ))
                      .toList(),
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

          _buildPdfControls(mapProvider),

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
                   if (mapProvider.showPdfOverlay && mapProvider.pdfOverlayBounds != null) ...[
                     const SizedBox(height: 10),
                     FloatingActionButton(
                       onPressed: () {
                         mapProvider.lockOnPdf();
                         _mapController.fitCamera(CameraFit.bounds(
                           bounds: mapProvider.pdfOverlayBounds!,
                           padding: const EdgeInsets.all(40.0),
                         ));
                       },
                       tooltip: 'Centralizar no PDF',
                       heroTag: 'centerPdfFab',
                       mini: true,
                       backgroundColor: Colors.orange,
                       foregroundColor: Colors.white,
                       child: const Icon(Icons.picture_as_pdf),
                     ),
                   ],
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
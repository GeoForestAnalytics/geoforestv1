// lib/providers/map_provider.dart (VERSÃO CORRIGIDA COM INICIALIZAÇÃO DE BD NOS ISOLATES)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/repositories/fazenda_repository.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
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
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// --- PACOTES DE DADOS PARA ISOLATES ---

class _PlanoImportPayload {
  final String geoJsonContent;
  final int atividadeId;
  final int projetoId;
  final String? referenciaRfDoProjeto;

  _PlanoImportPayload({
    required this.geoJsonContent,
    required this.atividadeId,
    required this.projetoId,
    this.referenciaRfDoProjeto,
  });
}

class _GerarAmostrasPayload {
    final List<Map<String, dynamic>> poligonosData;
    final double hectaresPerSample;
    final int atividadeId;
    final int projetoId;
    final String? referenciaRf;

    _GerarAmostrasPayload({
        required this.poligonosData,
        required this.hectaresPerSample,
        required this.atividadeId,
        required this.projetoId,
        this.referenciaRf,
    });
}

// --- FUNÇÃO DE INICIALIZAÇÃO PARA ISOLATES ---
// <<< CORREÇÃO PRINCIPAL AQUI >>>
void _initializeDatabaseForIsolate() {
  // Como estamos em um Isolate, não podemos usar a implementação padrão do 
  // sqflite que depende de Platform Channels (usada no Android/iOS).
  // Portanto, inicializamos a implementação FFI, que funciona em todas 
  // as plataformas (Desktop, Android, iOS) sem essa dependência.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}


// --- FUNÇÕES GLOBAIS PARA ISOLATES ---

Future<String> _processarPlanoDeAmostragemInIsolate(_PlanoImportPayload payload) async {
  _initializeDatabaseForIsolate();
  final db = await DatabaseHelper.instance.database;
  final List<Parcela> parcelasParaSalvar = [];
  int novasFazendas = 0;
  int novosTalhoes = 0;
  final now = DateTime.now().toIso8601String();

  final Map<String, Fazenda> fazendaCache = {};
  final Map<String, Talhao> talhaoCache = {};

  try {
    final geoJsonData = json.decode(payload.geoJsonContent);
    final List features = geoJsonData['features'];

    for (final feature in features) {
      final props = feature['properties'] as Map<String, dynamic>? ?? {};
      final geometry = feature['geometry'];
      
      if (geometry == null || geometry['type'] != 'Point') continue;

      final fazendaId = (props['id_fazenda'] ?? props['fazenda_id'] ?? props['fazenda'])?.toString();
      final nomeTalhao = (props['talhao'] ?? props['talhao_nome'])?.toString();
      
      if (fazendaId == null || nomeTalhao == null) continue;

      final fazendaKey = '${fazendaId}_${payload.atividadeId}';
      Fazenda? fazenda = fazendaCache[fazendaKey];
      if (fazenda == null) {
        final List<Map<String, dynamic>> fazendaResult = await db.query('fazendas', where: 'id = ? AND atividadeId = ?', whereArgs: [fazendaId, payload.atividadeId]);
        if (fazendaResult.isNotEmpty) {
          fazenda = Fazenda.fromMap(fazendaResult.first);
        } else {
          final nomeDaFazenda = props['fazenda_nome']?.toString() ?? props['fazenda']?.toString() ?? fazendaId;
          final municipio = props['municipio']?.toString() ?? 'N/I';
          final estado = props['estado']?.toString() ?? 'N/I';
          fazenda = Fazenda(id: fazendaId, atividadeId: payload.atividadeId, nome: nomeDaFazenda, municipio: municipio, estado: estado);
          final map = fazenda.toMap();
          map['lastModified'] = now;
          await db.insert('fazendas', map);
          novasFazendas++;
        }
        fazendaCache[fazendaKey] = fazenda;
      }

      final talhaoKey = '${nomeTalhao}_${fazenda.id}_${fazenda.atividadeId}';
      Talhao? talhao = talhaoCache[talhaoKey];
      if (talhao == null) {
        final List<Map<String, dynamic>> talhaoResult = await db.query('talhoes', where: 'nome = ? AND fazendaId = ? AND fazendaAtividadeId = ?', whereArgs: [nomeTalhao, fazenda.id, fazenda.atividadeId]);
        if (talhaoResult.isNotEmpty) {
          talhao = Talhao.fromMap(talhaoResult.first);
        } else {
          talhao = Talhao(
            fazendaId: fazenda.id, fazendaAtividadeId: fazenda.atividadeId, nome: nomeTalhao,
            projetoId: payload.projetoId, // <<< MELHORIA DE CONSISTÊNCIA
            especie: props['especie']?.toString(), areaHa: (props['area_ha'] as num?)?.toDouble(),
            espacamento: props['espacam']?.toString(),
          );
          final map = talhao.toMap();
          map['lastModified'] = now;
          final talhaoId = await db.insert('talhoes', map);
          talhao = talhao.copyWith(id: talhaoId);
          novosTalhoes++;
        }
        talhaoCache[talhaoKey] = talhao;
      }
      
      final idParcela = props['parcela_id_plano']?.toString() ?? props['amostra']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
      final rfDaFeature = props['referencia']?.toString() ?? props['referencia_rf']?.toString();
      final referenciaFinal = rfDaFeature ?? payload.referenciaRfDoProjeto;

      String? idUnicoAmostra;
      if (referenciaFinal != null && referenciaFinal.isNotEmpty) {
        idUnicoAmostra = '${referenciaFinal.trim()}-${talhao.nome.trim()}-${idParcela.trim()}';
      }

      final coordinates = geometry['coordinates'];
      final position = LatLng(coordinates[1].toDouble(), coordinates[0].toDouble());

      parcelasParaSalvar.add(Parcela(
        talhaoId: talhao.id,
        idParcela: idParcela,
        idUnicoAmostra: idUnicoAmostra,
        areaMetrosQuadrados: (props['area_m2'] as num?)?.toDouble() ?? 0.0,
        latitude: position.latitude, 
        longitude: position.longitude,
        status: StatusParcela.pendente,
        dataColeta: DateTime.now(),
        nomeFazenda: fazenda.nome, 
        idFazenda: fazenda.id, 
        nomeTalhao: talhao.nome,
        projetoId: payload.projetoId,
        municipio: fazenda.municipio,
        estado: fazenda.estado,
      ));
    }
    
    if (parcelasParaSalvar.isNotEmpty) {
      final batch = db.batch();
      for (final p in parcelasParaSalvar) {
        batch.insert('parcelas', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    }

    return "Plano importado com sucesso!\n${parcelasParaSalvar.length} amostras salvas.\n$novasFazendas novas fazendas criadas.\n$novosTalhoes novos talhões criados.";
  } catch (e, s) {
    debugPrint("Erro dentro do Isolate: $e\n$s");
    return "Erro ao processar arquivo: ${e.toString()}";
  }
}

Future<String> _gerarAmostrasInIsolate(_GerarAmostrasPayload payload) async {
    _initializeDatabaseForIsolate();
    final db = await DatabaseHelper.instance.database;
    final samplingService = SamplingService();

    final poligonos = payload.poligonosData.map((data) {
        final points = (data['points'] as List).map((p) => LatLng(p[0], p[1])).toList();
        return ImportedPolygonFeature(
            polygon: Polygon(points: points),
            properties: data['properties'],
        );
    }).toList();

    final pontosGerados = samplingService.generateMultiTalhaoSamplePoints(
      importedFeatures: poligonos,
      hectaresPerSample: payload.hectaresPerSample,
    );

    if (pontosGerados.isEmpty) {
      return "Nenhum ponto de amostra pôde ser gerado.";
    }

    final List<Parcela> parcelasParaSalvar = [];
    int pointIdCounter = 1;
    
    for (final ponto in pontosGerados) {
      final props = ponto.properties;
      final talhaoIdSalvo = props['db_talhao_id'] as int?;
      if (talhaoIdSalvo != null) {
        final idParcela = pointIdCounter.toString();
        final nomeTalhao = props['talhao_nome']?.toString() ?? 'TALHAO_S_NOME';

        String? idUnicoAmostra;
        if (payload.referenciaRf != null && payload.referenciaRf!.isNotEmpty) {
          idUnicoAmostra = '${payload.referenciaRf!.trim()}-${nomeTalhao.trim()}-${idParcela.trim()}';
        }

        parcelasParaSalvar.add(Parcela(
          talhaoId: talhaoIdSalvo,
          idParcela: idParcela, 
          idUnicoAmostra: idUnicoAmostra,
          areaMetrosQuadrados: 0,
          latitude: ponto.position.latitude, 
          longitude: ponto.position.longitude,
          status: StatusParcela.pendente, 
          dataColeta: DateTime.now(),
          nomeFazenda: props['db_fazenda_nome']?.toString(),
          idFazenda: props['fazenda_id']?.toString(),
          nomeTalhao: nomeTalhao,
          projetoId: payload.projetoId,
          municipio: props['municipio']?.toString(),
          estado: props['estado']?.toString(),
        ));
        pointIdCounter++;
      }
    }

    if (parcelasParaSalvar.isNotEmpty) {
      final batch = db.batch();
      for (final p in parcelasParaSalvar) {
        batch.insert('parcelas', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    }
    
    final optimizerService = ActivityOptimizerService(dbHelper: DatabaseHelper.instance);
    final talhoesRemovidos = await optimizerService.otimizarAtividade(payload.atividadeId);
    
    String mensagemFinal = "${parcelasParaSalvar.length} amostras foram geradas e salvas.";
    if (talhoesRemovidos > 0) {
      mensagemFinal += " $talhoesRemovidos talhões vazios foram otimizados.";
    }
    return mensagemFinal;
}

enum MapLayerType { ruas, satelite, sateliteMapbox }

class MapProvider with ChangeNotifier {
  final _geoJsonService = GeoJsonService();
  final _exportService = ExportService();
  
  final _parcelaRepository = ParcelaRepository();
  final _fazendaRepository = FazendaRepository();
  final _talhaoRepository = TalhaoRepository();
  final _projetoRepository = ProjetoRepository();
  
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

  MapProvider();

  bool get isDrawing => _isDrawing;
  List<LatLng> get drawnPoints => _drawnPoints;
  List<Polygon> get polygons => _importedPolygons.map((f) => f.polygon).toList();
  List<SamplePoint> get samplePoints => _samplePoints;
  bool get isLoading => _isLoading;
  Atividade? get currentAtividade => _currentAtividade;
  MapLayerType get currentLayer => _currentLayer;
  Position? get currentUserPosition => _currentUserPosition;
  bool get isFollowingUser => _isFollowingUser;

  final Map<MapLayerType, String> _tileUrls = {
    MapLayerType.ruas: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    MapLayerType.satelite: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    MapLayerType.sateliteMapbox: 'https://api.mapbox.com/styles/v1/mapbox/satellite-v9/tiles/256/{z}/{x}/{y}@2x?access_token={accessToken}',
  };
  final String _mapboxAccessToken = 'pk.eyJ1IjoiZ2VvZm9yZXN0YXBwIiwiYSI6ImNtY2FyczBwdDAxZmYybHB1OWZlbG1pdW0ifQ.5HeYC0moMJ8dzZzVXKTPrg';

  String get currentTileUrl {
    String url = _tileUrls[_currentLayer]!;
    if (url.contains('{accessToken}')) {
      if (_mapboxAccessToken.isEmpty) return _tileUrls[MapLayerType.satelite]!;
      return url.replaceAll('{accessToken}', _mapboxAccessToken);
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
      final hectaresPorAmostra = double.parse(dadosDoFormulario['hectares']!);
      final now = DateTime.now().toIso8601String();
  
      final talhaoSalvo = await DatabaseHelper.instance.database.then((db) async {
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
            projetoId: _currentAtividade!.projetoId, // <<< MELHORIA DE CONSISTÊNCIA
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
    final hectaresController = TextEditingController();
  
    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Dados da Amostragem'),
          content: Form(
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
          actions: [
            TextButton(onPressed: () {
              nomeFazendaController.dispose();
              codigoFazendaController.dispose();
              nomeTalhaoController.dispose();
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
                    'hectares': hectaresController.text.replaceAll(',', '.'),
                  };
                  nomeFazendaController.dispose();
                  codigoFazendaController.dispose();
                  nomeTalhaoController.dispose();
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

    final projeto = await _projetoRepository.getProjetoById(_currentAtividade!.projetoId);
    
    final poligonosData = poligonos.map((f) => {
      'points': f.polygon.points.map((p) => [p.latitude, p.longitude]).toList(),
      'properties': f.properties,
    }).toList();

    final payload = _GerarAmostrasPayload(
        poligonosData: poligonosData,
        hectaresPerSample: hectaresPerSample,
        atividadeId: _currentAtividade!.id!,
        projetoId: _currentAtividade!.projetoId,
        referenciaRf: projeto?.referenciaRf,
    );
    
    final resultMessage = await compute(_gerarAmostrasInIsolate, payload);

    await loadSamplesParaAtividade();
    _setLoading(false);
    return resultMessage;
  }
  
  Future<String> processarImportacaoDeArquivo({required bool isPlanoDeAmostragem, required BuildContext context}) async {
    if (_currentAtividade == null) {
      return "Erro: Nenhuma atividade selecionada para o planejamento.";
    }
    _setLoading(true);

    try {
      if (isPlanoDeAmostragem) {
        final fileContent = await _geoJsonService.importFileContent();
        if (fileContent != null && fileContent.isNotEmpty) {
          final projeto = await _projetoRepository.getProjetoById(_currentAtividade!.projetoId);
          final payload = _PlanoImportPayload(
            geoJsonContent: fileContent,
            atividadeId: _currentAtividade!.id!,
            projetoId: _currentAtividade!.projetoId,
            referenciaRfDoProjeto: projeto?.referenciaRf,
          );
          final resultMessage = await compute(_processarPlanoDeAmostragemInIsolate, payload);
          await loadSamplesParaAtividade();
          return resultMessage;
        }
      } else {
        final poligonosImportados = await _geoJsonService.importPolygons();
        if (poligonosImportados.isNotEmpty) {
          return await _processarCargaDeTalhoesImportada(poligonosImportados, context);
        }
      }
      
      return "Nenhum arquivo válido foi selecionado.";
    
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
    
    await DatabaseHelper.instance.database.then((db) async => await db.transaction((txn) async {
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
            projetoId: _currentAtividade!.projetoId, // <<< MELHORIA DE CONSISTÊNCIA
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
  
  @override
  void dispose() { 
    _positionStreamSubscription?.cancel(); 
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
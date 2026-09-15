import 'dart:convert';
import 'package:flutter/material.dart';

// ── Tipos de operação silvicultural ─────────────────────────────────────────

enum OperacaoSilviTipo {
  plantio,
  replantio,
  irrigacao,
  adubacao,
  rocada,
  coroamento,
  herbicida,
  formicida,
  capina,
  desbrota,
  outro;

  String get label => switch (this) {
    plantio    => 'Plantio',
    replantio  => 'Replantio',
    irrigacao  => 'Irrigação',
    adubacao   => 'Adubação',
    rocada     => 'Roçada',
    coroamento => 'Coroamento',
    herbicida  => 'Herbicida',
    formicida  => 'Formicida',
    capina     => 'Capina',
    desbrota   => 'Desbrota',
    outro      => 'Outra',
  };

  IconData get icon => switch (this) {
    plantio    => Icons.spa_outlined,
    replantio  => Icons.eco_outlined,
    irrigacao  => Icons.water_drop_outlined,
    adubacao   => Icons.science_outlined,
    rocada     => Icons.grass_outlined,
    coroamento => Icons.circle_outlined,
    herbicida  => Icons.bug_report_outlined,
    formicida  => Icons.pest_control_outlined,
    capina     => Icons.agriculture_outlined,
    desbrota   => Icons.content_cut,
    outro      => Icons.build_outlined,
  };

  Color get color => switch (this) {
    plantio    => Colors.green.shade700,
    replantio  => Colors.teal.shade600,
    irrigacao  => Colors.blue.shade600,
    adubacao   => Colors.purple.shade600,
    rocada     => Colors.lime.shade700,
    coroamento => Colors.orange.shade600,
    herbicida  => Colors.red.shade700,
    formicida  => Colors.deepOrange.shade600,
    capina     => Colors.brown.shade600,
    desbrota   => Colors.indigo.shade600,
    outro      => Colors.grey.shade600,
  };

  static OperacaoSilviTipo fromString(String s) =>
      OperacaoSilviTipo.values.firstWhere((v) => v.name == s, orElse: () => outro);
}

// ── Operação planejada — vinda do OS import ──────────────────────────────────

class OperacaoPlanejada {
  final String tipo;       // OperacaoSilviTipo.name
  final double? areaHa;
  final String? dataPrevista;
  final Map<String, String> extras; // colunas coringa do OS (espécie, produto, etc.)

  const OperacaoPlanejada({
    required this.tipo,
    this.areaHa,
    this.dataPrevista,
    this.extras = const {},
  });

  Map<String, dynamic> toMap() => {
    'tipo': tipo,
    'areaHa': areaHa,
    'dataPrevista': dataPrevista,
    if (extras.isNotEmpty) 'extras': extras,
  };

  factory OperacaoPlanejada.fromMap(Map<String, dynamic> m) {
    final extrasRaw = m['extras'];
    final Map<String, String> extras = {};
    if (extrasRaw is Map) {
      extrasRaw.forEach((k, v) {
        if (k is String && v != null) extras[k] = v.toString();
      });
    }
    return OperacaoPlanejada(
      tipo: m['tipo'] as String? ?? 'outro',
      areaHa: (m['areaHa'] as num?)?.toDouble(),
      dataPrevista: m['dataPrevista'] as String?,
      extras: extras,
    );
  }
}

// ── Centróide silvicultural — localizador do talhão no mapa ─────────────────

class CentroideSilvi {
  final int? id;
  final int? talhaoId;
  final String? fazendaId;
  final String nomeFazenda;
  final String nomeTalhao;
  final double latitude;
  final double longitude;
  final double? areaTotalHa;
  final List<OperacaoPlanejada> operacoesPlanejadas;

  const CentroideSilvi({
    this.id,
    this.talhaoId,
    this.fazendaId,
    required this.nomeFazenda,
    required this.nomeTalhao,
    required this.latitude,
    required this.longitude,
    this.areaTotalHa,
    this.operacoesPlanejadas = const [],
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'talhaoId': talhaoId,
    'fazendaId': fazendaId,
    'nomeFazenda': nomeFazenda,
    'nomeTalhao': nomeTalhao,
    'latitude': latitude,
    'longitude': longitude,
    'areaTotalHa': areaTotalHa,
    'operacoesPlanejadas': jsonEncode(
      operacoesPlanejadas.map((o) => o.toMap()).toList(),
    ),
    'lastModified': DateTime.now().toIso8601String(),
  };

  factory CentroideSilvi.fromMap(Map<String, dynamic> m) {
    final ops = <OperacaoPlanejada>[];
    final raw = m['operacoesPlanejadas'];
    if (raw is String && raw.isNotEmpty) {
      final list = jsonDecode(raw) as List;
      ops.addAll(list.map((e) => OperacaoPlanejada.fromMap(e as Map<String, dynamic>)));
    }
    return CentroideSilvi(
      id: m['id'] as int?,
      talhaoId: m['talhaoId'] as int?,
      fazendaId: m['fazendaId'] as String?,
      nomeFazenda: m['nomeFazenda'] as String? ?? '',
      nomeTalhao: m['nomeTalhao'] as String? ?? '',
      latitude: (m['latitude'] as num).toDouble(),
      longitude: (m['longitude'] as num).toDouble(),
      areaTotalHa: (m['areaTotalHa'] as num?)?.toDouble(),
      operacoesPlanejadas: ops,
    );
  }

  CentroideSilvi copyWith({
    int? id,
    double? areaTotalHa,
    List<OperacaoPlanejada>? operacoesPlanejadas,
  }) =>
      CentroideSilvi(
        id: id ?? this.id,
        talhaoId: talhaoId,
        fazendaId: fazendaId,
        nomeFazenda: nomeFazenda,
        nomeTalhao: nomeTalhao,
        latitude: latitude,
        longitude: longitude,
        areaTotalHa: areaTotalHa ?? this.areaTotalHa,
        operacoesPlanejadas: operacoesPlanejadas ?? this.operacoesPlanejadas,
      );
}

// ── Operação silvicultural executada — registro de campo ─────────────────────

class OperacaoSilvi {
  final int? id;
  final int? centroideId;
  final int? talhaoId;
  final String? fazendaId;
  final String? nomeFazenda;
  final String? nomeTalhao;
  final String tipo;          // OperacaoSilviTipo.name
  final double? areaAplicadaHa;
  final String? areaGeoJson;  // GeoJSON do polígono desenhado — opcional
  final String? dataExecucao;
  final String status;        // pendente | em_andamento | concluida
  final String? observacoes;
  final String? nomeLider;
  final List<String> fotos;
  final double? latitude;
  final double? longitude;
  final bool exportada;
  final bool isSynced;
  final String lastModified;

  const OperacaoSilvi({
    this.id,
    this.centroideId,
    this.talhaoId,
    this.fazendaId,
    this.nomeFazenda,
    this.nomeTalhao,
    required this.tipo,
    this.areaAplicadaHa,
    this.areaGeoJson,
    this.dataExecucao,
    this.status = 'concluida',
    this.observacoes,
    this.nomeLider,
    this.fotos = const [],
    this.latitude,
    this.longitude,
    this.exportada = false,
    this.isSynced = false,
    required this.lastModified,
  });

  OperacaoSilviTipo get tipoEnum => OperacaoSilviTipo.fromString(tipo);

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'centroideId': centroideId,
    'talhaoId': talhaoId,
    'fazendaId': fazendaId,
    'nomeFazenda': nomeFazenda,
    'nomeTalhao': nomeTalhao,
    'tipo': tipo,
    'areaAplicadaHa': areaAplicadaHa,
    'areaGeoJson': areaGeoJson,
    'dataExecucao': dataExecucao,
    'status': status,
    'observacoes': observacoes,
    'nomeLider': nomeLider,
    'fotos': jsonEncode(fotos),
    'latitude': latitude,
    'longitude': longitude,
    'exportada': exportada ? 1 : 0,
    'isSynced': isSynced ? 1 : 0,
    'lastModified': lastModified,
  };

  factory OperacaoSilvi.fromMap(Map<String, dynamic> m) {
    List<String> fotosList = [];
    final fr = m['fotos'];
    if (fr is String && fr.isNotEmpty) {
      fotosList = List<String>.from(jsonDecode(fr));
    }
    return OperacaoSilvi(
      id: m['id'] as int?,
      centroideId: m['centroideId'] as int?,
      talhaoId: m['talhaoId'] as int?,
      fazendaId: m['fazendaId'] as String?,
      nomeFazenda: m['nomeFazenda'] as String?,
      nomeTalhao: m['nomeTalhao'] as String?,
      tipo: m['tipo'] as String? ?? 'outro',
      areaAplicadaHa: (m['areaAplicadaHa'] as num?)?.toDouble(),
      areaGeoJson: m['areaGeoJson'] as String?,
      dataExecucao: m['dataExecucao'] as String?,
      status: m['status'] as String? ?? 'concluida',
      observacoes: m['observacoes'] as String?,
      nomeLider: m['nomeLider'] as String?,
      fotos: fotosList,
      latitude: (m['latitude'] as num?)?.toDouble(),
      longitude: (m['longitude'] as num?)?.toDouble(),
      exportada: (m['exportada'] as int? ?? 0) == 1,
      isSynced: (m['isSynced'] as int? ?? 0) == 1,
      lastModified: m['lastModified'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  OperacaoSilvi copyWith({
    int? id,
    double? areaAplicadaHa,
    String? areaGeoJson,
    String? dataExecucao,
    String? status,
    String? observacoes,
    List<String>? fotos,
    double? latitude,
    double? longitude,
    bool? exportada,
    bool? isSynced,
  }) =>
      OperacaoSilvi(
        id: id ?? this.id,
        centroideId: centroideId,
        talhaoId: talhaoId,
        fazendaId: fazendaId,
        nomeFazenda: nomeFazenda,
        nomeTalhao: nomeTalhao,
        tipo: tipo,
        areaAplicadaHa: areaAplicadaHa ?? this.areaAplicadaHa,
        areaGeoJson: areaGeoJson ?? this.areaGeoJson,
        dataExecucao: dataExecucao ?? this.dataExecucao,
        status: status ?? this.status,
        observacoes: observacoes ?? this.observacoes,
        nomeLider: nomeLider,
        fotos: fotos ?? this.fotos,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        exportada: exportada ?? this.exportada,
        isSynced: isSynced ?? this.isSynced,
        lastModified: DateTime.now().toIso8601String(),
      );
}

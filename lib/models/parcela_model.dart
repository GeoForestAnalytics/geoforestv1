// lib/models/parcela_model.dart (VERSÃO CORRIGIDA PARA SINCRONIZAÇÃO)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';

enum StatusParcela {
  pendente(Icons.pending_outlined, Colors.grey),
  emAndamento(Icons.edit_note_outlined, Colors.orange),
  concluida(Icons.check_circle_outline, Colors.green),
  exportada(Icons.cloud_done_outlined, Colors.blue);

  final IconData icone;
  final Color cor;
  
  const StatusParcela(this.icone, this.cor);
}

class Parcela {
  int? dbId;
  String uuid;
  int? talhaoId; 
  DateTime? dataColeta;
  final String? idFazenda;
  final String? nomeFazenda;
  final String? nomeTalhao;
  final String? nomeLider;
  final int? projetoId;
  final String? municipio;
  final String? estado;
  final String? atividadeTipo;
  final String? up;
  final String? referenciaRf;
  final String? ciclo;
  final int? rotacao;
  final String? tipoParcela;
  final String? formaParcela;
  final double? lado1;
  final double? lado2;
  final double? declividade;
  final String idParcela;
  final double areaMetrosQuadrados;
  final String? observacao;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  StatusParcela status;
  bool exportada;
  bool isSynced;
  List<String> photoPaths;
  List<Arvore> arvores;
  final DateTime? lastModified;
  // Instrumento padrão da amostra: 'fita' (CAP) ou 'suta' (DAP). Vale para todas as árvores da parcela.
  final String tipoMedidaCAP;

  Parcela({
    this.dbId, String? uuid, required this.talhaoId, required this.idParcela,
    required this.areaMetrosQuadrados, this.idFazenda, this.nomeFazenda,
    this.nomeTalhao, this.observacao, this.latitude, this.longitude,
    this.altitude, this.dataColeta, this.status = StatusParcela.pendente,
    this.exportada = false, this.isSynced = false, this.nomeLider,
    this.projetoId, this.municipio, this.estado, this.atividadeTipo,
    this.up, this.referenciaRf, this.ciclo, this.rotacao, this.tipoParcela,
    this.formaParcela, this.lado1, this.lado2, this.declividade,
    this.photoPaths = const [], this.arvores = const [], this.lastModified,
    this.tipoMedidaCAP = 'fita',
  }) : uuid = uuid ?? const Uuid().v4();

  Parcela copyWith({
    int? dbId, String? uuid, int? talhaoId, String? idFazenda, String? nomeFazenda,
    String? nomeTalhao, String? idParcela, double? areaMetrosQuadrados, String? observacao,
    double? latitude, double? longitude,double? altitude, DateTime? dataColeta, StatusParcela? status,
    bool? exportada, bool? isSynced, String? nomeLider, int? projetoId,
    String? municipio, String? estado, String? atividadeTipo, String? up,
    String? referenciaRf, String? ciclo, int? rotacao, String? tipoParcela,
    String? formaParcela, double? lado1, double? lado2, double? declividade, List<String>? photoPaths,
    List<Arvore>? arvores, DateTime? lastModified, String? tipoMedidaCAP,
  }) {
    return Parcela(
      dbId: dbId ?? this.dbId, uuid: uuid ?? this.uuid, talhaoId: talhaoId ?? this.talhaoId,
      idFazenda: idFazenda ?? this.idFazenda, nomeFazenda: nomeFazenda ?? this.nomeFazenda,
      nomeTalhao: nomeTalhao ?? this.nomeTalhao, idParcela: idParcela ?? this.idParcela,
      areaMetrosQuadrados: areaMetrosQuadrados ?? this.areaMetrosQuadrados, observacao: observacao ?? this.observacao,
      latitude: latitude ?? this.latitude, longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude, dataColeta: dataColeta ?? this.dataColeta,
      status: status ?? this.status, exportada: exportada ?? this.exportada,
      isSynced: isSynced ?? this.isSynced, nomeLider: nomeLider ?? this.nomeLider,
      projetoId: projetoId ?? this.projetoId, municipio: municipio ?? this.municipio,
      estado: estado ?? this.estado, atividadeTipo: atividadeTipo ?? this.atividadeTipo,
      up: up ?? this.up, referenciaRf: referenciaRf ?? this.referenciaRf, ciclo: ciclo ?? this.ciclo,
      rotacao: rotacao ?? this.rotacao, tipoParcela: tipoParcela ?? this.tipoParcela,
      formaParcela: formaParcela ?? this.formaParcela, lado1: lado1 ?? this.lado1,
      lado2: lado2 ?? this.lado2, declividade: declividade ?? this.declividade,
      photoPaths: photoPaths ?? this.photoPaths, arvores: arvores ?? this.arvores,
      lastModified: lastModified ?? this.lastModified,
      tipoMedidaCAP: tipoMedidaCAP ?? this.tipoMedidaCAP,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      DbParcelas.id: dbId, DbParcelas.uuid: uuid, DbParcelas.talhaoId: talhaoId,DbParcelas.atividadeTipo: atividadeTipo, 
      DbParcelas.idFazenda: idFazenda, DbParcelas.nomeFazenda: nomeFazenda, 
      DbParcelas.nomeTalhao: nomeTalhao, DbParcelas.idParcela: idParcela,
      DbParcelas.areaMetrosQuadrados: areaMetrosQuadrados, DbParcelas.observacao: observacao,
      DbParcelas.latitude: latitude, DbParcelas.longitude: longitude, 
      DbParcelas.altitude: altitude, 
      
      // >>> CORREÇÃO 1: Se estiver concluída mas sem data, insere data de agora <<<
      DbParcelas.dataColeta: dataColeta?.toIso8601String() ?? (status == StatusParcela.concluida ? DateTime.now().toIso8601String() : null),
      
      DbParcelas.status: status.name, DbParcelas.exportada: exportada ? 1 : 0, 
      DbParcelas.isSynced: isSynced ? 1 : 0, DbParcelas.nomeLider: nomeLider, 
      DbParcelas.projetoId: projetoId, DbParcelas.municipio: municipio, DbParcelas.estado: estado,
      DbParcelas.up: up, DbParcelas.referenciaRf: referenciaRf, DbParcelas.ciclo: ciclo, 
      DbParcelas.rotacao: rotacao, DbParcelas.tipoParcela: tipoParcela, 
      DbParcelas.formaParcela: formaParcela, DbParcelas.lado1: lado1, DbParcelas.lado2: lado2,
      DbParcelas.declividade: declividade, DbParcelas.photoPaths: jsonEncode(photoPaths),
      'arvores': arvores.map((a) => a.toMap()).toList(), // Firestore aceita List de Map diretamente
      DbParcelas.lastModified: lastModified?.toIso8601String(),
      DbParcelas.tipoMedidaCAP: tipoMedidaCAP,
    };
  }

  factory Parcela.fromMap(Map<String, dynamic> map) {
  DateTime? parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  List<Arvore> listaArvores = [];
  if (map['arvores'] != null) {
    if (map['arvores'] is String) {
      // Se vier do SQLite (Texto JSON)
      final List<dynamic> decoded = jsonDecode(map['arvores']);
      listaArvores = decoded.map((item) => Arvore.fromMap(item)).toList();
    } else if (map['arvores'] is List) {
      // Se vier do Firebase (Lista de Mapas)
      listaArvores = (map['arvores'] as List)
          .map((item) => Arvore.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    }
  }  

  List<String> paths = [];
  if (map[DbParcelas.photoPaths] != null) {
    try {
      paths = List<String>.from(jsonDecode(map[DbParcelas.photoPaths]));
    } catch (e) {
      debugPrint("Erro ao decodificar photoPaths: $e");
    }
  }
  
  return Parcela(
    dbId: map[DbParcelas.id],
    uuid: map[DbParcelas.uuid] ?? const Uuid().v4(),
    talhaoId: map[DbParcelas.talhaoId],
    idFazenda: map[DbParcelas.idFazenda],
    nomeFazenda: map[DbParcelas.nomeFazenda],
    nomeTalhao: map[DbParcelas.nomeTalhao],
    idParcela: map[DbParcelas.idParcela] ?? 'ID_N/A',
    areaMetrosQuadrados: (map[DbParcelas.areaMetrosQuadrados] as num?)?.toDouble() ?? 0.0,
    observacao: map[DbParcelas.observacao],
    latitude: (map[DbParcelas.latitude] as num?)?.toDouble(),
    longitude: (map[DbParcelas.longitude] as num?)?.toDouble(),
    altitude: (map[DbParcelas.altitude] as num?)?.toDouble(),
    dataColeta: parseDate(map[DbParcelas.dataColeta]),
    arvores: listaArvores,
    
    // --- LÓGICA DE STATUS ---
    status: StatusParcela.values.firstWhere(
      (e) => e.name.toLowerCase() == map[DbParcelas.status]?.toString().toLowerCase(),
      orElse: () => StatusParcela.pendente
    ),
    
    exportada: map[DbParcelas.exportada] == 1,
    isSynced: map[DbParcelas.isSynced] == 1,
    nomeLider: map[DbParcelas.nomeLider],
    projetoId: map[DbParcelas.projetoId],

    // ============================================================
    // AQUI ESTÁ A CORREÇÃO: Lendo a nova coluna do banco de dados
    // ============================================================
    atividadeTipo: map[DbParcelas.atividadeTipo], 
    // ============================================================

    up: map[DbParcelas.up],
    referenciaRf: map[DbParcelas.referenciaRf],
    ciclo: map[DbParcelas.ciclo]?.toString(),
    rotacao: int.tryParse(map[DbParcelas.rotacao]?.toString() ?? ''),
    tipoParcela: map[DbParcelas.tipoParcela],
    formaParcela: map[DbParcelas.formaParcela],
    lado1: (map[DbParcelas.lado1] as num?)?.toDouble(),
    lado2: (map[DbParcelas.lado2] as num?)?.toDouble(),
    declividade: (map[DbParcelas.declividade] as num?)?.toDouble(),
    photoPaths: paths,
    lastModified: parseDate(map[DbParcelas.lastModified]),
    tipoMedidaCAP: map[DbParcelas.tipoMedidaCAP]?.toString() ?? 'fita',
  );
}
}

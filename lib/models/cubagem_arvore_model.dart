// lib/models/cubagem_arvore_model.dart

import 'dart:convert'; // <--- NOVO: Necessário para o jsonEncode
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:geoforestv1/models/cubagem_secao_model.dart'; // <--- NOVO: Importar o modelo de seção

class CubagemArvore {
  int? id;
  int? talhaoId;
  String? idFazenda;
  String nomeFazenda;
  String nomeTalhao;
  String identificador;
  String? classe;
  bool exportada;
  bool isSynced;
  String? nomeLider;
  double alturaTotal;
  String tipoMedidaCAP;
  double valorCAP;
  double alturaBase;
  final String? observacao;
  final double? latitude;
  final double? longitude;
  final String? metodoCubagem;
  final String? rf;
  final DateTime? dataColeta;
  final DateTime? lastModified;
  
  // 1. ADICIONAR A LISTA DE SEÇÕES AQUI
  List<CubagemSecao> secoes; // <--- NOVO

  CubagemArvore({
    this.id,
    this.talhaoId,
    this.idFazenda,
    required this.nomeFazenda,
    required this.nomeTalhao,
    required this.identificador,
    this.classe,
    this.exportada = false,
    this.isSynced = false,
    this.nomeLider,
    this.alturaTotal = 0,
    this.tipoMedidaCAP = 'fita',
    this.valorCAP = 0,
    this.alturaBase = 0,
    this.observacao,
    this.latitude,
    this.longitude,
    this.metodoCubagem,
    this.rf,
    this.dataColeta,
    this.lastModified,
    this.secoes = const [], // <--- NOVO: Inicializar como lista vazia
  });

  CubagemArvore copyWith({
    int? id, int? talhaoId, String? idFazenda, String? nomeFazenda, String? nomeTalhao,
    String? identificador, String? classe, bool? exportada, bool? isSynced,
    String? nomeLider, double? alturaTotal, String? tipoMedidaCAP, double? valorCAP,
    double? alturaBase, String? observacao, double? latitude, double? longitude,
    String? metodoCubagem, String? rf, DateTime? dataColeta, DateTime? lastModified,
    List<CubagemSecao>? secoes, // <--- NOVO
  }) {
    return CubagemArvore(
      id: id ?? this.id,
      talhaoId: talhaoId ?? this.talhaoId,
      idFazenda: idFazenda ?? this.idFazenda,
      nomeFazenda: nomeFazenda ?? this.nomeFazenda,
      nomeTalhao: nomeTalhao ?? this.nomeTalhao,
      identificador: identificador ?? this.identificador,
      classe: classe ?? this.classe,
      exportada: exportada ?? this.exportada,
      isSynced: isSynced ?? this.isSynced,
      nomeLider: nomeLider ?? this.nomeLider,
      alturaTotal: alturaTotal ?? this.alturaTotal,
      tipoMedidaCAP: tipoMedidaCAP ?? this.tipoMedidaCAP,
      valorCAP: valorCAP ?? this.valorCAP,
      alturaBase: alturaBase ?? this.alturaBase,
      observacao: observacao ?? this.observacao,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      metodoCubagem: metodoCubagem ?? this.metodoCubagem,
      rf: rf ?? this.rf,
      dataColeta: dataColeta ?? this.dataColeta,
      lastModified: lastModified ?? this.lastModified,
      secoes: secoes ?? this.secoes, // <--- NOVO
    );
  }

  Map<String, dynamic> toMap() {
    return {
      DbCubagensArvores.id: id,
      DbCubagensArvores.talhaoId: talhaoId,
      DbCubagensArvores.idFazenda: idFazenda,
      DbCubagensArvores.nomeFazenda: nomeFazenda,
      DbCubagensArvores.nomeTalhao: nomeTalhao,
      DbCubagensArvores.identificador: identificador,
      DbCubagensArvores.classe: classe,
      DbCubagensArvores.alturaTotal: alturaTotal,
      DbCubagensArvores.tipoMedidaCAP: tipoMedidaCAP,
      DbCubagensArvores.valorCAP: valorCAP,
      DbCubagensArvores.alturaBase: alturaBase,
      DbCubagensArvores.observacao: observacao,
      DbCubagensArvores.latitude: latitude,
      DbCubagensArvores.longitude: longitude,
      DbCubagensArvores.metodoCubagem: metodoCubagem,
      DbCubagensArvores.rf: rf,      
      DbCubagensArvores.dataColeta: dataColeta?.toIso8601String() ?? (alturaTotal > 0 ? DateTime.now().toIso8601String() : null),      
      DbCubagensArvores.exportada: exportada ? 1 : 0,
      DbCubagensArvores.isSynced: isSynced ? 1 : 0,
      DbCubagensArvores.nomeLider: nomeLider,
      
      // 2. EMPACOTAR AS SEÇÕES COMO JSON AQUI
      'secoes': jsonEncode(secoes.map((s) => s.toMap()).toList()), // <--- NOVO
      
      DbCubagensArvores.lastModified: lastModified?.toIso8601String(),
    };
  }

  factory CubagemArvore.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    // 3. LÓGICA PARA LER O "PACOTE" DE SEÇÕES (Resiliente)
    List<CubagemSecao> listaSecoes = []; // <--- NOVO
    if (map['secoes'] != null) { // <--- NOVO
      try {
        var raw = map['secoes'];
        // Se for String (SQLite), faz o decode. Se for List (Firebase), usa direto.
        var decoded = raw is String ? jsonDecode(raw) : raw;
        if (decoded is List) {
          listaSecoes = decoded.map((s) => CubagemSecao.fromMap(Map<String, dynamic>.from(s))).toList();
        }
      } catch (e) {
        print("Erro ao decodificar secoes: $e");
      }
    }

    return CubagemArvore(
      id: map[DbCubagensArvores.id],
      talhaoId: map[DbCubagensArvores.talhaoId],
      idFazenda: map[DbCubagensArvores.idFazenda],
      nomeFazenda: map[DbCubagensArvores.nomeFazenda] ?? '',
      nomeTalhao: map[DbCubagensArvores.nomeTalhao] ?? '',
      identificador: map[DbCubagensArvores.identificador],
      classe: map[DbCubagensArvores.classe],
      observacao: map[DbCubagensArvores.observacao],
      latitude: (map[DbCubagensArvores.latitude] as num?)?.toDouble(),
      longitude: (map[DbCubagensArvores.longitude] as num?)?.toDouble(),
      metodoCubagem: map[DbCubagensArvores.metodoCubagem],
      rf: map[DbCubagensArvores.rf],
      dataColeta: parseDate(map[DbCubagensArvores.dataColeta]),
      exportada: map[DbCubagensArvores.exportada] == 1,
      isSynced: map[DbCubagensArvores.isSynced] == 1,
      nomeLider: map[DbCubagensArvores.nomeLider],
      
      alturaTotal: (map[DbCubagensArvores.alturaTotal] is String)
          ? double.tryParse(map[DbCubagensArvores.alturaTotal].toString().replaceAll(',', '.')) ?? 0.0
          : (map[DbCubagensArvores.alturaTotal] as num?)?.toDouble() ?? 0.0,
          
      tipoMedidaCAP: map[DbCubagensArvores.tipoMedidaCAP] ?? 'fita',
      
      valorCAP: (map[DbCubagensArvores.valorCAP] is String)
          ? double.tryParse(map[DbCubagensArvores.valorCAP].toString().replaceAll(',', '.')) ?? 0.0
          : (map[DbCubagensArvores.valorCAP] as num?)?.toDouble() ?? 0.0,
          
      alturaBase: (map[DbCubagensArvores.alturaBase] is String)
          ? double.tryParse(map[DbCubagensArvores.alturaBase].toString().replaceAll(',', '.')) ?? 0.0
          : (map[DbCubagensArvores.alturaBase] as num?)?.toDouble() ?? 0.0,
      
      secoes: listaSecoes, // <--- NOVO: Atribuir a lista carregada
      lastModified: parseDate(map[DbCubagensArvores.lastModified]),
    );
  }
}
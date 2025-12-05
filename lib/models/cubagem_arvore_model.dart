// lib/models/cubagem_arvore_model.dart (VERSÃO CORRIGIDA E ROBUSTA)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';

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

  CubagemArvore({
    this.id, this.talhaoId, this.idFazenda, required this.nomeFazenda,
    required this.nomeTalhao, required this.identificador, this.classe,
    this.exportada = false, this.isSynced = false, this.nomeLider,
    this.alturaTotal = 0, this.tipoMedidaCAP = 'fita', this.valorCAP = 0,
    this.alturaBase = 0, this.observacao, this.latitude, this.longitude,
    this.metodoCubagem, this.rf, this.dataColeta, this.lastModified,
  });

  CubagemArvore copyWith({
    int? id, int? talhaoId, String? idFazenda, String? nomeFazenda, String? nomeTalhao,
    String? identificador, String? classe, bool? exportada, bool? isSynced,
    String? nomeLider, double? alturaTotal, String? tipoMedidaCAP, double? valorCAP,
    double? alturaBase, String? observacao, double? latitude, double? longitude,
    String? metodoCubagem, String? rf, DateTime? dataColeta, DateTime? lastModified,
  }) {
    return CubagemArvore(
      id: id ?? this.id, talhaoId: talhaoId ?? this.talhaoId,
      idFazenda: idFazenda ?? this.idFazenda, nomeFazenda: nomeFazenda ?? this.nomeFazenda,
      nomeTalhao: nomeTalhao ?? this.nomeTalhao, identificador: identificador ?? this.identificador,
      classe: classe ?? this.classe, exportada: exportada ?? this.exportada,
      isSynced: isSynced ?? this.isSynced, nomeLider: nomeLider ?? this.nomeLider,
      alturaTotal: alturaTotal ?? this.alturaTotal, tipoMedidaCAP: tipoMedidaCAP ?? this.tipoMedidaCAP,
      valorCAP: valorCAP ?? this.valorCAP, alturaBase: alturaBase ?? this.alturaBase,
      observacao: observacao ?? this.observacao, latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude, metodoCubagem: metodoCubagem ?? this.metodoCubagem,
      rf: rf ?? this.rf, dataColeta: dataColeta ?? this.dataColeta,
      lastModified: lastModified ?? this.lastModified,
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
      
      // >>> CORREÇÃO 1: Se tem altura (foi medida) mas não tem data, insere AGORA <<<
      DbCubagensArvores.dataColeta: dataColeta?.toIso8601String() ?? (alturaTotal > 0 ? DateTime.now().toIso8601String() : null),
      
      DbCubagensArvores.exportada: exportada ? 1 : 0,
      DbCubagensArvores.isSynced: isSynced ? 1 : 0,
      DbCubagensArvores.nomeLider: nomeLider,
      DbCubagensArvores.lastModified: lastModified?.toIso8601String(),
    };
  }

  factory CubagemArvore.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
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
      
      // >>> CORREÇÃO 2: Robustez na leitura de números (String ou Num) <<<
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
      
      lastModified: parseDate(map[DbCubagensArvores.lastModified]),
    );
  }
}
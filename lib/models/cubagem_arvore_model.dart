// lib/models/cubagem_arvore_model.dart (VERSÃO ATUALIZADA E CORRIGIDA)
import 'package:cloud_firestore/cloud_firestore.dart'; // <<< PASSO 1: IMPORTAR CLOUD_FIRESTORE

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
  final DateTime? lastModified;

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
    this.lastModified,
  });

  CubagemArvore copyWith({
    int? id,
    int? talhaoId,
    String? idFazenda,
    String? nomeFazenda,
    String? nomeTalhao,
    String? identificador,
    String? classe,
    bool? exportada,
    bool? isSynced,
    String? nomeLider,
    double? alturaTotal,
    String? tipoMedidaCAP,
    double? valorCAP,
    double? alturaBase,
    DateTime? lastModified,
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
      lastModified: lastModified ?? this.lastModified,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'talhaoId': talhaoId,
      'id_fazenda': idFazenda,
      'nome_fazenda': nomeFazenda,
      'nome_talhao': nomeTalhao,
      'identificador': identificador,
      'classe': classe,
      'alturaTotal': alturaTotal,
      'tipoMedidaCAP': tipoMedidaCAP,
      'valorCAP': valorCAP,
      'alturaBase': alturaBase,
      'exportada': exportada ? 1 : 0,
      'isSynced': isSynced ? 1 : 0,
      'nomeLider': nomeLider,
      'lastModified': lastModified?.toIso8601String(),
    };
  }

  factory CubagemArvore.fromMap(Map<String, dynamic> map) {
    // <<< PASSO 2: ADICIONAR FUNÇÃO AUXILIAR PARA PARSE DE DATAS >>>
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      } else if (value is String) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    return CubagemArvore(
      id: map['id'],
      talhaoId: map['talhaoId'],
      idFazenda: map['id_fazenda'],
      nomeFazenda: map['nome_fazenda'] ?? '',
      nomeTalhao: map['nome_talhao'] ?? '',
      identificador: map['identificador'],
      classe: map['classe'],
      exportada: map['exportada'] == 1,
      isSynced: map['isSynced'] == 1,
      nomeLider: map['nomeLider'],
      alturaTotal: map['alturaTotal']?.toDouble() ?? 0,
      tipoMedidaCAP: map['tipoMedidaCAP'] ?? 'fita',
      valorCAP: map['valorCAP']?.toDouble() ?? 0,
      alturaBase: map['alturaBase']?.toDouble() ?? 0,
      // <<< PASSO 3: USAR A FUNÇÃO AUXILIAR NO CAMPO 'lastModified' >>>
      lastModified: parseDate(map['lastModified']),
    );
  }
}
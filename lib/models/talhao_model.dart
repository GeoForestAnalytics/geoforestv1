// lib/models/talhao_model.dart (VERSÃO ATUALIZADA PARA O.S. KLABIN)
import 'package:cloud_firestore/cloud_firestore.dart';

/// Representa uma área de manejo florestal, conhecida como talhão.
class Talhao {
  /// ID único do banco de dados local (gerado automaticamente).
  final int? id;
  
  /// ID da fazenda à qual o talhão pertence.
  final String fazendaId; 
  
  /// ID da atividade à qual o talhão está vinculado.
  final int fazendaAtividadeId;
  
  /// ID do projeto pai, obtido através de JOINs.
  final int? projetoId;
  
  /// Nome ou código identificador do talhão.
  final String nome;
  
  /// Área do talhão em hectares.
  final double? areaHa;
  
  /// Idade do plantio em anos.
  final double? idadeAnos;
  
  /// Espécie florestal plantada.
  final String? especie;
  
  /// Espaçamento de plantio (ex: "3x2").
  final String? espacamento;
  
  /// Nome da fazenda (geralmente obtido via JOIN).
  final String? fazendaNome;
  
  final String? municipio;
  final String? estado;
  
  /// Volume total de madeira estimado para o talhão.
  double? volumeTotalTalhao;
  
  /// Data e hora da última modificação do registro.
  final DateTime? lastModified;

  // <<< NOVOS CAMPOS DA O.S. KLABIN >>>
  /// Bloco ao qual o talhão pertence.
  final String? bloco;
  /// Unidade de Produção (UP), vindo da coluna RF.
  final String? up;
  /// Material genético utilizado no plantio.
  final String? materialGenetico;
  /// Data do plantio.
  final String? dataPlantio;

  Talhao({
    this.id,
    required this.fazendaId,
    required this.fazendaAtividadeId,
    this.projetoId,
    required this.nome,
    this.areaHa,
    this.idadeAnos,
    this.especie,
    this.espacamento,
    this.fazendaNome,
    this.municipio,
    this.estado,
    this.volumeTotalTalhao,
    this.lastModified,
    this.bloco,
    this.up,
    this.materialGenetico,
    this.dataPlantio,
  });

  Talhao copyWith({
    int? id, String? fazendaId, int? fazendaAtividadeId, int? projetoId, String? nome,
    double? areaHa, double? idadeAnos, String? especie, String? espacamento, String? fazendaNome,
    String? municipio, String? estado, double? volumeTotalTalhao, DateTime? lastModified,
    String? bloco, String? up, String? materialGenetico, String? dataPlantio,
  }) {
    return Talhao(
      id: id ?? this.id,
      fazendaId: fazendaId ?? this.fazendaId,
      fazendaAtividadeId: fazendaAtividadeId ?? this.fazendaAtividadeId,
      projetoId: projetoId ?? this.projetoId,
      nome: nome ?? this.nome,
      areaHa: areaHa ?? this.areaHa,
      idadeAnos: idadeAnos ?? this.idadeAnos,
      especie: especie ?? this.especie,
      espacamento: espacamento ?? this.espacamento,
      fazendaNome: fazendaNome ?? this.fazendaNome,
      municipio: municipio ?? this.municipio,
      estado: estado ?? this.estado,
      volumeTotalTalhao: volumeTotalTalhao ?? this.volumeTotalTalhao,
      lastModified: lastModified ?? this.lastModified,
      bloco: bloco ?? this.bloco,
      up: up ?? this.up,
      materialGenetico: materialGenetico ?? this.materialGenetico,
      dataPlantio: dataPlantio ?? this.dataPlantio,
    );
  }

  /// Converte para um Map para o BANCO DE DADOS LOCAL.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fazendaId': fazendaId,
      'fazendaAtividadeId': fazendaAtividadeId,
      'projetoId': projetoId,
      'nome': nome,
      'areaHa': areaHa,
      'idadeAnos': idadeAnos,
      'especie': especie,
      'espacamento': espacamento,
      'bloco': bloco,
      'up': up,
      'material_genetico': materialGenetico,
      'data_plantio': dataPlantio,
      'lastModified': lastModified?.toIso8601String(), 
    };
  }

  /// Converte para um Map para o FIRESTORE.
  Map<String, dynamic> toFirestoreMap() {
    return {
      'id': id,
      'fazendaId': fazendaId,
      'fazendaAtividadeId': fazendaAtividadeId,
      'nome': nome,
      'areaHa': areaHa,
      'idadeAnos': idadeAnos,
      'especie': especie,
      'espacamento': espacamento,
      'bloco': bloco,
      'up': up,
      'material_genetico': materialGenetico,
      'data_plantio': dataPlantio,
      // lastModified é gerenciado pelo servidor no Firestore
    };
  }
  
  factory Talhao.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return Talhao(
      id: map['id'],
      fazendaId: map['fazendaId'],
      fazendaAtividadeId: map['fazendaAtividadeId'],
      projetoId: map['projetoId'],
      nome: map['nome'],
      areaHa: map['areaHa'],
      idadeAnos: map['idadeAnos'],
      especie: map['especie'],
      espacamento: map['espacamento'],
      fazendaNome: map['fazendaNome'],
      municipio: map['municipio'],
      estado: map['estado'],
      bloco: map['bloco'],
      up: map['up'],
      materialGenetico: map['material_genetico'],
      dataPlantio: map['data_plantio'],
      lastModified: parseDate(map['lastModified']),
    );
  }
}
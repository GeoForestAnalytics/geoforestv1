// lib/models/sortimento_model.dart (VERSÃO REFATORADA)

import 'package:geoforestv1/data/datasources/local/database_constants.dart';

class SortimentoModel {
  final int? id;
  final String nome;
  final double comprimento;
  final double diametroMinimo;
  final double diametroMaximo;

  SortimentoModel({
    this.id,
    required this.nome,
    required this.comprimento,
    required this.diametroMinimo,
    required this.diametroMaximo,
  });

  Map<String, dynamic> toMap() {
    return {
      DbSortimentos.id: id,
      DbSortimentos.nome: nome,
      DbSortimentos.comprimento: comprimento,
      DbSortimentos.diametroMinimo: diametroMinimo,
      DbSortimentos.diametroMaximo: diametroMaximo,
    };
  }

  factory SortimentoModel.fromMap(Map<String, dynamic> map) {
    return SortimentoModel(
      id: map[DbSortimentos.id],
      nome: map[DbSortimentos.nome] ?? '',
      comprimento: (map[DbSortimentos.comprimento] as num?)?.toDouble() ?? 0.0,
      diametroMinimo: (map[DbSortimentos.diametroMinimo] as num?)?.toDouble() ?? 0.0,
      diametroMaximo: (map[DbSortimentos.diametroMaximo] as num?)?.toDouble() ?? 0.0,
    );
  }
}
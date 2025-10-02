// lib/models/diario_de_campo_model.dart (VERSÃO REFATORADA)

import 'package:geoforestv1/data/datasources/local/database_constants.dart';

class DiarioDeCampo {
  final int? id;
  final String dataRelatorio;
  final String nomeLider;
  final int projetoId;
  final int? talhaoId;
  final double? kmInicial;
  final double? kmFinal;
  final String? localizacaoDestino;
  final double? pedagioValor;
  final double? abastecimentoValor;
  final int? alimentacaoMarmitasQtd;
  final double? alimentacaoRefeicaoValor;
  final String? alimentacaoDescricao;
  final double? outrasDespesasValor;
  final String? outrasDespesasDescricao;
  final String? veiculoPlaca;
  final String? veiculoModelo;
  final String? equipeNoCarro;
  final String lastModified;
  final String? locaisTrabalhadosJson;

  DiarioDeCampo({
    this.id,
    required this.dataRelatorio,
    required this.nomeLider,
    required this.projetoId,
    this.talhaoId,
    this.kmInicial,
    this.kmFinal,
    this.localizacaoDestino,
    this.pedagioValor,
    this.abastecimentoValor,
    this.alimentacaoMarmitasQtd,
    this.alimentacaoRefeicaoValor,
    this.alimentacaoDescricao,
    this.outrasDespesasValor,
    this.outrasDespesasDescricao,
    this.veiculoPlaca,
    this.veiculoModelo,
    this.equipeNoCarro,
    required this.lastModified,
    this.locaisTrabalhadosJson,
  });

  Map<String, dynamic> toMap() {
    return {
      DbDiarioDeCampo.id: id,
      DbDiarioDeCampo.dataRelatorio: dataRelatorio,
      DbDiarioDeCampo.nomeLider: nomeLider,
      DbDiarioDeCampo.projetoId: projetoId,
      DbDiarioDeCampo.talhaoId: talhaoId,
      DbDiarioDeCampo.kmInicial: kmInicial,
      DbDiarioDeCampo.kmFinal: kmFinal,
      DbDiarioDeCampo.localizacaoDestino: localizacaoDestino,
      DbDiarioDeCampo.pedagioValor: pedagioValor,
      DbDiarioDeCampo.abastecimentoValor: abastecimentoValor,
      DbDiarioDeCampo.alimentacaoMarmitasQtd: alimentacaoMarmitasQtd,
      DbDiarioDeCampo.alimentacaoRefeicaoValor: alimentacaoRefeicaoValor,
      DbDiarioDeCampo.alimentacaoDescricao: alimentacaoDescricao,
      DbDiarioDeCampo.outrasDespesasValor: outrasDespesasValor,
      DbDiarioDeCampo.outrasDespesasDescricao: outrasDespesasDescricao,
      DbDiarioDeCampo.veiculoPlaca: veiculoPlaca,
      DbDiarioDeCampo.veiculoModelo: veiculoModelo,
      DbDiarioDeCampo.equipeNoCarro: equipeNoCarro,
      DbDiarioDeCampo.lastModified: lastModified,
    };
  }

  factory DiarioDeCampo.fromMap(Map<String, dynamic> map) {
    return DiarioDeCampo(
      id: map[DbDiarioDeCampo.id],
      dataRelatorio: map[DbDiarioDeCampo.dataRelatorio],
      nomeLider: map[DbDiarioDeCampo.nomeLider],
      projetoId: map[DbDiarioDeCampo.projetoId],
      talhaoId: map[DbDiarioDeCampo.talhaoId],
      kmInicial: (map[DbDiarioDeCampo.kmInicial] as num?)?.toDouble(),
      kmFinal: (map[DbDiarioDeCampo.kmFinal] as num?)?.toDouble(),
      localizacaoDestino: map[DbDiarioDeCampo.localizacaoDestino],
      pedagioValor: (map[DbDiarioDeCampo.pedagioValor] as num?)?.toDouble(),
      abastecimentoValor: (map[DbDiarioDeCampo.abastecimentoValor] as num?)?.toDouble(),
      alimentacaoMarmitasQtd: map[DbDiarioDeCampo.alimentacaoMarmitasQtd],
      alimentacaoRefeicaoValor: (map[DbDiarioDeCampo.alimentacaoRefeicaoValor] as num?)?.toDouble(),
      alimentacaoDescricao: map[DbDiarioDeCampo.alimentacaoDescricao],
      outrasDespesasValor: (map[DbDiarioDeCampo.outrasDespesasValor] as num?)?.toDouble(),
      outrasDespesasDescricao: map[DbDiarioDeCampo.outrasDespesasDescricao],
      veiculoPlaca: map[DbDiarioDeCampo.veiculoPlaca],
      veiculoModelo: map[DbDiarioDeCampo.veiculoModelo],
      equipeNoCarro: map[DbDiarioDeCampo.equipeNoCarro],
      lastModified: map[DbDiarioDeCampo.lastModified],
    );
  }
}
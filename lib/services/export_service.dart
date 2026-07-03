// lib/services/export_service.dart (VERSÃO CORRIGIDA PARA FORMATAÇÃO DE NÚMEROS)

import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/utils/constants.dart';
import 'package:geoforestv1/widgets/progress_dialog.dart';
import 'package:provider/provider.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/analise_result_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/services/permission_service.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/providers/team_provider.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/widgets/manager_export_dialog.dart';
import 'package:geoforestv1/models/cubagem_secao_model.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/data/repositories/codigos_repository.dart';

// --- PAYLOADS PARA ISOLATES ---

class _CsvParcelaPayload {
  final List<Map<String, dynamic>> parcelasMap;
  final Map<int, List<Map<String, dynamic>>> arvoresPorParcelaMap;
  final Map<int, Map<String, dynamic>> talhoesMap;
  final String nomeLider;
  final String nomesAjudantes;
  final String nomeZona;
  final Map<int, String> proj4Defs;
  final String nomeEmpresa;
  final Map<String, String> mapaCodigos;
  final Map<String, List<List<dynamic>>> codigosPorTipo;

  _CsvParcelaPayload({
    required this.parcelasMap,
    required this.arvoresPorParcelaMap,
    required this.talhoesMap,
    required this.nomeLider,
    required this.nomesAjudantes,
    required this.nomeZona,
    required this.proj4Defs,
    required this.nomeEmpresa,
    required this.mapaCodigos,
    required this.codigosPorTipo,
  });
}

class _CsvCubagemPayload {
  final List<Map<String, dynamic>> cubagensMap;
  final Map<int, List<Map<String, dynamic>>> secoesPorCubagemMap;
  final Map<int, Map<String, dynamic>> talhoesMap;
  final String nomeLider;
  final String nomesAjudantes;
  final String nomeZona;
  final Map<int, String> proj4Defs;
  final String nomeEmpresa;
  final List<List<dynamic>> classesRows;

  _CsvCubagemPayload({
    required this.cubagensMap,
    required this.secoesPorCubagemMap,
    required this.talhoesMap,
    required this.nomeLider,
    required this.nomesAjudantes,
    required this.nomeZona,
    required this.proj4Defs,
    required this.nomeEmpresa,
    required this.classesRows,
  });
}

class _DevEquipePayload {
  final List<Map<String, dynamic>> coletasData;
  final String nomeZona;
  final Map<int, String> proj4Defs;
  final List<List<dynamic>> resumoProjetoRows;
  final List<List<dynamic>> resumoTalhaoRows;
  final List<List<dynamic>> produtividadeEquipeRows;
  final List<List<dynamic>> qualidadeColetaRows;

  _DevEquipePayload({
    required this.coletasData,
    required this.nomeZona,
    required this.proj4Defs,
    required this.resumoProjetoRows,
    required this.resumoTalhaoRows,
    required this.produtividadeEquipeRows,
    required this.qualidadeColetaRows,
  });
}

// --- ACUMULADORES DE ESTATÍSTICAS (Relatório de Desenvolvimento das Equipes) ---

class _ProjetoStats {
  int parcelasPendentes = 0, parcelasAndamento = 0, parcelasConcluidas = 0, parcelasExportadas = 0;
  int cubagensPendentes = 0, cubagensConcluidas = 0, cubagensExportadas = 0;
  final Set<int> talhaoIds = {};
  final Set<String> fazendas = {};
}

class _TalhaoStats {
  String projetoNome = '';
  String fazendaNome = '';
  String talhaoNome = '';
  double? areaHa;
  String? especie;
  double? idadeAnos;
  int parcelasPendentes = 0, parcelasAndamento = 0, parcelasConcluidas = 0, parcelasExportadas = 0;
  int cubagensPendentes = 0, cubagensConcluidas = 0, cubagensExportadas = 0;
  int totalCovas = 0, totalFustes = 0, totalFalhas = 0, totalCodigosEspeciais = 0;
  int parcelasSemGps = 0, parcelasComObservacao = 0;
  double somaDistanciaPlanejadoReal = 0.0;
  double? distanciaMaximaPlanejadoReal;
  int qtdComDistancia = 0;
  int qtdDesvioAcimaTolerancia = 0;
}

class _EquipeStats {
  int totalParcelas = 0;
  int totalCubagens = 0;
  final Set<String> diasTrabalhados = {};
  DateTime? dataInicio;
  DateTime? dataFim;
}

String _statusLabelParcela(Parcela p) {
  if (p.exportada) return 'Exportada';
  switch (p.status) {
    case StatusParcela.pendente:
      return 'Pendente';
    case StatusParcela.emAndamento:
      return 'Em Andamento';
    case StatusParcela.concluida:
      return 'Concluída';
    case StatusParcela.exportada:
      return 'Exportada';
  }
}

String _statusLabelCubagem(CubagemArvore c) {
  if (c.exportada) return 'Exportada';
  return c.alturaTotal > 0 ? 'Concluída' : 'Pendente';
}

/// Distância em metros entre dois pontos GPS (fórmula de Haversine).
double? _distanciaMetros(double? lat1, double? lon1, double? lat2, double? lon2) {
  if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) return null;
  const raioTerraM = 6371000.0;
  final dLat = (lat2 - lat1) * (math.pi / 180);
  final dLon = (lon2 - lon1) * (math.pi / 180);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) * math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return raioTerraM * c;
}

class _CsvOperacoesPayload {
  final List<Map<String, dynamic>> diariosMap;
  final List<List<dynamic>> resumoKpisRows;
  final List<List<dynamic>> composicaoDespesasRows;
  final List<List<dynamic>> custoPorVeiculoRows;
  final List<List<dynamic>> custoPorEquipeRows;
  _CsvOperacoesPayload({
    required this.diariosMap,
    required this.resumoKpisRows,
    required this.composicaoDespesasRows,
    required this.custoPorVeiculoRows,
    required this.custoPorEquipeRows,
  });
}

class _CsvConsolidadoPayload {
  final Map<String, dynamic> diarioMap;
  final List<Map<String, dynamic>> parcelasMap;
  final List<Map<String, dynamic>> cubagensMap;
  final Map<int, Map<String, dynamic>> projetosMap;
  final Map<int, Map<String, dynamic>> atividadesMap;
  final Map<int, Map<String, dynamic>> talhoesMap;
  final Map<int, int> totaisAmostrasPorTalhao;
  final Map<int, int> totaisCubagensPorTalhao;

  _CsvConsolidadoPayload({
    required this.diarioMap,
    required this.parcelasMap,
    required this.cubagensMap,
    required this.projetosMap,
    required this.atividadesMap,
    required this.talhoesMap,
    required this.totaisAmostrasPorTalhao,
    required this.totaisCubagensPorTalhao,
  });
}

// --- FUNÇÕES DE ISOLATE (GERAÇÃO DE PLANILHA EM BACKGROUND) ---

CellValue? _paraCellValue(dynamic v) {
  if (v == null) return null;
  if (v is int) return IntCellValue(v);
  if (v is double) return DoubleCellValue(v);
  return TextCellValue(v.toString());
}

Future<List<int>> _generateXlsxParcelaBytesInIsolate(_CsvParcelaPayload payload) async {
  proj4.Projection.add('EPSG:4326', '+proj=longlat +datum=WGS84 +no_defs');
  payload.proj4Defs.forEach((epsg, def) {
    proj4.Projection.add('EPSG:$epsg', def);
  });

  final codigoEpsg = zonasUtmSirgas2000[payload.nomeZona] ?? 31982;
  final projWGS84 = proj4.Projection.get('EPSG:4326');
  final projUTM = proj4.Projection.get('EPSG:$codigoEpsg');

  if (projWGS84 == null || projUTM == null) {
    throw StateError('Não foi possível inicializar o sistema de projeção de coordenadas.');
  }

  // Formatadores
  final nf1 = NumberFormat("0.0", "pt_BR");
  final nf2 = NumberFormat("0.00", "pt_BR");
  final df = DateFormat('dd/MM/yyyy'); // Para data igual ao print

  List<List<dynamic>> rows = [];
  
  // 1. CABEÇALHOS REORDENADOS CONFORME SOLICITADO
  rows.add([
    'Atividade',
    'ID_Db_Parcela',
    'Empresa',
    'Codigo_Fazenda',
    'Fazenda',
    'UP',
    'Talhao',
    'Area_Talhao_ha',
    'Especie_Talhao',
    'Espacamento',
    'Idade_Anos',
    'Lider_Equipe',
    'Ajudantes',
    'ID_Coleta_Parcela',
    'Area_Inclinada_m2',
    'Area_Horizontal_m2',
    'Lado1_m',
    'Lado2_m',
    'Declividade_Graus',
    'Easting',
    'Northing',
    'Data_Coleta',
    'Status_Parcela',
    'Linha',
    'Posicao_na_Linha',
    'Fuste_Num',
    'Especie_Individual',
    'Descricao_Codigo_1',
    'Descricao_Codigo_2',
    'CAP_cm',
    'Tipo_Medida_CAP',
    'Suta_Diametro1_cm',
    'Suta_Diametro2_cm',
    'Altura_m',
    'Altura_Dano_m',
    'Dominante',
    'Observacao_Parcela'
  ]);

  String formatValue(double? value, NumberFormat formatter) {
    return value != null ? formatter.format(value) : '';
  }

  String traduzirCodigo(String? sigla) {
    if (sigla == null || sigla.isEmpty) return '';
    // Retorna a descrição (ex: "Normal") ou a sigla original se não achar
    return payload.mapaCodigos[sigla.toUpperCase()] ?? sigla;
  }

  for (var pMap in payload.parcelasMap) {
    final p = Parcela.fromMap(pMap);
    final talhaoData = payload.talhoesMap[p.talhaoId] ?? {};

    String easting = '', northing = '';
    if (p.latitude != null && p.longitude != null) {
      var pUtm = projWGS84.transform(
          projUTM, proj4.Point(x: p.longitude!, y: p.latitude!));
      easting = nf2.format(pUtm.x);
      northing = nf2.format(pUtm.y);
    }

    double areaInclinada = p.areaMetrosQuadrados;
    if (p.declividade != null && p.declividade! > 0) {
      final radianos = p.declividade! * (math.pi / 180.0);
      if (math.cos(radianos) > 0) {
        areaInclinada = p.areaMetrosQuadrados / math.cos(radianos);
      }
    }

    final arvoresMap = payload.arvoresPorParcelaMap[p.dbId] ?? [];
    final arvores = arvoresMap.map((aMap) => Arvore.fromMap(aMap)).toList();
    final liderDaColeta = p.nomeLider ?? payload.nomeLider;
    
    // Formata a data para dd/mm/aaaa
    final dataColetaFormatada = p.dataColeta != null ? df.format(p.dataColeta!) : '';

    if (arvores.isEmpty) {
      // 2. LINHA VAZIA (Sem árvores) - REORDENADA      
      rows.add([
        p.atividadeTipo ?? 'IPC',                   // Atividade
        p.dbId,                                     // ID_Db_Parcela
        payload.nomeEmpresa,                        // Empresa
        p.idFazenda,                                // Codigo_Fazenda
        p.nomeFazenda,                              // Fazenda
        p.up,                                       // UP
        p.nomeTalhao,                               // Talhao
        formatValue(talhaoData['areaHa'], nf2),     // Area_Talhao_ha
        talhaoData['especie'],                      // Especie
        talhaoData['espacamento'],                  // Espacamento
        formatValue(talhaoData['idadeAnos'], nf1),  // Idade_Anos
        liderDaColeta,                              // Lider_Equipe
        payload.nomesAjudantes,                     // Ajudantes
        p.idParcela,                                // ID_Coleta_Parcela
        nf2.format(areaInclinada),                  // Area_Inclinada_m2
        nf2.format(p.areaMetrosQuadrados),          // Area_Horizontal_m2
        formatValue(p.lado1, nf2),                  // Lado1_m
        formatValue(p.lado2, nf2),                  // Lado2_m
        formatValue(p.declividade, nf2),            // Declividade_Graus
        easting,                                    // Easting
        northing,                                   // Northing
        dataColetaFormatada,                        // Data_Coleta
        p.status.name,                              // Status_Parcela
        null, // Linha
        null, // Posicao
        null, // Fuste
        null, // Especie Individual
        null, // Codigo
        null, // Codigo 2
        null, // CAP
        null, // Tipo_Medida_CAP
        null, // Suta_Diametro1_cm
        null, // Suta_Diametro2_cm
        null, // Altura
        null, // Altura Dano
        null, // Dominante
        p.observacao                                // Observacao_Parcela (FINAL)
      ]);
    } else {
      Map<String, int> fusteCounter = {};
      for (final a in arvores) {
        String key = '${a.linha}-${a.posicaoNaLinha}';
        fusteCounter[key] = (fusteCounter[key] ?? 0) + 1;
        
        // 3. LINHA COM ÁRVORE - REORDENADA
        rows.add([
          p.atividadeTipo ?? 'IPC',                   // Atividade
          p.dbId,                                     // ID_Db_Parcela
          payload.nomeEmpresa,                        // Empresa
          p.idFazenda,                                // Codigo_Fazenda
          p.nomeFazenda,                              // Fazenda
          p.up,                                       // UP
          p.nomeTalhao,                               // Talhao
          formatValue(talhaoData['areaHa'], nf2),     // Area_Talhao_ha
          talhaoData['especie'],                      // Especie
          talhaoData['espacamento'],                  // Espacamento
          formatValue(talhaoData['idadeAnos'], nf1),  // Idade_Anos
          liderDaColeta,                              // Lider_Equipe
          payload.nomesAjudantes,                     // Ajudantes
          p.idParcela,                                // ID_Coleta_Parcela
          nf2.format(areaInclinada),                  // Area_Inclinada_m2
          nf2.format(p.areaMetrosQuadrados),          // Area_Horizontal_m2
          formatValue(p.lado1, nf2),                  // Lado1_m
          formatValue(p.lado2, nf2),                  // Lado2_m
          formatValue(p.declividade, nf2),            // Declividade_Graus
          easting,                                    // Easting
          northing,                                   // Northing
          dataColetaFormatada,                        // Data_Coleta
          p.status.name,                              // Status_Parcela
          a.linha,                                    // Linha
          a.posicaoNaLinha,                           // Posicao_na_Linha
          fusteCounter[key],                          // Fuste_Num
          a.especie ?? '',                           // Especie_Individual
          traduzirCodigo(a.codigo),                                   // Codigo_Arvore
          traduzirCodigo(a.codigo2),                            // Codigo_Arvore_2
          formatValue(a.cap, nf1),                    // CAP_cm
          a.tipoMedidaCAP,                            // Tipo_Medida_CAP
          formatValue(a.medidaSuta1, nf1),            // Suta_Diametro1_cm
          formatValue(a.medidaSuta2, nf1),            // Suta_Diametro2_cm
          formatValue(a.altura, nf1),                 // Altura_m
          formatValue(a.alturaDano, nf1),             // Altura_Dano_m
          a.dominante ? 'Sim' : 'Não',                // Dominante
          p.observacao ?? ''                          // Observacao_Parcela (FINAL)
        ]);
      }
    }
  }

  final excelFile = Excel.createExcel();
  const sheetDados = 'Dados';
  final sheetPadrao = excelFile.getDefaultSheet();

  for (final row in rows) {
    excelFile.appendRow(sheetDados, row.map(_paraCellValue).toList());
  }

  // Uma aba de legenda de códigos por tipo de atividade presente (ex: IPC, IFC)
  payload.codigosPorTipo.forEach((tipo, linhas) {
    final nomeAba = 'Codigos_$tipo';
    for (final row in linhas) {
      excelFile.appendRow(nomeAba, row.map(_paraCellValue).toList());
    }
  });

  // Remove a aba padrão vazia criada por Excel.createExcel()
  if (sheetPadrao != null && sheetPadrao != sheetDados) {
    excelFile.delete(sheetPadrao);
  }
  excelFile.setDefaultSheet(sheetDados);

  return excelFile.save() ?? <int>[];
}

Future<List<int>> _generateXlsxCubagemBytesInIsolate(_CsvCubagemPayload payload) async {
  proj4.Projection.add('EPSG:4326', '+proj=longlat +datum=WGS84 +no_defs');
  payload.proj4Defs.forEach((epsg, def) {
    proj4.Projection.add('EPSG:$epsg', def);
  });

  final codigoEpsg = zonasUtmSirgas2000[payload.nomeZona] ?? 31982;
  final projWGS84 = proj4.Projection.get('EPSG:4326');
  final projUTM = proj4.Projection.get('EPSG:$codigoEpsg');

  if (projWGS84 == null || projUTM == null) {
    throw StateError('Não foi possível inicializar o sistema de projeção de coordenadas.');
  }

  final nf1 = NumberFormat("0.0", "pt_BR");
  final nf2 = NumberFormat("0.00", "pt_BR");

  List<List<dynamic>> rows = [];
  rows.add([
    'Empresa', 'Atividade', 'Lider_Equipe', 'Ajudantes', 'id_db_arvore', 'id_fazenda',
    'fazenda', 'UP', 'talhao', 'area_talhao_ha', 'especie', 'espacamento', 'idade_anos',
    'identificador_arvore', 'classe', 'altura_total_m', 'tipo_medida_cap', 'valor_cap',
    'altura_base_m', 'Data_Coleta', 'Easting_Cubagem', 'Northing_Cubagem', 'Observacao_Cubagem',
    'altura_medicao_secao_m', 'circunferencia_secao_cm', 'casca1_mm', 'casca2_mm', 'dsc_cm'
  ]);

  String formatValue(double? value, NumberFormat formatter) {
    return value != null ? formatter.format(value) : '';
  }

  for (var cMap in payload.cubagensMap) {
    final arvore = CubagemArvore.fromMap(cMap);
    final talhaoData = payload.talhoesMap[arvore.talhaoId] ?? {};
    final rf = talhaoData['up'] ?? 'N/A';
    
    String easting = '', northing = '';
    if (arvore.latitude != null && arvore.longitude != null) {
      var pUtm = projWGS84.transform(
          projUTM, proj4.Point(x: arvore.longitude!, y: arvore.latitude!));
      easting = nf2.format(pUtm.x);
      northing = nf2.format(pUtm.y);
    }

    final secoesMap = payload.secoesPorCubagemMap[arvore.id] ?? [];
    final secoes = secoesMap.map((sMap) => CubagemSecao.fromMap(sMap)).toList();
    final liderDaColeta = arvore.nomeLider ?? payload.nomeLider;
    final dataColetaFormatada = arvore.dataColeta != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(arvore.dataColeta!)
        : '';

    if (secoes.isEmpty) {
      rows.add([
        payload.nomeEmpresa, 'CUB', liderDaColeta, payload.nomesAjudantes, arvore.id,
        arvore.idFazenda, arvore.nomeFazenda, rf, arvore.nomeTalhao,
        formatValue(talhaoData['areaHa'], nf2), talhaoData['especie'], talhaoData['espacamento'],
        formatValue(talhaoData['idadeAnos'], nf1), arvore.identificador, arvore.classe,
        formatValue(arvore.alturaTotal, nf2), arvore.tipoMedidaCAP, formatValue(arvore.valorCAP, nf2),
        formatValue(arvore.alturaBase, nf2), dataColetaFormatada, easting, northing,
        arvore.observacao, null, null, null, null, null
      ]);
    } else {
      for (var secao in secoes) {
        rows.add([
          payload.nomeEmpresa, 'CUB', liderDaColeta, payload.nomesAjudantes, arvore.id,
          arvore.idFazenda, arvore.nomeFazenda, rf, arvore.nomeTalhao,
          formatValue(talhaoData['areaHa'], nf2), talhaoData['especie'], talhaoData['espacamento'],
          formatValue(talhaoData['idadeAnos'], nf1), arvore.identificador, arvore.classe,
          formatValue(arvore.alturaTotal, nf2), arvore.tipoMedidaCAP, formatValue(arvore.valorCAP, nf2),
          formatValue(arvore.alturaBase, nf2), dataColetaFormatada, easting, northing,
          arvore.observacao, formatValue(secao.alturaMedicao, nf2), formatValue(secao.circunferencia, nf2),
          formatValue(secao.casca1_mm, nf2), formatValue(secao.casca2_mm, nf2), nf2.format(secao.diametroSemCasca)
        ]);
      }
    }
  }

  final excelFile = Excel.createExcel();
  const sheetDados = 'Dados';
  const sheetClasses = 'Classes';
  final sheetPadrao = excelFile.getDefaultSheet();

  for (final row in rows) {
    excelFile.appendRow(sheetDados, row.map(_paraCellValue).toList());
  }

  // Aba com a quantidade de árvores planejadas x realizadas por classe diamétrica
  for (final row in payload.classesRows) {
    excelFile.appendRow(sheetClasses, row.map(_paraCellValue).toList());
  }

  // Remove a aba padrão vazia criada por Excel.createExcel()
  if (sheetPadrao != null && sheetPadrao != sheetDados) {
    excelFile.delete(sheetPadrao);
  }
  excelFile.setDefaultSheet(sheetDados);

  return excelFile.save() ?? <int>[];
}

Future<List<int>> _generateXlsxDevEquipeBytesInIsolate(_DevEquipePayload payload) async {
  proj4.Projection.add('EPSG:4326', '+proj=longlat +datum=WGS84 +no_defs');
  payload.proj4Defs.forEach((epsg, def) {
    proj4.Projection.add('EPSG:$epsg', def);
  });

  final codigoEpsg = zonasUtmSirgas2000[payload.nomeZona] ?? 31982;
  final projWGS84 = proj4.Projection.get('EPSG:4326');
  final projUTM = proj4.Projection.get('EPSG:$codigoEpsg');

  if (projWGS84 == null || projUTM == null) {
    throw StateError('Não foi possível inicializar o sistema de projeção de coordenadas.');
  }

  final nf2 = NumberFormat("0.00", "pt_BR");

  List<List<dynamic>> rows = [];
  rows.add([
    'Projeto', 'Atividade', 'Fazenda', 'Talhao', 'ID_Amostra_Coleta', 'Area_Talhao_ha',
    'Situacao', 'Data_Alteracao', 'Responsavel', 'Coord_X_UTM', 'Coord_Y_UTM',
    'Area_Parcela_m2', 'Lado1_m', 'Lado2_m', 'Observacao_Parcela', 'Total_Fustes',
    'Total_Covas', 'Total_Falhas', 'Total_Codigos_Especiais', 'Classe Arvore - Cubagem',
    'CAP Arvore - Cubagem', 'Altura Cubagem', 'Distancia_Planejado_Real_m'
  ]);

  for (final rowData in payload.coletasData) {
    String easting = '', northing = '';
    final lat = rowData['latitude'] as double?;
    final lon = rowData['longitude'] as double?;
    if (lat != null && lon != null) {
      var pUtm = projWGS84.transform(projUTM, proj4.Point(x: lon, y: lat));
      easting = nf2.format(pUtm.x);
      northing = nf2.format(pUtm.y);
    }

    String formatValue(dynamic value, NumberFormat formatter) {
      if (value == null) return '';
      if (value is double) return formatter.format(value);
      return value.toString();
    }

    rows.add([
      rowData['projeto_nome'], rowData['atividade_tipo'], rowData['fazenda_nome'], rowData['talhao_nome'],
      rowData['id_coleta'], formatValue(rowData['talhao_area_ha'], nf2), rowData['situacao'],
      rowData['data_alteracao'], rowData['responsavel'], easting, northing,
      formatValue(rowData['parcela_area_m2'], nf2), formatValue(rowData['parcela_lado1_m'], nf2),
      formatValue(rowData['parcela_lado2_m'], nf2), rowData['parcela_observacao'], rowData['total_fustes'],
      rowData['total_covas'], rowData['total_falhas'], rowData['total_codigos_especiais'],
      rowData['cubagem_classe'], formatValue(rowData['cubagem_cap'], nf2), formatValue(rowData['cubagem_altura'], nf2),
      formatValue(rowData['distancia_planejado_real_m'], nf2),
    ]);
  }

  final excelFile = Excel.createExcel();
  const sheetDados = 'Dados';
  const sheetResumoProjeto = 'Resumo_Projeto';
  const sheetResumoTalhao = 'Resumo_Talhao';
  const sheetProdutividade = 'Produtividade_Equipe';
  const sheetQualidade = 'Qualidade_Coleta';
  final sheetPadrao = excelFile.getDefaultSheet();

  for (final row in rows) {
    excelFile.appendRow(sheetDados, row.map(_paraCellValue).toList());
  }
  for (final row in payload.resumoProjetoRows) {
    excelFile.appendRow(sheetResumoProjeto, row.map(_paraCellValue).toList());
  }
  for (final row in payload.resumoTalhaoRows) {
    excelFile.appendRow(sheetResumoTalhao, row.map(_paraCellValue).toList());
  }
  for (final row in payload.produtividadeEquipeRows) {
    excelFile.appendRow(sheetProdutividade, row.map(_paraCellValue).toList());
  }
  for (final row in payload.qualidadeColetaRows) {
    excelFile.appendRow(sheetQualidade, row.map(_paraCellValue).toList());
  }

  if (sheetPadrao != null && sheetPadrao != sheetDados) {
    excelFile.delete(sheetPadrao);
  }
  excelFile.setDefaultSheet(sheetDados);

  return excelFile.save() ?? <int>[];
}

Future<List<int>> _generateXlsxOperacoesBytesInIsolate(_CsvOperacoesPayload payload) async {
  final List<List<dynamic>> rows = [];
  final nf = NumberFormat("#,##0.00", "pt_BR");
  final nfKm = NumberFormat("#,##0.0", "pt_BR");

  rows.add([
    'Data', 'Líder', 'Equipe', 'Veículo (Placa)', 'KM Rodados', 'Custo Abastecimento (R\$)',
    'Custo Alimentação (R\$)', 'Custo Pedágio (R\$)', 'Outros Gastos (R\$)',
    'Descrição Outros Gastos', 'Custo Total (R\$)', 'Destino'
  ]);

  String formatValue(dynamic value) {
    if (value == null) return '';
    if (value is double) return nf.format(value);
    return value.toString();
  }
  String formatKm(dynamic value) {
    if (value == null || value <= 0) return '0,0';
    return nfKm.format(value);
  }

  for (final diarioMap in payload.diariosMap) {
    final d = DiarioDeCampo.fromMap(diarioMap);
    final distancia = (d.kmFinal ?? 0) - (d.kmInicial ?? 0);
    final custoTotal = (d.abastecimentoValor ?? 0) + (d.pedagioValor ?? 0) +
                       (d.alimentacaoRefeicaoValor ?? 0) + (d.outrasDespesasValor ?? 0);

    rows.add([
      DateFormat('dd/MM/yyyy').format(DateTime.parse(d.dataRelatorio)),
      d.nomeLider, d.equipeNoCarro, d.veiculoPlaca, formatKm(distancia),
      formatValue(d.abastecimentoValor), formatValue(d.alimentacaoRefeicaoValor),
      formatValue(d.pedagioValor), formatValue(d.outrasDespesasValor),
      d.outrasDespesasDescricao, formatValue(custoTotal), d.localizacaoDestino
    ]);
  }

  final excelFile = Excel.createExcel();
  const sheetDados = 'Dados';
  const sheetKpis = 'Resumo_KPIs';
  const sheetComposicao = 'Composicao_Despesas';
  const sheetVeiculo = 'Custo_Por_Veiculo';
  const sheetEquipe = 'Custo_Por_Equipe';
  final sheetPadrao = excelFile.getDefaultSheet();

  for (final row in rows) {
    excelFile.appendRow(sheetDados, row.map(_paraCellValue).toList());
  }
  for (final row in payload.resumoKpisRows) {
    excelFile.appendRow(sheetKpis, row.map(_paraCellValue).toList());
  }
  for (final row in payload.composicaoDespesasRows) {
    excelFile.appendRow(sheetComposicao, row.map(_paraCellValue).toList());
  }
  for (final row in payload.custoPorVeiculoRows) {
    excelFile.appendRow(sheetVeiculo, row.map(_paraCellValue).toList());
  }
  for (final row in payload.custoPorEquipeRows) {
    excelFile.appendRow(sheetEquipe, row.map(_paraCellValue).toList());
  }

  if (sheetPadrao != null && sheetPadrao != sheetDados) {
    excelFile.delete(sheetPadrao);
  }
  excelFile.setDefaultSheet(sheetDados);

  return excelFile.save() ?? <int>[];
}

Future<List<int>> _generateXlsxConsolidadoBytesInIsolate(_CsvConsolidadoPayload payload) async {
  List<List<dynamic>> rows = [];
  final nf = NumberFormat("#,##0.00", "pt_BR");
  final nfKm = NumberFormat("#,##0.0", "pt_BR");

  rows.add([
    'Data_Relatorio', 'Lider_Equipe', 'Ajudantes', 'Projeto', 'Atividade', 'Fazenda', 'Talhao',
    'Tipo_Coleta', 'ID_Amostra', 'Indicador_Amostra', 'Total_Amostras', 'Indicador_Cubagem',
    'Total_Cubagens', 'Status_Coleta', 'UP_RF', 'KM_Inicial', 'KM_Final', 'Total_KM', 'Destino',
    'Pedagio_RS', 'Abastecimento_RS', 'Qtd_Marmitas', 'Refeicao_RS', 'Total_Gastos',
    'Descricao_Alimentacao', 'Placa_Veiculo', 'Modelo_Veiculo'
  ]);

  final diario = DiarioDeCampo.fromMap(payload.diarioMap);
  final projetos = payload.projetosMap.map((k, v) => MapEntry(k, Projeto.fromMap(v)));
  final atividades = payload.atividadesMap.map((k, v) => MapEntry(k, Atividade.fromMap(v)));
  final talhoes = payload.talhoesMap.map((k, v) => MapEntry(k, Talhao.fromMap(v)));

  String formatValue(dynamic value) {
    if (value == null) return '';
    if (value is double) return nf.format(value);
    return value.toString();
  }
  String formatKm(dynamic value) {
    if (value == null || value <= 0) return '0,0';
    return nfKm.format(value);
  }

  final distancia = (diario.kmFinal ?? 0) - (diario.kmInicial ?? 0);
  final totalGastos = (diario.abastecimentoValor ?? 0) + (diario.pedagioValor ?? 0) + (diario.alimentacaoRefeicaoValor ?? 0);

  final projetoDoDiario = projetos[diario.projetoId];
  final talhaoDoDiario = diario.talhaoId != null ? talhoes[diario.talhaoId] : null;
  final custoTotalDiario = (diario.abastecimentoValor ?? 0) + (diario.pedagioValor ?? 0) +
      (diario.alimentacaoRefeicaoValor ?? 0) + (diario.outrasDespesasValor ?? 0);

  final List<List<dynamic>> resumoDiarioRows = [
    ['Campo', 'Valor'],
    ['Data do Relatório', DateFormat('dd/MM/yyyy').format(DateTime.parse(diario.dataRelatorio))],
    ['Líder da Equipe', diario.nomeLider],
    ['Equipe Completa', diario.equipeNoCarro],
    ['Projeto (Referência)', projetoDoDiario?.nome ?? 'N/A'],
    ['Fazenda (Referência)', talhaoDoDiario?.fazendaNome ?? 'N/A'],
    ['Talhão (Referência)', talhaoDoDiario?.nome ?? 'N/A'],
    ['Placa do Veículo', diario.veiculoPlaca],
    ['Modelo do Veículo', diario.veiculoModelo],
    ['KM Inicial', formatValue(diario.kmInicial)],
    ['KM Final', formatValue(diario.kmFinal)],
    ['Total KM Rodados', formatKm(distancia)],
    ['Destino', diario.localizacaoDestino],
    ['Pedágio (R\$)', formatValue(diario.pedagioValor)],
    ['Abastecimento (R\$)', formatValue(diario.abastecimentoValor)],
    ['Qtd. Marmitas', diario.alimentacaoMarmitasQtd],
    ['Valor Refeição (R\$)', formatValue(diario.alimentacaoRefeicaoValor)],
    ['Descrição Alimentação', diario.alimentacaoDescricao],
    ['Outras Despesas (R\$)', formatValue(diario.outrasDespesasValor)],
    ['Descrição Outras Despesas', diario.outrasDespesasDescricao],
    ['Custo Total do Dia (R\$)', formatValue(custoTotalDiario)],
  ];

  for (var pMap in payload.parcelasMap) {
    final p = Parcela.fromMap(pMap);
    final talhao = talhoes[p.talhaoId];
    final atividade = atividades[talhao?.fazendaAtividadeId];
    final projeto = projetos[atividade?.projetoId];
    final totaisAmostras = payload.totaisAmostrasPorTalhao[p.talhaoId] ?? 0;
    final totaisCubagens = payload.totaisCubagensPorTalhao[p.talhaoId] ?? 0;

    rows.add([
      DateFormat('dd/MM/yyyy').format(DateTime.parse(diario.dataRelatorio)), diario.nomeLider,
      diario.equipeNoCarro, projeto?.nome, atividade?.tipo, p.nomeFazenda, p.nomeTalhao,
      'Inventario', p.idParcela, 1, totaisAmostras, 0, totaisCubagens, p.status.name, p.up,
      formatValue(diario.kmInicial), formatValue(diario.kmFinal), formatKm(distancia),
      diario.localizacaoDestino, formatValue(diario.pedagioValor), formatValue(diario.abastecimentoValor),
      diario.alimentacaoMarmitasQtd, formatValue(diario.alimentacaoRefeicaoValor), formatValue(totalGastos),
      diario.alimentacaoDescricao, diario.veiculoPlaca, diario.veiculoModelo
    ]);
  }

  for (var cMap in payload.cubagensMap) {
    final c = CubagemArvore.fromMap(cMap);
    final talhao = talhoes[c.talhaoId];
    final atividade = atividades[talhao?.fazendaAtividadeId];
    final projeto = projetos[atividade?.projetoId];
    final totaisAmostras = payload.totaisAmostrasPorTalhao[c.talhaoId] ?? 0;
    final totaisCubagens = payload.totaisCubagensPorTalhao[c.talhaoId] ?? 0;

    rows.add([
      DateFormat('dd/MM/yyyy').format(DateTime.parse(diario.dataRelatorio)), diario.nomeLider,
      diario.equipeNoCarro, projeto?.nome, atividade?.tipo, c.nomeFazenda, c.nomeTalhao,
      'Cubagem', c.identificador, 0, totaisAmostras, 1, totaisCubagens,
      c.alturaTotal > 0 ? 'concluida' : 'pendente', c.rf,
      formatValue(diario.kmInicial), formatValue(diario.kmFinal), formatKm(distancia),
      diario.localizacaoDestino, formatValue(diario.pedagioValor), formatValue(diario.abastecimentoValor),
      diario.alimentacaoMarmitasQtd, formatValue(diario.alimentacaoRefeicaoValor), formatValue(totalGastos),
      diario.alimentacaoDescricao, diario.veiculoPlaca, diario.veiculoModelo
    ]);
  }

  final excelFile = Excel.createExcel();
  const sheetDados = 'Dados';
  const sheetResumoDiario = 'Resumo_Diario';
  final sheetPadrao = excelFile.getDefaultSheet();

  for (final row in rows) {
    excelFile.appendRow(sheetDados, row.map(_paraCellValue).toList());
  }
  for (final row in resumoDiarioRows) {
    excelFile.appendRow(sheetResumoDiario, row.map(_paraCellValue).toList());
  }

  if (sheetPadrao != null && sheetPadrao != sheetDados) {
    excelFile.delete(sheetPadrao);
  }
  excelFile.setDefaultSheet(sheetDados);

  return excelFile.save() ?? <int>[];
}

class ExportService {
  final _parcelaRepository = ParcelaRepository();
  final _cubagemRepository = CubagemRepository();
  final _projetoRepository = ProjetoRepository();
  final _atividadeRepository = AtividadeRepository();
  final _talhaoRepository = TalhaoRepository();

  Future<void> exportarRelatorioDiarioConsolidadoCsv({
    required BuildContext context,
    required DiarioDeCampo diario,
    required List<Parcela> parcelas,
    required List<CubagemArvore> cubagens,
  }) async {
    try {
      if (!await _requestPermission(context)) return;
      ProgressDialog.show(context, 'Gerando CSV consolidado...');

      final Set<int> talhaoIds = {...parcelas.map((p) => p.talhaoId), ...cubagens.map((c) => c.talhaoId)}.whereType<int>().toSet();
      final talhoes = (await Future.wait(talhaoIds.map((id) => _talhaoRepository.getTalhaoById(id)))).whereType<Talhao>().toList();
      final talhoesMap = {for (var t in talhoes) t.id!: t.toMap()};

      final Set<int> atividadeIds = talhoes.map((t) => t.fazendaAtividadeId).toSet();
      final atividades = (await _atividadeRepository.getTodasAsAtividades()).where((a) => atividadeIds.contains(a.id)).toList();
      final atividadesMap = {for (var a in atividades) a.id!: a.toMap()};

      final Set<int> projetoIds = atividades.map((a) => a.projetoId).toSet();
      final projetos = (await _projetoRepository.getTodosOsProjetosParaGerente()).where((p) => projetoIds.contains(p.id)).toList();
      final projetosMap = {for (var p in projetos) p.id!: p.toMap()};

      final Map<int, int> totaisAmostrasPorTalhao = {};
      final Map<int, int> totaisCubagensPorTalhao = {};
      final todosTalhoesTrabalhados = {...parcelas.map((p) => p.talhaoId), ...cubagens.map((c) => c.talhaoId)}.whereType<int>();

      for (final talhaoId in todosTalhoesTrabalhados) {
        if (!totaisAmostrasPorTalhao.containsKey(talhaoId)) {
          final todasAsParcelasDoTalhao = await _parcelaRepository.getParcelasDoTalhao(talhaoId);
          totaisAmostrasPorTalhao[talhaoId] = todasAsParcelasDoTalhao.length;
        }
        if (!totaisCubagensPorTalhao.containsKey(talhaoId)) {
          final todasAsCubagensDoTalhao = await _cubagemRepository.getTodasCubagensDoTalhao(talhaoId);
          totaisCubagensPorTalhao[talhaoId] = todasAsCubagensDoTalhao.length;
        }
      }

      final payload = _CsvConsolidadoPayload(
        diarioMap: diario.toMap(),
        parcelasMap: parcelas.map((p) => p.toMap()).toList(),
        cubagensMap: cubagens.map((c) => c.toMap()).toList(),
        projetosMap: projetosMap, atividadesMap: atividadesMap, talhoesMap: talhoesMap,
        totaisAmostrasPorTalhao: totaisAmostrasPorTalhao, totaisCubagensPorTalhao: totaisCubagensPorTalhao,
      );

      final List<int> xlsxBytes = await compute(_generateXlsxConsolidadoBytesInIsolate, payload);
      final nomeLiderFmt = diario.nomeLider.replaceAll(RegExp(r'\s+'), '_');
      final dataFmt = diario.dataRelatorio;
      final fName = 'relatorio_consolidado_${nomeLiderFmt}_${dataFmt}.xlsx';

      final path = await _salvarBytesEObterCaminho(xlsxBytes, fName);
      if (context.mounted) {
        await Share.shareXFiles([XFile(path)], subject: 'Relatório Consolidado - GeoForest');
      }
    } catch (e, s) {
      _handleExportError(context, 'exportar relatório consolidado', e, s);
    } finally {
      if (context.mounted) ProgressDialog.hide(context);
    }
  }

  Future<void> exportarOperacoesCsv({
    required BuildContext context,
    required List<DiarioDeCampo> diarios,
    required String tipoRelatorio,
  }) async {
    if (diarios.isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum dado de diário para exportar.'), backgroundColor: Colors.orange));
      return;
    }
    try {
      if (!await _requestPermission(context)) return;
      ProgressDialog.show(context, 'Gerando planilha de Operações...');

      final nf2 = NumberFormat("#,##0.00", "pt_BR");
      final nfKm = NumberFormat("#,##0.0", "pt_BR");

      double totalAbastecimento = 0, totalPedagio = 0, totalAlimentacao = 0, totalOutros = 0, kmTotal = 0;
      for (final d in diarios) {
        totalAbastecimento += d.abastecimentoValor ?? 0;
        totalPedagio += d.pedagioValor ?? 0;
        totalAlimentacao += d.alimentacaoRefeicaoValor ?? 0;
        totalOutros += d.outrasDespesasValor ?? 0;
        if (d.kmFinal != null && d.kmInicial != null && d.kmFinal! > d.kmInicial!) {
          kmTotal += (d.kmFinal! - d.kmInicial!);
        }
      }
      final custoTotalGeral = totalAbastecimento + totalPedagio + totalAlimentacao + totalOutros;
      final custoMedioPorKm = kmTotal > 0 ? totalAbastecimento / kmTotal : 0.0;
      final custoMedioDiario = diarios.isNotEmpty ? custoTotalGeral / diarios.length : 0.0;

      final resumoKpisRows = <List<dynamic>>[
        ['Métrica', 'Valor'],
        ['Total de Diários', diarios.length],
        ['KM Total Rodado', nfKm.format(kmTotal)],
        ['Custo Total Abastecimento (R\$)', nf2.format(totalAbastecimento)],
        ['Custo Total Pedágio (R\$)', nf2.format(totalPedagio)],
        ['Custo Total Alimentação (R\$)', nf2.format(totalAlimentacao)],
        ['Custo Total Outros (R\$)', nf2.format(totalOutros)],
        ['Custo Total Geral (R\$)', nf2.format(custoTotalGeral)],
        ['Custo Médio por KM (R\$)', nf2.format(custoMedioPorKm)],
        ['Custo Médio Diário (R\$)', nf2.format(custoMedioDiario)],
      ];

      final composicaoDespesasRows = <List<dynamic>>[
        ['Categoria', 'Valor (R\$)', '% do Total'],
      ];
      final categorias = {
        'Abastecimento': totalAbastecimento, 'Alimentação': totalAlimentacao,
        'Pedágio': totalPedagio, 'Outros': totalOutros,
      };
      categorias.forEach((categoria, valor) {
        final pct = custoTotalGeral > 0 ? valor / custoTotalGeral * 100 : 0.0;
        composicaoDespesasRows.add([categoria, nf2.format(valor), '${nfKm.format(pct)}%']);
      });

      final custoPorVeiculoRows = <List<dynamic>>[
        ['Placa', 'KM Rodado', 'Custo Abastecimento (R\$)', 'Custo Médio por KM (R\$)'],
      ];
      final porPlaca = <String, List<DiarioDeCampo>>{};
      for (final d in diarios) {
        final placa = d.veiculoPlaca;
        if (placa == null || placa.isEmpty) continue;
        porPlaca.putIfAbsent(placa, () => []).add(d);
      }
      porPlaca.forEach((placa, lista) {
        final kmPlaca = lista.fold(0.0, (prev, d) => prev + ((d.kmFinal != null && d.kmInicial != null && d.kmFinal! > d.kmInicial!) ? (d.kmFinal! - d.kmInicial!) : 0.0));
        final custoAbastecimentoPlaca = lista.fold(0.0, (prev, d) => prev + (d.abastecimentoValor ?? 0));
        final custoMedioPlaca = kmPlaca > 0 ? custoAbastecimentoPlaca / kmPlaca : 0.0;
        custoPorVeiculoRows.add([placa, nfKm.format(kmPlaca), nf2.format(custoAbastecimentoPlaca), nf2.format(custoMedioPlaca)]);
      });

      final custoPorEquipeRows = <List<dynamic>>[
        ['Líder/Equipe', 'Dias com Diário', 'KM Total', 'Custo Total (R\$)', 'Custo Médio por KM (R\$)'],
      ];
      final porLider = <String, List<DiarioDeCampo>>{};
      for (final d in diarios) {
        final lider = d.nomeLider.isEmpty ? 'Não informado' : d.nomeLider;
        porLider.putIfAbsent(lider, () => []).add(d);
      }
      porLider.forEach((lider, lista) {
        final kmLider = lista.fold(0.0, (prev, d) => prev + ((d.kmFinal != null && d.kmInicial != null && d.kmFinal! > d.kmInicial!) ? (d.kmFinal! - d.kmInicial!) : 0.0));
        final custoLider = lista.fold(0.0, (prev, d) => prev + (d.abastecimentoValor ?? 0) + (d.pedagioValor ?? 0) + (d.alimentacaoRefeicaoValor ?? 0) + (d.outrasDespesasValor ?? 0));
        final custoMedioKmLider = kmLider > 0 ? custoLider / kmLider : 0.0;
        custoPorEquipeRows.add([lider, lista.length, nfKm.format(kmLider), nf2.format(custoLider), nf2.format(custoMedioKmLider)]);
      });

      final payload = _CsvOperacoesPayload(
        diariosMap: diarios.map((d) => d.toMap()).toList(),
        resumoKpisRows: resumoKpisRows,
        composicaoDespesasRows: composicaoDespesasRows,
        custoPorVeiculoRows: custoPorVeiculoRows,
        custoPorEquipeRows: custoPorEquipeRows,
      );
      final List<int> xlsxBytes = await compute(_generateXlsxOperacoesBytesInIsolate, payload);
      final dataFmt = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final fName = 'relatorio_operacoes_${tipoRelatorio}_${dataFmt}.xlsx';
      final path = await _salvarBytesEObterCaminho(xlsxBytes, fName);
      if (context.mounted) {
        await Share.shareXFiles([XFile(path)], subject: 'Relatório de Operações - GeoForest');
      }
    } catch (e, s) {
      _handleExportError(context, 'exportar relatório de operações', e, s);
    } finally {
      if (context.mounted) ProgressDialog.hide(context);
    }
  }

  Future<void> exportarDesenvolvimentoEquipes(BuildContext context, {Set<int>? projetoIdsFiltrados}) async {
    try {
      if (!await _requestPermission(context)) return;
      ProgressDialog.show(context, 'Gerando relatório detalhado...');

      final todosProjetos = await _projetoRepository.getTodosOsProjetosParaGerente();
      final projetos = (projetoIdsFiltrados == null || projetoIdsFiltrados.isEmpty)
          ? todosProjetos : todosProjetos.where((p) => projetoIdsFiltrados.contains(p.id!)).toList();

      if (projetos.isEmpty) {
        ProgressDialog.hide(context);
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum projeto encontrado para o filtro selecionado.'), backgroundColor: Colors.orange));
        return;
      }

      final projetosMap = {for (var p in projetos) p.id: p};
      final Set<int> idsProjetosFiltrados = projetos.map((p) => p.id!).toSet();
      final todasAtividades = await _atividadeRepository.getTodasAsAtividades();
      final atividades = todasAtividades.where((a) => idsProjetosFiltrados.contains(a.projetoId)).toList();
      final atividadesMap = {for (var a in atividades) a.id: a};
      final todosTalhoes = await _talhaoRepository.getTodosOsTalhoes();
      final talhoes = todosTalhoes.where((t) => atividadesMap.containsKey(t.fazendaAtividadeId)).toList();
      final talhoesMap = {for (var t in talhoes) t.id: t};

      final List<Map<String, dynamic>> allColetasData = [];
      final Map<String, _ProjetoStats> projetoStatsMap = {};
      final Map<int, _TalhaoStats> talhaoStatsMap = {};
      final Map<String, _EquipeStats> equipeStatsMap = {};

      final todasAsParcelas = await _parcelaRepository.getTodasAsParcelas();
      final parcelasFiltradas = todasAsParcelas.where((p) => talhoesMap.containsKey(p.talhaoId));

      for (final parcela in parcelasFiltradas) {
        if (parcela.talhaoId == null) continue;
        final talhao = talhoesMap[parcela.talhaoId]; if (talhao == null) continue;
        final atividade = atividadesMap[talhao.fazendaAtividadeId]; if (atividade == null) continue;
        final projeto = projetosMap[atividade.projetoId]; if (projeto == null) continue;
        final arvores = await _parcelaRepository.getArvoresDaParcela(parcela.dbId!);
        final covas = <String>{}; for (var a in arvores) { covas.add('${a.linha}-${a.posicaoNaLinha}'); }
        final fustes = arvores.where((a) => a.codigo != "F" && a.codigo != "CA").length;
        final falhas = arvores.where((a) => a.codigo == "F").length;
        final codigosEspeciais = arvores.where((a) => a.codigo != "N" && a.codigo != "F" && a.codigo != "CA").length;
        final statusLabel = _statusLabelParcela(parcela);
        final distanciaPlanejadoReal = _distanciaMetros(
          parcela.latitudePlanejada, parcela.longitudePlanejada, parcela.latitude, parcela.longitude);

        allColetasData.add({
          'projeto_nome': projeto.nome, 'atividade_tipo': atividade.tipo, 'fazenda_nome': parcela.nomeFazenda,
          'talhao_nome': parcela.nomeTalhao, 'id_coleta': parcela.idParcela, 'talhao_area_ha': talhao.areaHa,
          'situacao': statusLabel,
          'data_alteracao': parcela.dataColeta?.toIso8601String(), 'responsavel': parcela.nomeLider,
          'latitude': parcela.latitude, 'longitude': parcela.longitude, 'parcela_area_m2': parcela.areaMetrosQuadrados,
          'parcela_lado1_m': parcela.lado1, 'parcela_lado2_m': parcela.lado2, 'parcela_observacao': parcela.observacao,
          'total_fustes': fustes, 'total_covas': covas.length, 'total_falhas': falhas, 'total_codigos_especiais': codigosEspeciais,
          'cubagem_classe': null, 'cubagem_cap': null, 'cubagem_altura': null,
          'distancia_planejado_real_m': distanciaPlanejadoReal,
        });

        final pStats = projetoStatsMap.putIfAbsent(projeto.nome, () => _ProjetoStats());
        if (talhao.id != null) pStats.talhaoIds.add(talhao.id!);
        if (parcela.nomeFazenda != null) pStats.fazendas.add(parcela.nomeFazenda!);

        final tStats = talhaoStatsMap.putIfAbsent(talhao.id!, () => _TalhaoStats()
          ..projetoNome = projeto.nome
          ..fazendaNome = parcela.nomeFazenda ?? ''
          ..talhaoNome = talhao.nome
          ..areaHa = talhao.areaHa
          ..especie = talhao.especie
          ..idadeAnos = talhao.idadeAnos);

        switch (statusLabel) {
          case 'Pendente': pStats.parcelasPendentes++; tStats.parcelasPendentes++; break;
          case 'Em Andamento': pStats.parcelasAndamento++; tStats.parcelasAndamento++; break;
          case 'Concluída': pStats.parcelasConcluidas++; tStats.parcelasConcluidas++; break;
          case 'Exportada': pStats.parcelasExportadas++; tStats.parcelasExportadas++; break;
        }

        tStats.totalCovas += covas.length;
        tStats.totalFustes += fustes;
        tStats.totalFalhas += falhas;
        tStats.totalCodigosEspeciais += codigosEspeciais;
        if (parcela.latitude == null || parcela.longitude == null) tStats.parcelasSemGps++;
        if (parcela.observacao != null && parcela.observacao!.trim().isNotEmpty) tStats.parcelasComObservacao++;
        if (distanciaPlanejadoReal != null) {
          tStats.somaDistanciaPlanejadoReal += distanciaPlanejadoReal;
          tStats.qtdComDistancia++;
          if (tStats.distanciaMaximaPlanejadoReal == null || distanciaPlanejadoReal > tStats.distanciaMaximaPlanejadoReal!) {
            tStats.distanciaMaximaPlanejadoReal = distanciaPlanejadoReal;
          }
          if (distanciaPlanejadoReal > 30) tStats.qtdDesvioAcimaTolerancia++;
        }

        final liderNome = parcela.nomeLider ?? 'Não informado';
        final eStats = equipeStatsMap.putIfAbsent(liderNome, () => _EquipeStats());
        eStats.totalParcelas++;
        final dataColeta = parcela.dataColeta;
        if (dataColeta != null) {
          eStats.diasTrabalhados.add(DateFormat('yyyy-MM-dd').format(dataColeta));
          if (eStats.dataInicio == null || dataColeta.isBefore(eStats.dataInicio!)) eStats.dataInicio = dataColeta;
          if (eStats.dataFim == null || dataColeta.isAfter(eStats.dataFim!)) eStats.dataFim = dataColeta;
        }
      }

      final todasAsCubagens = await _cubagemRepository.getTodasCubagens();
      final cubagensFiltradas = todasAsCubagens.where((c) => talhoesMap.containsKey(c.talhaoId));

      for (final cubagem in cubagensFiltradas) {
        if (cubagem.talhaoId == null) continue;
        final talhao = talhoesMap[cubagem.talhaoId]; if (talhao == null) continue;
        final atividade = atividadesMap[talhao.fazendaAtividadeId]; if (atividade == null) continue;
        final projeto = projetosMap[atividade.projetoId]; if (projeto == null) continue;
        final statusLabel = _statusLabelCubagem(cubagem);

        allColetasData.add({
          'projeto_nome': projeto.nome, 'atividade_tipo': atividade.tipo, 'fazenda_nome': cubagem.nomeFazenda,
          'talhao_nome': cubagem.nomeTalhao, 'id_coleta': cubagem.identificador, 'id_unico_amostra': null,
          'talhao_area_ha': talhao.areaHa, 'situacao': statusLabel,
          'data_alteracao': null, 'responsavel': cubagem.nomeLider, 'latitude': null, 'longitude': null,
          'parcela_area_m2': null, 'parcela_lado1_m': null, 'parcela_lado2_m': null, 'parcela_observacao': null,
          'total_fustes': 1, 'total_covas': 1, 'total_falhas': 0, 'total_codigos_especiais': 0,
          'cubagem_classe': cubagem.classe, 'cubagem_cap': cubagem.valorCAP, 'cubagem_altura': cubagem.alturaTotal,
        });

        final pStats = projetoStatsMap.putIfAbsent(projeto.nome, () => _ProjetoStats());
        if (talhao.id != null) pStats.talhaoIds.add(talhao.id!);
        if (cubagem.idFazenda != null || cubagem.nomeFazenda.isNotEmpty) pStats.fazendas.add(cubagem.nomeFazenda);

        final tStats = talhaoStatsMap.putIfAbsent(talhao.id!, () => _TalhaoStats()
          ..projetoNome = projeto.nome
          ..fazendaNome = cubagem.nomeFazenda
          ..talhaoNome = talhao.nome
          ..areaHa = talhao.areaHa
          ..especie = talhao.especie
          ..idadeAnos = talhao.idadeAnos);

        switch (statusLabel) {
          case 'Pendente': pStats.cubagensPendentes++; tStats.cubagensPendentes++; break;
          case 'Concluída': pStats.cubagensConcluidas++; tStats.cubagensConcluidas++; break;
          case 'Exportada': pStats.cubagensExportadas++; tStats.cubagensExportadas++; break;
        }

        final liderNome = cubagem.nomeLider ?? 'Não informado';
        final eStats = equipeStatsMap.putIfAbsent(liderNome, () => _EquipeStats());
        eStats.totalCubagens++;
        final dataColeta = cubagem.dataColeta;
        if (dataColeta != null) {
          eStats.diasTrabalhados.add(DateFormat('yyyy-MM-dd').format(dataColeta));
          if (eStats.dataInicio == null || dataColeta.isBefore(eStats.dataInicio!)) eStats.dataInicio = dataColeta;
          if (eStats.dataFim == null || dataColeta.isAfter(eStats.dataFim!)) eStats.dataFim = dataColeta;
        }
      }

      if (allColetasData.isEmpty) {
        ProgressDialog.hide(context);
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma coleta encontrada para os filtros selecionados.'), backgroundColor: Colors.orange));
        return;
      }

      final nf1 = NumberFormat("0.0", "pt_BR");
      final dfCurto = DateFormat('dd/MM/yyyy');

      final List<List<dynamic>> resumoProjetoRows = [
        ['Projeto', 'Nº Talhões', 'Nº Fazendas', 'Parcelas Pendentes', 'Parcelas Em Andamento',
          'Parcelas Concluídas', 'Parcelas Exportadas', 'Total Parcelas', '% Progresso Parcelas',
          'Cubagens Pendentes', 'Cubagens Concluídas', 'Cubagens Exportadas', 'Total Cubagens', '% Progresso Cubagens']
      ];
      projetoStatsMap.forEach((nome, s) {
        final totalParcelas = s.parcelasPendentes + s.parcelasAndamento + s.parcelasConcluidas + s.parcelasExportadas;
        final pctParcelas = totalParcelas > 0 ? (s.parcelasConcluidas + s.parcelasExportadas) / totalParcelas * 100 : 0.0;
        final totalCubagens = s.cubagensPendentes + s.cubagensConcluidas + s.cubagensExportadas;
        final pctCubagens = totalCubagens > 0 ? (s.cubagensConcluidas + s.cubagensExportadas) / totalCubagens * 100 : 0.0;
        resumoProjetoRows.add([
          nome, s.talhaoIds.length, s.fazendas.length,
          s.parcelasPendentes, s.parcelasAndamento, s.parcelasConcluidas, s.parcelasExportadas, totalParcelas, '${nf1.format(pctParcelas)}%',
          s.cubagensPendentes, s.cubagensConcluidas, s.cubagensExportadas, totalCubagens, '${nf1.format(pctCubagens)}%',
        ]);
      });

      final List<List<dynamic>> resumoTalhaoRows = [
        ['Projeto', 'Fazenda', 'Talhão', 'Área (ha)', 'Espécie', 'Idade (anos)',
          'Parcelas Pendentes', 'Parcelas Em Andamento', 'Parcelas Concluídas', 'Parcelas Exportadas',
          'Total Parcelas', '% Progresso Parcelas', 'Cubagens Pendentes', 'Cubagens Concluídas', 'Cubagens Exportadas', 'Total Cubagens']
      ];
      talhaoStatsMap.forEach((id, s) {
        final totalParcelas = s.parcelasPendentes + s.parcelasAndamento + s.parcelasConcluidas + s.parcelasExportadas;
        final pctParcelas = totalParcelas > 0 ? (s.parcelasConcluidas + s.parcelasExportadas) / totalParcelas * 100 : 0.0;
        final totalCubagens = s.cubagensPendentes + s.cubagensConcluidas + s.cubagensExportadas;
        resumoTalhaoRows.add([
          s.projetoNome, s.fazendaNome, s.talhaoNome,
          s.areaHa != null ? nf1.format(s.areaHa) : '', s.especie ?? '', s.idadeAnos != null ? nf1.format(s.idadeAnos) : '',
          s.parcelasPendentes, s.parcelasAndamento, s.parcelasConcluidas, s.parcelasExportadas, totalParcelas, '${nf1.format(pctParcelas)}%',
          s.cubagensPendentes, s.cubagensConcluidas, s.cubagensExportadas, totalCubagens,
        ]);
      });

      final List<List<dynamic>> produtividadeEquipeRows = [
        ['Líder/Equipe', 'Total Parcelas', 'Total Cubagens', 'Total Amostras', 'Dias Trabalhados',
          'Data Início', 'Data Fim', 'Média Parcelas/Dia', 'Média Cubagens/Dia', 'Média Amostras/Dia']
      ];
      equipeStatsMap.forEach((lider, s) {
        final totalAmostras = s.totalParcelas + s.totalCubagens;
        final dias = s.diasTrabalhados.length;
        final mediaParcelas = dias > 0 ? s.totalParcelas / dias : 0.0;
        final mediaCubagens = dias > 0 ? s.totalCubagens / dias : 0.0;
        final mediaAmostras = dias > 0 ? totalAmostras / dias : 0.0;
        produtividadeEquipeRows.add([
          lider, s.totalParcelas, s.totalCubagens, totalAmostras, dias,
          s.dataInicio != null ? dfCurto.format(s.dataInicio!) : '', s.dataFim != null ? dfCurto.format(s.dataFim!) : '',
          nf1.format(mediaParcelas), nf1.format(mediaCubagens), nf1.format(mediaAmostras),
        ]);
      });

      final List<List<dynamic>> qualidadeColetaRows = [
        ['Projeto', 'Fazenda', 'Talhão', 'Total Covas', 'Total Fustes', 'Total Falhas', '% Falhas',
          'Total Códigos Especiais', '% Códigos Especiais', 'Parcelas Sem GPS', 'Parcelas Com Observação',
          'Distância Média Planejado-Real (m)', 'Distância Máx. Planejado-Real (m)', 'Parcelas Com Desvio > 30m', 'Parcelas Sem Ponto Planejado']
      ];
      talhaoStatsMap.forEach((id, s) {
        final pctFalhas = s.totalCovas > 0 ? s.totalFalhas / s.totalCovas * 100 : 0.0;
        final pctCodigos = s.totalFustes > 0 ? s.totalCodigosEspeciais / s.totalFustes * 100 : 0.0;
        final totalParcelasTalhao = s.parcelasPendentes + s.parcelasAndamento + s.parcelasConcluidas + s.parcelasExportadas;
        final distanciaMedia = s.qtdComDistancia > 0 ? s.somaDistanciaPlanejadoReal / s.qtdComDistancia : null;
        qualidadeColetaRows.add([
          s.projetoNome, s.fazendaNome, s.talhaoNome, s.totalCovas, s.totalFustes, s.totalFalhas, '${nf1.format(pctFalhas)}%',
          s.totalCodigosEspeciais, '${nf1.format(pctCodigos)}%', s.parcelasSemGps, s.parcelasComObservacao,
          distanciaMedia != null ? nf1.format(distanciaMedia) : '', s.distanciaMaximaPlanejadoReal != null ? nf1.format(s.distanciaMaximaPlanejadoReal) : '',
          s.qtdDesvioAcimaTolerancia, totalParcelasTalhao - s.qtdComDistancia,
        ]);
      });

      final prefs = await SharedPreferences.getInstance();
      final payload = _DevEquipePayload(
        coletasData: allColetasData,
        nomeZona: prefs.getString('zona_utm_selecionada') ?? 'SIRGAS 2000 / UTM Zona 22S',
        proj4Defs: proj4Definitions,
        resumoProjetoRows: resumoProjetoRows,
        resumoTalhaoRows: resumoTalhaoRows,
        produtividadeEquipeRows: produtividadeEquipeRows,
        qualidadeColetaRows: qualidadeColetaRows,
      );
      final List<int> xlsxBytes = await compute(_generateXlsxDevEquipeBytesInIsolate, payload);
      final fName = 'relatorio_desenvolvimento_equipes_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.xlsx';
      final path = await _salvarBytesEObterCaminho(xlsxBytes, fName);
      if (context.mounted) {
        await Share.shareXFiles([XFile(path)], subject: 'Relatório de Desenvolvimento de Equipes - GeoForest');
      }
      ProgressDialog.hide(context);
    } catch (e, s) {
      ProgressDialog.hide(context);
      _handleExportError(context, 'gerar relatório de desenvolvimento', e, s);
    }
  }

  Future<void> exportarDados(BuildContext context) async {
    try {
      if (!await _requestPermission(context)) return;
      final licenseProvider = Provider.of<LicenseProvider>(context, listen: false);
      final cargo = licenseProvider.licenseData?.cargo;
      if (cargo == 'gerente') {
        await _showManagerExportDialog(context, isBackup: false);
      } else {
        await _exportarDadosDaEquipe(context);
      }
    } catch (e, s) {
      _handleExportError(context, 'iniciar exportação', e, s);
    }
  }

  Future<void> exportarTodasAsParcelasBackup(BuildContext context) async {
    try {
      if (!await _requestPermission(context)) return;
      final licenseProvider = Provider.of<LicenseProvider>(context, listen: false);
      final cargo = licenseProvider.licenseData?.cargo;
      if (cargo == 'gerente') {
        await _showManagerExportDialog(context, isBackup: true);
      } else {
        await _exportarBackupDaEquipe(context);
      }
    } catch (e, s) {
      _handleExportError(context, 'iniciar backup', e, s);
    }
  }

  Future<void> _exportarDadosDaEquipe(BuildContext context) async {
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);
    final nomeDoColetor = teamProvider.lider;
    if (nomeDoColetor == null || nomeDoColetor.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nome do líder não encontrado.')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Buscando coletas de "$nomeDoColetor"...')));
    final List<Parcela> parcelas = await _parcelaRepository.getUnexportedConcludedParcelasByLider(nomeDoColetor);
    if (parcelas.isEmpty && context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma parcela nova para exportar.'), backgroundColor: Colors.orange));
      return;
    }
    final nomeArquivoColetor = nomeDoColetor.replaceAll(RegExp(r'[^\w]'), '_');
    final String fName = 'geoforest_export_${nomeArquivoColetor}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx';
    final path = await _gerarXlsxParcela(parcelas, fName);
    if (context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      await Share.shareXFiles([XFile(path)], subject: 'Exportação GeoForest - Coleta de $nomeDoColetor');
      final idsParaMarcar = parcelas.map((p) => p.dbId).whereType<int>().toList();
      await _parcelaRepository.marcarParcelasComoExportadas(idsParaMarcar);
    }
  }

  Future<void> _exportarBackupDaEquipe(BuildContext context) async {
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);
    final nomeDoColetor = teamProvider.lider;
    if (nomeDoColetor == null || nomeDoColetor.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Buscando dados para o backup...')));
    final List<Parcela> parcelas = await _parcelaRepository.getConcludedParcelasByLiderParaBackup(nomeDoColetor);
    if (parcelas.isEmpty && context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma parcela encontrada para seu backup.'), backgroundColor: Colors.orange));
      return;
    }
    final String fName = 'geoforest_MEU_BACKUP_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.xlsx';
    final path = await _gerarXlsxParcela(parcelas, fName);
    if (context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      await Share.shareXFiles([XFile(path)], subject: 'Meu Backup GeoForest - $nomeDoColetor');
    }
  }

  Future<void> _showManagerExportDialog(BuildContext context, {required bool isBackup}) async {
    final todosProjetos = await _projetoRepository.getTodosOsProjetosParaGerente();
    final todosLideres = await _parcelaRepository.getDistinctLideres();
    if (context.mounted) {
      final result = await showDialog<ExportFilters>(
        context: context,
        builder: (dialogContext) => ManagerExportDialog(isBackup: isBackup, projetosDisponiveis: todosProjetos, lideresDisponiveis: todosLideres),
      );
      if (result != null && context.mounted) await _executarExportacaoGerente(context, result);
    }
  }

  Future<void> _executarExportacaoGerente(BuildContext context, ExportFilters filters) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Buscando dados com base nos filtros...')));
    List<Parcela> parcelasParaExportar;
    final gerenteProvider = Provider.of<GerenteProvider>(context, listen: false);
    final projetoFiltradoId = filters.selectedProjetoIds.length == 1 ? filters.selectedProjetoIds.first : null;
    final bool isProjetoNaMemoria = projetoFiltradoId != null && gerenteProvider.projetoCarregadoId == projetoFiltradoId;

    if (filters.isBackup) {
      parcelasParaExportar = await _parcelaRepository.getTodasConcluidasParcelasFiltrado(
        projetoIds: filters.selectedProjetoIds.isNotEmpty ? filters.selectedProjetoIds : null,
        lideresNomes: filters.selectedLideres.isNotEmpty ? filters.selectedLideres : null,
      );
    } else {
      if (isProjetoNaMemoria) {
         parcelasParaExportar = gerenteProvider.parcelasSincronizadas.where((p) {
            bool liderOk = filters.selectedLideres.isEmpty || filters.selectedLideres.contains(p.nomeLider ?? 'Gerente');
            bool naoExportada = !p.exportada;
            bool concluida = p.status == StatusParcela.concluida;
            return liderOk && naoExportada && concluida;
         }).toList();
         debugPrint("Exportando ${parcelasParaExportar.length} parcelas da MEMÓRIA (Rápido).");
      } else {
         parcelasParaExportar = await _parcelaRepository.getUnexportedConcludedParcelasFiltrado(
            projetoIds: filters.selectedProjetoIds.isNotEmpty ? filters.selectedProjetoIds : null,
            lideresNomes: filters.selectedLideres.isNotEmpty ? filters.selectedLideres : null,
         );
         debugPrint("Exportando ${parcelasParaExportar.length} parcelas do BANCO SQLITE (Completo).");
      }
    }

    if (parcelasParaExportar.isEmpty && context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma parcela encontrada para os filtros selecionados.')));
      return;
    }

    final tipo = filters.isBackup ? "BACKUP_GERENTE" : "EXPORT_GERENTE";
    final String fName = 'geoforest_${tipo}_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.xlsx';
    final path = await _gerarXlsxParcela(parcelasParaExportar, fName);

    if (context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      await Share.shareXFiles([XFile(path)], subject: 'Exportação do Gerente - GeoForest');
      if (!filters.isBackup) {
        final idsParaMarcar = parcelasParaExportar.map((p) => p.dbId).whereType<int>().toList();
        await _parcelaRepository.marcarParcelasComoExportadas(idsParaMarcar);
      }
    }
  }

  Future<String> _gerarXlsxParcela(List<Parcela> parcelas, String nomeArquivo) async {
    final Map<int, List<Map<String, dynamic>>> arvoresPorParcelaMap = {};
    final Set<int> talhaoIds = parcelas.map((p) => p.talhaoId).whereType<int>().toSet();
    final Map<int, Map<String, dynamic>> talhoesMapParaIsolate = {};

    for (final talhaoId in talhaoIds) {
      final talhao = await _talhaoRepository.getTalhaoById(talhaoId);
      if (talhao != null) talhoesMapParaIsolate[talhaoId] = talhao.toMap();
    }

    for (final parcela in parcelas) {
      if (parcela.dbId != null) {
        final arvores = await _parcelaRepository.getArvoresDaParcela(parcela.dbId!);
        arvoresPorParcelaMap[parcela.dbId!] = arvores.map((a) => a.toMap()).toList();
      }
    }

    String empresaFinal = "N/A";
    if (parcelas.isNotEmpty) {
      final projeto =
          await _projetoRepository.getProjetoPelaParcela(parcelas.first);
      empresaFinal = projeto?.empresa ?? "N/A";
    }

    // =========================================================================
    // Carrega os códigos para traduzir siglas e montar a(s) aba(s) de legenda
    // =========================================================================
    final codigosRepo = CodigosRepository();

    // Carrega listas de códigos para garantir que siglas sejam traduzidas
    final listaIpc = await codigosRepo.carregarCodigos('IPC');
    final listaBio = await codigosRepo.carregarCodigos('BIO');
    final listaIfc = await codigosRepo.carregarCodigos('IFC');
    final listaIfq = await codigosRepo.carregarCodigos('IFQ');
    final listaIfs = await codigosRepo.carregarCodigos('IFS');

    // Cria o mapa { "N": "Normal", "F": "Falha" ... }
    final Map<String, String> mapaUnificado = {};

    for (var c in [...listaIpc, ...listaBio, ...listaIfc, ...listaIfq, ...listaIfs]) {
      mapaUnificado[c.sigla.toUpperCase()] = c.descricao;
    }

    // Monta uma aba de legenda de códigos para cada tipo de atividade
    // presente nas parcelas exportadas (ex: parcelas de IPC geram a aba
    // "Codigos_IPC" com a tabela de códigos daquela atividade).
    final Set<String> tiposPresentes = parcelas
        .map((p) => codigosRepo.classificarTipo(p.atividadeTipo ?? 'IPC'))
        .toSet();
    final Map<String, List<List<dynamic>>> codigosPorTipo = {};
    for (final tipo in tiposPresentes) {
      codigosPorTipo[tipo] = await codigosRepo.carregarLinhasParaExport(tipo);
    }
    // =========================================================================

    final prefs = await SharedPreferences.getInstance();
    final payload = _CsvParcelaPayload(
      parcelasMap: parcelas.map((p) => p.toMap()).toList(),
      arvoresPorParcelaMap: arvoresPorParcelaMap,
      talhoesMap: talhoesMapParaIsolate,
      nomeLider: prefs.getString('nome_lider') ?? 'N/A',
      nomesAjudantes: prefs.getString('nomes_ajudantes') ?? 'N/A',
      nomeZona: prefs.getString('zona_utm_selecionada') ??
          'SIRGAS 2000 / UTM Zona 22S',
      proj4Defs: proj4Definitions,
      nomeEmpresa: empresaFinal,
      mapaCodigos: mapaUnificado,
      codigosPorTipo: codigosPorTipo,
    );

    final List<int> xlsxBytes =
        await compute(_generateXlsxParcelaBytesInIsolate, payload);

    return await _salvarBytesEObterCaminho(xlsxBytes, nomeArquivo);
  }
  Future<void> exportarNovasCubagens(BuildContext context) async {
    try {
      if (!await _requestPermission(context)) return;
      final licenseProvider = Provider.of<LicenseProvider>(context, listen: false);
      final cargo = licenseProvider.licenseData?.cargo;
      if (cargo == 'gerente') {
        await _showManagerCubagemExportDialog(context, isBackup: false);
      } else {
        final cubagens = await _cubagemRepository.getUnexportedCubagens();
        final cubagensConcluidas = cubagens.where((c) => c.alturaTotal > 0).toList();
        final hoje = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
        final nomeArquivo = 'geoforest_export_cubagens_$hoje.xlsx';
        await _gerarXlsxCubagem(context, cubagensConcluidas, nomeArquivo, true);
      }
    } catch (e, s) {
      _handleExportError(context, 'exportar cubagens', e, s);
    }
  }

  Future<void> exportarTodasCubagensBackup(BuildContext context) async {
    try {
      if (!await _requestPermission(context)) return;
      final licenseProvider = Provider.of<LicenseProvider>(context, listen: false);
      final cargo = licenseProvider.licenseData?.cargo;
      if (cargo == 'gerente') {
        await _showManagerCubagemExportDialog(context, isBackup: true);
      } else {
        final cubagens = await _cubagemRepository.getTodasCubagensParaBackup();
        final cubagensConcluidas = cubagens.where((c) => c.alturaTotal > 0).toList();
        final hoje = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
        final nomeArquivo = 'geoforest_BACKUP_CUBAGENS_$hoje.xlsx';
        await _gerarXlsxCubagem(context, cubagensConcluidas, nomeArquivo, false);
      }
    } catch (e, s) {
      _handleExportError(context, 'backup de cubagens', e, s);
    }
  }

  Future<void> _showManagerCubagemExportDialog(BuildContext context, {required bool isBackup}) async {
    final todosProjetos = await _projetoRepository.getTodosOsProjetosParaGerente();
    final todosLideres = await _cubagemRepository.getDistinctLideres();
    if (context.mounted) {
      final result = await showDialog<ExportFilters>(
        context: context,
        builder: (dialogContext) => ManagerExportDialog(isBackup: isBackup, projetosDisponiveis: todosProjetos, lideresDisponiveis: todosLideres),
      );
      if (result != null && context.mounted) await _executarExportacaoGerenteCubagem(context, result);
    }
  }

  Future<void> _executarExportacaoGerenteCubagem(BuildContext context, ExportFilters filters) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Buscando cubagens com base nos filtros...')));
    List<CubagemArvore> cubagensParaExportar;
    final gerenteProvider = Provider.of<GerenteProvider>(context, listen: false);
    final projetoFiltradoId = filters.selectedProjetoIds.length == 1 ? filters.selectedProjetoIds.first : null;
    final bool isProjetoNaMemoria = projetoFiltradoId != null && gerenteProvider.projetoCarregadoId == projetoFiltradoId;

    if (!filters.isBackup && isProjetoNaMemoria) {
         cubagensParaExportar = gerenteProvider.cubagensSincronizadas.where((c) {
            bool liderOk = filters.selectedLideres.isEmpty || filters.selectedLideres.contains(c.nomeLider ?? 'Gerente');
            bool naoExportada = !c.exportada;
            bool concluida = c.alturaTotal > 0;
            return liderOk && naoExportada && concluida;
         }).toList();
         debugPrint("Exportando ${cubagensParaExportar.length} cubagens da MEMÓRIA.");
    } else {
         cubagensParaExportar = await _cubagemRepository.getConcludedCubagensFiltrado(
          projetoIds: filters.selectedProjetoIds.isNotEmpty ? filters.selectedProjetoIds : null,
          lideresNomes: filters.selectedLideres.isNotEmpty ? filters.selectedLideres : null,
        );
        debugPrint("Exportando ${cubagensParaExportar.length} cubagens do BANCO SQLITE.");
    }

    if (cubagensParaExportar.isEmpty && context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma cubagem encontrada para os filtros selecionados.')));
      return;
    }
    final tipo = filters.isBackup ? "BACKUP_CUBAGEM_GERENTE" : "EXPORT_CUBAGEM_GERENTE";
    final String fName = 'geoforest_${tipo}_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.xlsx';
    await _gerarXlsxCubagem(context, cubagensParaExportar, fName, !filters.isBackup);
  }

  Future<void> _gerarXlsxCubagem(BuildContext context, List<CubagemArvore> cubagens, String nomeArquivo, bool marcarComoExportado) async {
    if (cubagens.isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma cubagem encontrada para exportar.'), backgroundColor: Colors.orange));
      return;
    }
    String empresaFinal = "N/A";
    if (cubagens.isNotEmpty) {
      final projeto = await _projetoRepository.getProjetoPelaCubagem(cubagens.first);
      empresaFinal = projeto?.empresa ?? "N/A";
    }
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gerando planilha de cubagens...')));

    final Set<int> talhaoIds = cubagens.map((c) => c.talhaoId).whereType<int>().toSet();
    final Map<int, Map<String, dynamic>> talhoesMapParaIsolate = {};
    for (final talhaoId in talhaoIds) {
      final talhao = await _talhaoRepository.getTalhaoById(talhaoId);
      if (talhao != null) talhoesMapParaIsolate[talhaoId] = talhao.toMap();
    }
    final Map<int, List<Map<String, dynamic>>> secoesPorCubagemMap = {};
    for (final cubagem in cubagens) {
      if (cubagem.id != null) {
        final secoes = await _cubagemRepository.getSecoesPorArvoreId(cubagem.id!);
        secoesPorCubagemMap[cubagem.id!] = secoes.map((s) => s.toMap()).toList();
      }
    }

    // Monta a aba "Classes": quantidade de árvores planejadas x realizadas
    // por classe diamétrica, com base no campo `classe` de cada árvore de
    // cubagem (atribuído no plano de cubagem gerado a partir da distribuição
    // diamétrica do inventário).
    final List<List<dynamic>> classesRows = [
      ['Talhao', 'Classe', 'Qtd_Planejada', 'Qtd_Realizada', 'Pct_Realizado']
    ];
    for (final talhaoId in talhaoIds) {
      final todasDoTalhao = await _cubagemRepository.getTodasCubagensDoTalhao(talhaoId);
      if (todasDoTalhao.isEmpty) continue;
      final nomeTalhao = todasDoTalhao.first.nomeTalhao;
      final Map<String, int> planejadoPorClasse = {};
      final Map<String, int> realizadoPorClasse = {};
      for (final arv in todasDoTalhao) {
        final classe = (arv.classe == null || arv.classe!.isEmpty) ? 'Sem Classe' : arv.classe!;
        planejadoPorClasse[classe] = (planejadoPorClasse[classe] ?? 0) + 1;
        if (arv.alturaTotal > 0) {
          realizadoPorClasse[classe] = (realizadoPorClasse[classe] ?? 0) + 1;
        }
      }
      final classesOrdenadas = planejadoPorClasse.keys.toList()..sort();
      for (final classe in classesOrdenadas) {
        final planejado = planejadoPorClasse[classe] ?? 0;
        final realizado = realizadoPorClasse[classe] ?? 0;
        final pct = planejado > 0 ? (realizado / planejado * 100) : 0.0;
        classesRows.add([nomeTalhao, classe, planejado, realizado, '${pct.toStringAsFixed(1)}%']);
      }
    }

    final teamProvider = Provider.of<TeamProvider>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();
    final payload = _CsvCubagemPayload(
      cubagensMap: cubagens.map((c) => c.toMap()).toList(),
      secoesPorCubagemMap: secoesPorCubagemMap,
      talhoesMap: talhoesMapParaIsolate,
      nomeLider: teamProvider.lider ?? 'N/A',
      nomesAjudantes: teamProvider.ajudantes ?? 'N/A',
      nomeZona: prefs.getString('zona_utm_selecionada') ?? 'SIRGAS 2000 / UTM Zona 22S',
      proj4Defs: proj4Definitions,
      nomeEmpresa: empresaFinal,
      classesRows: classesRows,
    );
    final List<int> xlsxBytes = await compute(_generateXlsxCubagemBytesInIsolate, payload);
    String path = await _salvarBytesEObterCaminho(xlsxBytes, nomeArquivo);
    if (context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      await Share.shareXFiles([XFile(path)], subject: 'Exportação de Cubagens GeoForest');
      if (marcarComoExportado) {
        final idsParaMarcar = cubagens.map((c) => c.id).whereType<int>().toList();
        await _cubagemRepository.marcarCubagensComoExportadas(idsParaMarcar);
      }
    }
  }

  Future<void> exportarAnaliseTalhaoCsv({required BuildContext context, required Talhao talhao, required TalhaoAnalysisResult analise}) async {
    try {
      if (!await _requestPermission(context)) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gerando planilha de análise...')));
      final nf1 = NumberFormat("0.0", "pt_BR");
      final nf2 = NumberFormat("0.00", "pt_BR");
      final nf4 = NumberFormat("0.0000", "pt_BR");

      final excelFile = Excel.createExcel();
      const sheetResumo = 'Resumo';
      const sheetDistribuicao = 'Distribuicao_Diametrica';
      const sheetCodigos = 'Analise_Por_Codigo';
      const sheetAlertas = 'Alertas_Insights';
      final sheetPadrao = excelFile.getDefaultSheet();

      void addRow(String sheet, List<dynamic> row) {
        excelFile.appendRow(sheet, row.map(_paraCellValue).toList());
      }

      // --- Resumo ---
      addRow(sheetResumo, ['Resumo do Talhão']);
      addRow(sheetResumo, ['Métrica', 'Valor']);
      addRow(sheetResumo, ['Fazenda', talhao.fazendaNome ?? 'N/A']);
      addRow(sheetResumo, ['Talhão', talhao.nome]);
      addRow(sheetResumo, ['Nº de Parcelas Amostradas', analise.totalParcelasAmostradas]);
      addRow(sheetResumo, ['Nº de Árvores Medidas', analise.totalArvoresAmostradas]);
      addRow(sheetResumo, ['Área Total Amostrada (ha)', nf4.format(analise.areaTotalAmostradaHa)]);
      addRow(sheetResumo, ['']);
      addRow(sheetResumo, ['Resultados por Hectare']);
      addRow(sheetResumo, ['Métrica', 'Valor']);
      addRow(sheetResumo, ['Árvores / ha', analise.arvoresPorHectare]);
      addRow(sheetResumo, ['Área Basal (G) m²/ha', nf2.format(analise.areaBasalPorHectare)]);
      addRow(sheetResumo, ['Volume Estimado m³/ha', nf2.format(analise.volumePorHectare)]);
      addRow(sheetResumo, ['']);
      addRow(sheetResumo, ['Estatísticas da Amostra']);
      addRow(sheetResumo, ['Métrica', 'Valor']);
      addRow(sheetResumo, ['CAP Médio (cm)', nf1.format(analise.mediaCap)]);
      addRow(sheetResumo, ['Altura Média (m)', nf1.format(analise.mediaAltura)]);
      if (analise.alturaDominante > 0) {
        addRow(sheetResumo, ['Altura Dominante - HD (m)', nf1.format(analise.alturaDominante)]);
      }
      if (analise.indiceDeSitio > 0) {
        addRow(sheetResumo, ['Índice de Sítio (7 anos)', nf1.format(analise.indiceDeSitio)]);
      }

      // --- Distribuição Diamétrica ---
      addRow(sheetDistribuicao, ['Classe (cm)', 'Nº de Árvores', '%']);
      final totalArvoresVivas = analise.distribuicaoDiametrica.values.fold(0, (a, b) => a + b);
      final classesOrdenadas = analise.distribuicaoDiametrica.keys.toList()..sort();
      for (final pontoMedio in classesOrdenadas) {
        final contagem = analise.distribuicaoDiametrica[pontoMedio]!;
        final inicioClasse = pontoMedio - 2.5;
        final fimClasse = pontoMedio + 2.5 - 0.1;
        final porcentagem = totalArvoresVivas > 0 ? (contagem / totalArvoresVivas) * 100 : 0;
        addRow(sheetDistribuicao, ['${nf1.format(inicioClasse)} - ${nf1.format(fimClasse)}', contagem, '${nf1.format(porcentagem)}%']);
      }

      // --- Análise por Código ---
      final codigos = analise.analiseDeCodigos;
      if (codigos != null) {
        addRow(sheetCodigos, ['Total de Fustes', codigos.totalFustes]);
        addRow(sheetCodigos, ['Total de Covas Ocupadas', codigos.totalCovasOcupadas]);
        addRow(sheetCodigos, ['Total de Covas Amostradas', codigos.totalCovasAmostradas]);
        addRow(sheetCodigos, ['']);
        addRow(sheetCodigos, ['Contagem por Código']);
        addRow(sheetCodigos, ['Código', 'Quantidade']);
        codigos.contagemPorCodigo.forEach((codigo, qtd) {
          addRow(sheetCodigos, [codigo, qtd]);
        });
        addRow(sheetCodigos, ['']);
        addRow(sheetCodigos, ['Estatísticas por Código']);
        addRow(sheetCodigos, ['Código', 'Média CAP', 'Mediana CAP', 'Moda CAP', 'Desvio Padrão CAP', 'Média Altura', 'Mediana Altura', 'Moda Altura', 'Desvio Padrão Altura']);
        codigos.estatisticasPorCodigo.forEach((codigo, stats) {
          addRow(sheetCodigos, [
            codigo, nf1.format(stats.mediaCap), nf1.format(stats.medianaCap), nf1.format(stats.modaCap), nf2.format(stats.desvioPadraoCap),
            nf1.format(stats.mediaAltura), nf1.format(stats.medianaAltura), nf1.format(stats.modaAltura), nf2.format(stats.desvioPadraoAltura),
          ]);
        });
      } else {
        addRow(sheetCodigos, ['Sem dados de análise por código disponíveis para este talhão.']);
      }

      // --- Alertas / Insights / Recomendações ---
      addRow(sheetAlertas, ['Tipo', 'Mensagem']);
      for (final w in analise.warnings) { addRow(sheetAlertas, ['Alerta', w]); }
      for (final i in analise.insights) { addRow(sheetAlertas, ['Insight', i]); }
      for (final r in analise.recommendations) { addRow(sheetAlertas, ['Recomendação', r]); }
      if (analise.warnings.isEmpty && analise.insights.isEmpty && analise.recommendations.isEmpty) {
        addRow(sheetAlertas, ['Nenhum', 'Sem alertas, insights ou recomendações para este talhão.']);
      }

      if (sheetPadrao != null && sheetPadrao != sheetResumo) {
        excelFile.delete(sheetPadrao);
      }
      excelFile.setDefaultSheet(sheetResumo);

      final bytes = excelFile.save() ?? <int>[];
      final hoje = DateTime.now();
      final fName = 'analise_talhao_${talhao.nome.replaceAll(' ', '_')}_${DateFormat('yyyy-MM-dd_HH-mm').format(hoje)}.xlsx';
      final path = await _salvarBytesEObterCaminho(bytes, fName);
      if (context.mounted) {
        await Share.shareXFiles([XFile(path)], subject: 'Análise do Talhão ${talhao.nome}');
      }
    } catch (e, s) {
      _handleExportError(context, 'exportar análise', e, s);
    }
  }

  Future<void> exportarPlanoDeAmostragem({required BuildContext context, required List<int> parcelaIds}) async {
    if (parcelaIds.isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum plano de amostragem para exportar.'), backgroundColor: Colors.orange));
      return;
    }
    ProgressDialog.show(context, 'Gerando GeoJSON...');
    try {
      final List<Map<String, dynamic>> features = [];
      String nomeProjetoFinal = 'PlanoAmostragem';
      final allParcelas = (await Future.wait(parcelaIds.map((id) => _parcelaRepository.getParcelaById(id)))).whereType<Parcela>().toList();
      final talhaoIds = allParcelas.map((p) => p.talhaoId).whereType<int>().toSet();
      final allTalhoes = <int, Talhao>{};
      for (final talhaoId in talhaoIds) {
        final talhao = await _talhaoRepository.getTalhaoById(talhaoId);
        if (talhao != null) allTalhoes[talhaoId] = talhao;
      }
      if (allParcelas.isNotEmpty) {
        final projeto = await _projetoRepository.getProjetoPelaParcela(allParcelas.first);
        if (projeto != null) nomeProjetoFinal = projeto.nome;
      }
      final prefs = await SharedPreferences.getInstance();
      final nomeZona = prefs.getString('zona_utm_selecionada') ?? 'SIRGAS 2000 / UTM Zona 22S';
      final codigoEpsg = zonasUtmSirgas2000[nomeZona] ?? 31982;
      final projWGS84 = proj4.Projection.get('EPSG:4326')!;
      final projUTM = proj4.Projection.get('EPSG:$codigoEpsg') ?? proj4.Projection.parse(proj4Definitions[codigoEpsg]!);
      final zonaUtmStr = nomeZona.split(' ').last;

      for (final parcela in allParcelas) {
        final talhao = allTalhoes[parcela.talhaoId];
        if (parcela.latitude != null && parcela.longitude != null) {
          var pUtm = projWGS84.transform(projUTM, proj4.Point(x: parcela.longitude!, y: parcela.latitude!));
          features.add({
            'type': 'Feature',
            'geometry': {'type': 'Point', 'coordinates': [parcela.longitude, parcela.latitude]},
            'properties': {
              'atividade': parcela.atividadeTipo ?? 'N/A', 'bloco': talhao?.bloco, 'fazenda_nome': parcela.nomeFazenda,
              'fazenda_id': parcela.idFazenda, 'rf': parcela.up, 'talhao_nome': parcela.nomeTalhao, 'parcela': parcela.idParcela,
              'area_talhao_ha': talhao?.areaHa, 'especie': talhao?.especie, 'material': talhao?.materialGenetico,
              'espacamento': talhao?.espacamento, 'plantio': talhao?.dataPlantio, 'regime': null,
              'lado1': parcela.lado1, 'lado2': parcela.lado2, 'area_parcela_m2': parcela.areaMetrosQuadrados,
              'tipo': parcela.tipoParcela, 'ciclo': parcela.ciclo, 'rotacao': parcela.rotacao, 'situacao': null,
              'medir_?': 'SIM', 'status': parcela.status.name,
              'data_realizacao': parcela.status == StatusParcela.concluida ? DateFormat('dd/MM/yyyy').format(parcela.dataColeta!) : null,
              'observacao': parcela.observacao, 'zona_utm': zonaUtmStr, 'long_x': pUtm.x.toStringAsFixed(0),
              'lat_y': pUtm.y.toStringAsFixed(0), 'alt_z': parcela.altitude,
            }
          });
        }
      }
      final Map<String, dynamic> geoJson = {'type': 'FeatureCollection', 'features': features};
      const jsonEncoder = JsonEncoder.withIndent('  ');
      final jsonString = jsonEncoder.convert(geoJson);
      final hoje = DateTime.now();
      final fName = 'Plano_Amostragem_${nomeProjetoFinal.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd_HHmm').format(hoje)}.json';
      await _salvarECompartilhar(context: context, fileContent: jsonString, fileName: fName, subject: 'Plano de Amostragem GeoForest');
    } catch (e, s) {
      _handleExportError(context, 'exportar plano de amostragem', e, s);
    } finally {
      ProgressDialog.hide(context);
    }
  }

  Future<void> exportarTudoComoZip({required BuildContext context, required List<Talhao> talhoes}) async {
    if (talhoes.isEmpty) return;
    try {
      if (!await _requestPermission(context)) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Iniciando exportação completa...'), duration: Duration(seconds: 20)));
      final directory = await getApplicationDocumentsDirectory();
      final hoje = DateTime.now();
      final nomePasta = 'Exportacao_Completa_${DateFormat('yyyy-MM-dd_HH-mm').format(hoje)}';
      final pastaDeExportacao = Directory('${directory.path}/$nomePasta');
      if (await pastaDeExportacao.exists()) await pastaDeExportacao.delete(recursive: true);
      await pastaDeExportacao.create(recursive: true);
      await _gerarCsvParcelasParaZip(context, talhoes, '${pastaDeExportacao.path}/parcelas_coletadas.xlsx');
      await _gerarCsvCubagensParaZip(context, talhoes, '${pastaDeExportacao.path}/cubagens_realizadas.xlsx');
      final zipFilePath = '${directory.path}/$nomePasta.zip';
      final zipFile = File(zipFilePath);
      await ZipFile.createFromDirectory(sourceDir: pastaDeExportacao, zipFile: zipFile, recurseSubDirs: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        await Share.shareXFiles([XFile(zipFilePath)], subject: 'Exportação Completa - GeoForest');
      }
    } catch (e, s) {
      _handleExportError(context, 'criar pacote de exportação', e, s);
    }
  }

  Future<void> _gerarCsvParcelasParaZip(BuildContext context, List<Talhao> talhoes, String filePath) async {
    final List<Parcela> todasAsParcelas = [];
    for (final talhao in talhoes) {
      final talhaoId = talhao.id;
      if (talhaoId != null) {
        final parcelasDoTalhao = await _parcelaRepository.getParcelasDoTalhao(talhaoId);
        todasAsParcelas.addAll(parcelasDoTalhao.where((p) => p.status == StatusParcela.concluida));
      }
    }
    if (todasAsParcelas.isNotEmpty) await _gerarXlsxParcela(todasAsParcelas, filePath);
  }

  Future<void> _gerarCsvCubagensParaZip(BuildContext context, List<Talhao> talhoes, String outputPath) async {
    final List<CubagemArvore> todasAsCubagens = [];
    for (final talhao in talhoes) {
      final talhaoId = talhao.id;
      if (talhaoId != null) {
        final cubagensDoTalhao = await _cubagemRepository.getTodasCubagensDoTalhao(talhaoId);
        todasAsCubagens.addAll(cubagensDoTalhao.where((c) => c.alturaTotal > 0));
      }
    }
    if (todasAsCubagens.isNotEmpty) await _gerarXlsxCubagem(context, todasAsCubagens, outputPath, false);
  }

  Future<bool> _requestPermission(BuildContext context) async {
    final permissionService = PermissionService();
    final hasPermission = await permissionService.requestStoragePermission();
    if (!hasPermission && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permissão de acesso ao armazenamento negada.'), backgroundColor: Colors.red));
    return hasPermission;
  }

  void _handleExportError(BuildContext context, String action, Object e, StackTrace s) {
    debugPrint('Erro ao $action: $e\n$s');
    if (context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao $action: ${e.toString()}'), backgroundColor: Colors.red));
    }
  }

  Future<String> _salvarBytesEObterCaminho(List<int> bytes, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$fileName';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  Future<String> _salvarEObterCaminho(String fileContent, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$fileName';
    final bom = [0xEF, 0xBB, 0xBF];
    final bytes = utf8.encode(fileContent);
    await File(path).writeAsBytes(fileName.endsWith('.csv') ? [...bom, ...bytes] : bytes);
    return path;
  }

  Future<void> _salvarECompartilhar({required BuildContext context, required String fileContent, required String fileName, required String subject}) async {
    final path = await _salvarEObterCaminho(fileContent, fileName);
    if (context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      await Share.shareXFiles([XFile(path, name: fileName)], subject: subject);
    }
  }

}
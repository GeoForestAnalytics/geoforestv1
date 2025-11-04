// lib/services/export_service.dart (VERSÃO CORRIGIDA PARA FORMATAÇÃO DE NÚMEROS)

import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
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
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/providers/team_provider.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/utils/constants.dart';
import 'package:geoforestv1/widgets/manager_export_dialog.dart';
import 'package:geoforestv1/models/cubagem_secao_model.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/atividade_model.dart';

// PAYLOADS ... (Sem alterações aqui)
class _CsvParcelaPayload {
  final List<Map<String, dynamic>> parcelasMap;
  final Map<int, List<Map<String, dynamic>>> arvoresPorParcelaMap;
  final Map<int, Map<String, dynamic>> talhoesMap;
  final String nomeLider;
  final String nomesAjudantes;
  final String nomeZona;
  final Map<int, String> proj4Defs;

  _CsvParcelaPayload({
    required this.parcelasMap,
    required this.arvoresPorParcelaMap,
    required this.talhoesMap,
    required this.nomeLider,
    required this.nomesAjudantes,
    required this.nomeZona,
    required this.proj4Defs,
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

  _CsvCubagemPayload({
    required this.cubagensMap,
    required this.secoesPorCubagemMap,
    required this.talhoesMap,
    required this.nomeLider,
    required this.nomesAjudantes,
    required this.nomeZona,
    required this.proj4Defs,
  });
}

class _DevEquipePayload {
  final List<Map<String, dynamic>> coletasData;
  final String nomeZona;
  final Map<int, String> proj4Defs;

  _DevEquipePayload({
    required this.coletasData,
    required this.nomeZona,
    required this.proj4Defs,
  });
}

class _CsvOperacoesPayload {
  final List<Map<String, dynamic>> diariosMap;
  _CsvOperacoesPayload({ required this.diariosMap });
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


// FUNÇÕES DE ISOLATE...

// =========================================================================
// ==================== INÍCIO DAS CORREÇÕES DE FORMATAÇÃO ====================
// =========================================================================

Future<String> _generateCsvParcelaDataInIsolate(_CsvParcelaPayload payload) async {
  proj4.Projection.add('EPSG:4326', '+proj=longlat +datum=WGS84 +no_defs');
  payload.proj4Defs.forEach((epsg, def) {
    proj4.Projection.add('EPSG:$epsg', def);
  });
  
  final codigoEpsg = zonasUtmSirgas2000[payload.nomeZona] ?? 31982;
  final projWGS84 = proj4.Projection.get('EPSG:4326');
  final projUTM = proj4.Projection.get('EPSG:$codigoEpsg');

  if (projWGS84 == null || projUTM == null) {
      return 'ERRO,"Não foi possível inicializar o sistema de projeção de coordenadas."';
  }

  // ✅ 1. CRIAR OS FORMATADORES DE NÚMERO
  final nf1 = NumberFormat("0.0", "pt_BR");   // Formato para 1 casa decimal
  final nf2 = NumberFormat("0.00", "pt_BR");  // Formato para 2 casas decimais

  List<List<dynamic>> rows = [];
  rows.add(['Atividade', 'Lider_Equipe', 'Ajudantes', 'ID_Db_Parcela', 'Codigo_Fazenda', 'Fazenda', 'UP', 'Talhao', 'Area_Talhao_ha', 'Especie', 'Espacamento', 'Idade_Anos', 'ID_Coleta_Parcela', 'Area_Inclinada_m2', 'Area_Horizontal_m2', 'Lado1_m', 'Lado2_m', 'Declividade_Graus', 'Observacao_Parcela', 'Easting', 'Northing', 'Data_Coleta', 'Status_Parcela', 'Linha', 'Posicao_na_Linha', 'Fuste_Num', 'Codigo_Arvore', 'Codigo_Arvore_2', 'CAP_cm', 'Altura_m', 'Altura_Dano_m', 'Dominante']);
  
  for (var pMap in payload.parcelasMap) {
    final p = Parcela.fromMap(pMap);
    final talhaoData = payload.talhoesMap[p.talhaoId] ?? {};
    
    String easting = '', northing = '';
    if (p.latitude != null && p.longitude != null) {
      var pUtm = projWGS84.transform(projUTM, proj4.Point(x: p.longitude!, y: p.latitude!));
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

    // ✅ 2. FUNÇÃO AUXILIAR PARA FORMATAR VALORES NULOS
    String formatValue(double? value, NumberFormat formatter) {
      return value != null ? formatter.format(value) : '';
    }

    if (arvores.isEmpty) {
       rows.add([
         p.atividadeTipo ?? 'IPC', liderDaColeta, payload.nomesAjudantes, p.dbId, p.idFazenda, p.nomeFazenda, 
         p.up, p.nomeTalhao, formatValue(talhaoData['areaHa'], nf2), talhaoData['especie'], 
         talhaoData['espacamento'], formatValue(talhaoData['idadeAnos'], nf1), p.idParcela, 
         nf2.format(areaInclinada), nf2.format(p.areaMetrosQuadrados), formatValue(p.lado1, nf2), 
         formatValue(p.lado2, nf2), formatValue(p.declividade, nf2), p.observacao, 
         easting, northing, p.dataColeta?.toIso8601String(), p.status.name, 
         null, null, null, null, null, null, null, null, null, null, null
       ]);
    } else {
      Map<String, int> fusteCounter = {};
      for (final a in arvores) {
        String key = '${a.linha}-${a.posicaoNaLinha}';
        fusteCounter[key] = (fusteCounter[key] ?? 0) + 1;
        rows.add([
          p.atividadeTipo ?? 'IPC', liderDaColeta, payload.nomesAjudantes, p.dbId, p.idFazenda, p.nomeFazenda, 
          p.up, p.nomeTalhao, formatValue(talhaoData['areaHa'], nf2), talhaoData['especie'], 
          talhaoData['espacamento'], formatValue(talhaoData['idadeAnos'], nf1), p.idParcela, 
          nf2.format(areaInclinada), nf2.format(p.areaMetrosQuadrados), formatValue(p.lado1, nf2), 
          formatValue(p.lado2, nf2), formatValue(p.declividade, nf2), p.observacao, 
          easting, northing, p.dataColeta?.toIso8601String(), p.status.name, 
          a.linha, a.posicaoNaLinha, fusteCounter[key], a.codigo.name, a.codigo2?.name, 
          formatValue(a.cap, nf1), formatValue(a.altura, nf1), formatValue(a.alturaDano, nf1), a.dominante ? 'Sim' : 'Não'
        ]);
      }
    }
  }
  return const ListToCsvConverter().convert(rows, fieldDelimiter: ';');
}

Future<String> _generateCsvCubagemDataInIsolate(_CsvCubagemPayload payload) async {
  proj4.Projection.add('EPSG:4326', '+proj=longlat +datum=WGS84 +no_defs');
  payload.proj4Defs.forEach((epsg, def) {
    proj4.Projection.add('EPSG:$epsg', def);
  });
  
  final codigoEpsg = zonasUtmSirgas2000[payload.nomeZona] ?? 31982;
  final projWGS84 = proj4.Projection.get('EPSG:4326');
  final projUTM = proj4.Projection.get('EPSG:$codigoEpsg');

  if (projWGS84 == null || projUTM == null) {
      return 'ERRO,"Não foi possível inicializar o sistema de projeção de coordenadas."';
  }

  // ✅ 1. CRIAR OS FORMATADORES DE NÚMERO
  final nf1 = NumberFormat("0.0", "pt_BR");
  final nf2 = NumberFormat("0.00", "pt_BR");

  List<List<dynamic>> rows = [];
  rows.add([
    'Atividade', 'Lider_Equipe', 'Ajudantes', 'id_db_arvore', 'id_fazenda', 'fazenda', 'UP', 'talhao', 'area_talhao_ha', 'especie', 'espacamento', 'idade_anos', 'identificador_arvore', 'classe', 'altura_total_m', 'tipo_medida_cap', 'valor_cap', 'altura_base_m', 'Data_Coleta', 'Easting_Cubagem', 'Northing_Cubagem', 'Observacao_Cubagem', 'altura_medicao_secao_m', 'circunferencia_secao_cm', 'casca1_mm', 'casca2_mm', 'dsc_cm'
  ]);

  for (var cMap in payload.cubagensMap) {
    final arvore = CubagemArvore.fromMap(cMap);
    final talhaoData = payload.talhoesMap[arvore.talhaoId] ?? {};

    final rf = talhaoData['up'] ?? 'N/A';
    String easting = '', northing = '';
    if (arvore.latitude != null && arvore.longitude != null) {
      var pUtm = projWGS84.transform(projUTM, proj4.Point(x: arvore.longitude!, y: arvore.latitude!));
      easting = nf2.format(pUtm.x);
      northing = nf2.format(pUtm.y);
    }
    
    final secoesMap = payload.secoesPorCubagemMap[arvore.id] ?? [];
    final secoes = secoesMap.map((sMap) => CubagemSecao.fromMap(sMap)).toList();
    
    final liderDaColeta = arvore.nomeLider ?? payload.nomeLider;
    final dataColetaFormatada = arvore.dataColeta != null 
        ? DateFormat('dd/MM/yyyy HH:mm').format(arvore.dataColeta!) 
        : '';
        
    // ✅ 2. FUNÇÃO AUXILIAR PARA FORMATAR
    String formatValue(double? value, NumberFormat formatter) {
      return value != null ? formatter.format(value) : '';
    }

    if (secoes.isEmpty) {
      rows.add([
        'CUB', liderDaColeta, payload.nomesAjudantes, arvore.id, arvore.idFazenda, 
        arvore.nomeFazenda, rf, arvore.nomeTalhao, formatValue(talhaoData['areaHa'], nf2), 
        talhaoData['especie'], talhaoData['espacamento'], formatValue(talhaoData['idadeAnos'], nf1), 
        arvore.identificador, arvore.classe, formatValue(arvore.alturaTotal, nf2), arvore.tipoMedidaCAP, 
        formatValue(arvore.valorCAP, nf2), formatValue(arvore.alturaBase, nf2), 
        dataColetaFormatada,
        easting, northing, arvore.observacao,
        null, null, null, null, null
      ]);
    } else {
      for (var secao in secoes) {
        rows.add([
          'CUB', liderDaColeta, payload.nomesAjudantes, arvore.id, arvore.idFazenda, 
          arvore.nomeFazenda, rf, arvore.nomeTalhao, formatValue(talhaoData['areaHa'], nf2), 
          talhaoData['especie'], talhaoData['espacamento'], formatValue(talhaoData['idadeAnos'], nf1), 
          arvore.identificador, arvore.classe, formatValue(arvore.alturaTotal, nf2), arvore.tipoMedidaCAP, 
          formatValue(arvore.valorCAP, nf2), formatValue(arvore.alturaBase, nf2), 
          dataColetaFormatada,
          easting, northing, arvore.observacao,
          formatValue(secao.alturaMedicao, nf2), formatValue(secao.circunferencia, nf2), formatValue(secao.casca1_mm, nf2), 
          formatValue(secao.casca2_mm, nf2), nf2.format(secao.diametroSemCasca)
        ]);
      }
    }
  }
  return const ListToCsvConverter().convert(rows, fieldDelimiter: ';');
}

// =========================================================================
// ===================== FIM DAS CORREÇÕES DE FORMATAÇÃO =====================
// =========================================================================

Future<String> _generateDevEquipeCsvInIsolate(_DevEquipePayload payload) async {
  proj4.Projection.add('EPSG:4326', '+proj=longlat +datum=WGS84 +no_defs');
  payload.proj4Defs.forEach((epsg, def) {
    proj4.Projection.add('EPSG:$epsg', def);
  });
  
  final codigoEpsg = zonasUtmSirgas2000[payload.nomeZona] ?? 31982;
  final projWGS84 = proj4.Projection.get('EPSG:4326');
  final projUTM = proj4.Projection.get('EPSG:$codigoEpsg');

  if (projWGS84 == null || projUTM == null) {
      return 'ERRO,"Não foi possível inicializar o sistema de projeção de coordenadas."';
  }
  
  final nf2 = NumberFormat("0.00", "pt_BR");
  
  List<List<dynamic>> rows = [];
  rows.add([
    'Projeto', 'Atividade', 'Fazenda', 'Talhao', 'ID_Amostra_Coleta', 'Area_Talhao_ha',
    'Situacao', 'Data_Alteracao', 'Responsavel', 'Coord_X_UTM', 'Coord_Y_UTM',
    'Area_Parcela_m2', 'Lado1_m', 'Lado2_m', 'Observacao_Parcela',
    'Total_Fustes', 'Total_Covas', 'Total_Falhas', 'Total_Codigos_Especiais',
    'Classe Arvore - Cubagem', 'CAP Arvore - Cubagem', 'Altura Cubagem'
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
      rowData['projeto_nome'],
      rowData['atividade_tipo'],
      rowData['fazenda_nome'],
      rowData['talhao_nome'],
      rowData['id_coleta'],
      formatValue(rowData['talhao_area_ha'], nf2),
      rowData['situacao'],
      rowData['data_alteracao'],
      rowData['responsavel'],
      easting,
      northing,
      formatValue(rowData['parcela_area_m2'], nf2),
      formatValue(rowData['parcela_lado1_m'], nf2),
      formatValue(rowData['parcela_lado2_m'], nf2),
      rowData['parcela_observacao'],
      rowData['total_fustes'],
      rowData['total_covas'],
      rowData['total_falhas'],
      rowData['total_codigos_especiais'],
      rowData['cubagem_classe'],
      formatValue(rowData['cubagem_cap'], nf2),
      formatValue(rowData['cubagem_altura'], nf2),
    ]);
  }

  return const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
}

Future<String> _generateCsvOperacoesInIsolate(_CsvOperacoesPayload payload) async {
    final List<List<dynamic>> rows = [];
  final nf = NumberFormat("#,##0.00", "pt_BR");
  final nfKm = NumberFormat("#,##0.0", "pt_BR");

  rows.add([
    'Data', 'Líder', 'Equipe', 'Veículo (Placa)', 'KM Rodados',
    'Custo Abastecimento (R\$)', 'Custo Alimentação (R\$)', 'Custo Pedágio (R\$)',
    'Outros Gastos (R\$)', 'Descrição Outros Gastos',
    'Custo Total (R\$)', 'Destino'
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
    final custoTotal = (d.abastecimentoValor ?? 0) + (d.pedagioValor ?? 0) + (d.alimentacaoRefeicaoValor ?? 0) + (d.outrasDespesasValor ?? 0);

    rows.add([
      DateFormat('dd/MM/yyyy').format(DateTime.parse(d.dataRelatorio)),
      d.nomeLider,
      d.equipeNoCarro,
      d.veiculoPlaca,
      formatKm(distancia),
      formatValue(d.abastecimentoValor),
      formatValue(d.alimentacaoRefeicaoValor),
      formatValue(d.pedagioValor),
      formatValue(d.outrasDespesasValor),
      d.outrasDespesasDescricao,
      formatValue(custoTotal),
      d.localizacaoDestino
    ]);
  }

  return const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
}

Future<String> _generateCsvConsolidadoInIsolate(_CsvConsolidadoPayload payload) async {
  List<List<dynamic>> rows = [];
  final nf = NumberFormat("#,##0.00", "pt_BR");
  final nfKm = NumberFormat("#,##0.0", "pt_BR");

  rows.add([
    'Data_Relatorio', 'Lider_Equipe', 'Ajudantes', 'Projeto', 'Atividade', 'Fazenda', 'Talhao',
    'Tipo_Coleta', 'ID_Amostra', 'Indicador_Amostra', 'Total_Amostras', 'Indicador_Cubagem', 'Total_Cubagens',
    'Status_Coleta', 'UP_RF', 'KM_Inicial', 'KM_Final', 'Total_KM', 'Destino',
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
  
  for (var pMap in payload.parcelasMap) {
    final p = Parcela.fromMap(pMap);
    final talhao = talhoes[p.talhaoId];
    final atividade = atividades[talhao?.fazendaAtividadeId];
    final projeto = projetos[atividade?.projetoId];
    final totaisAmostras = payload.totaisAmostrasPorTalhao[p.talhaoId] ?? 0;
    final totaisCubagens = payload.totaisCubagensPorTalhao[p.talhaoId] ?? 0;

    rows.add([
      DateFormat('dd/MM/yyyy').format(DateTime.parse(diario.dataRelatorio)),
      diario.nomeLider,
      diario.equipeNoCarro,
      projeto?.nome,
      atividade?.tipo,
      p.nomeFazenda,
      p.nomeTalhao,
      'Inventario',
      p.idParcela,
      1,
      totaisAmostras,
      0,
      totaisCubagens,
      p.status.name,
      p.up,
      formatValue(diario.kmInicial),
      formatValue(diario.kmFinal),
      formatKm(distancia),
      diario.localizacaoDestino,
      formatValue(diario.pedagioValor),
      formatValue(diario.abastecimentoValor),
      diario.alimentacaoMarmitasQtd,
      formatValue(diario.alimentacaoRefeicaoValor),
      formatValue(totalGastos),
      diario.alimentacaoDescricao,
      diario.veiculoPlaca,
      diario.veiculoModelo
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
      DateFormat('dd/MM/yyyy').format(DateTime.parse(diario.dataRelatorio)),
      diario.nomeLider,
      diario.equipeNoCarro,
      projeto?.nome,
      atividade?.tipo,
      c.nomeFazenda,
      c.nomeTalhao,
      'Cubagem',
      c.identificador,
      0,
      totaisAmostras,
      1,
      totaisCubagens,
      c.alturaTotal > 0 ? 'concluida' : 'pendente',
      c.rf,
      formatValue(diario.kmInicial),
      formatValue(diario.kmFinal),
      formatKm(distancia),
      diario.localizacaoDestino,
      formatValue(diario.pedagioValor),
      formatValue(diario.abastecimentoValor),
      diario.alimentacaoMarmitasQtd,
      formatValue(diario.alimentacaoRefeicaoValor),
      formatValue(totalGastos),
      diario.alimentacaoDescricao,
      diario.veiculoPlaca,
      diario.veiculoModelo
    ]);
  }

  return const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
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
        projetosMap: projetosMap,
        atividadesMap: atividadesMap,
        talhoesMap: talhoesMap,
        totaisAmostrasPorTalhao: totaisAmostrasPorTalhao,
        totaisCubagensPorTalhao: totaisCubagensPorTalhao,
      );

      final String csvData = await compute(_generateCsvConsolidadoInIsolate, payload);
      
      final nomeLiderFmt = diario.nomeLider.replaceAll(RegExp(r'\s+'), '_');
      final dataFmt = diario.dataRelatorio;
      final fName = 'relatorio_consolidado_${nomeLiderFmt}_${dataFmt}.csv';
      
      await _salvarECompartilharCsv(context, csvData, fName, 'Relatório Consolidado - GeoForest');

    } catch (e, s) {
      _handleExportError(context, 'exportar relatório consolidado', e, s);
    } finally {
      if(context.mounted) ProgressDialog.hide(context);
    }
  }

  Future<void> exportarOperacoesCsv({
    required BuildContext context,
    required List<DiarioDeCampo> diarios,
    required String tipoRelatorio,
  }) async {
    if (diarios.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nenhum dado de diário para exportar.'),
          backgroundColor: Colors.orange,
        ));
      }
      return;
    }
    
    try {
      if (!await _requestPermission(context)) return;
      ProgressDialog.show(context, 'Gerando CSV de Operações...');

      final payload = _CsvOperacoesPayload(
        diariosMap: diarios.map((d) => d.toMap()).toList(),
      );

      final String csvData = await compute(_generateCsvOperacoesInIsolate, payload);
      
      final dataFmt = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final fName = 'relatorio_operacoes_${tipoRelatorio}_${dataFmt}.csv';
      
      await _salvarECompartilharCsv(context, csvData, fName, 'Relatório de Operações - GeoForest');

    } catch (e, s) {
      _handleExportError(context, 'exportar relatório de operações', e, s);
    } finally {
      if(context.mounted) ProgressDialog.hide(context);
    }
  }
  
  Future<void> exportarDiarioDeCampoCsv({required BuildContext context, required DiarioDeCampo diario}) async {
    try {
      if (!await _requestPermission(context)) return;

      final nf = NumberFormat("0.00", "pt_BR");
      final projeto = await _projetoRepository.getProjetoById(diario.projetoId);
      final talhao = diario.talhaoId != null ? await _talhaoRepository.getTalhaoById(diario.talhaoId!) : null;

      List<List<dynamic>> rows = [
        ['Campo', 'Valor'],
        ['Data do Relatório', diario.dataRelatorio],
        ['Líder da Equipe', diario.nomeLider],
        ['Equipe Completa', diario.equipeNoCarro],
        ['Projeto (Referência)', projeto?.nome ?? 'N/A'],
        ['Fazenda (Referência)', talhao?.fazendaNome ?? 'N/A'],
        ['Talhão (Referência)', talhao?.nome ?? 'N/A'],
        ['Placa do Veículo', diario.veiculoPlaca],
        ['Modelo do Veículo', diario.veiculoModelo],
        ['KM Inicial', diario.kmInicial != null ? nf.format(diario.kmInicial) : ''],
        ['KM Final', diario.kmFinal != null ? nf.format(diario.kmFinal) : ''],
        ['Destino', diario.localizacaoDestino],
        ['Pedágio (R\$)', diario.pedagioValor != null ? nf.format(diario.pedagioValor) : ''],
        ['Abastecimento (R\$)', diario.abastecimentoValor != null ? nf.format(diario.abastecimentoValor) : ''],
        ['Qtd. Marmitas', diario.alimentacaoMarmitasQtd],
        ['Valor Refeição (R\$)', diario.alimentacaoRefeicaoValor != null ? nf.format(diario.alimentacaoRefeicaoValor) : ''],
        ['Descrição Alimentação', diario.alimentacaoDescricao],
        ['Outras Despesas (R\$)', diario.outrasDespesasValor != null ? nf.format(diario.outrasDespesasValor) : ''],
        ['Descrição Outras Despesas', diario.outrasDespesasDescricao],
      ];

      final csvData = const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
      final nomeLiderFormatado = diario.nomeLider.replaceAll(RegExp(r'\s+'), '_');
      final dataFormatada = diario.dataRelatorio;
      final fName = 'diario_de_campo_${nomeLiderFormatado}_${dataFormatada}.csv';
      
      await _salvarECompartilharCsv(context, csvData, fName, 'Diário de Campo - GeoForest');

    } catch (e, s) {
      _handleExportError(context, 'exportar diário de campo', e, s);
    }
  }
  
  Future<void> exportarDesenvolvimentoEquipes(BuildContext context, {Set<int>? projetoIdsFiltrados}) async {
    try {
      if (!await _requestPermission(context)) return;
      
      ProgressDialog.show(context, 'Gerando relatório detalhado...');

      final todosProjetos = await _projetoRepository.getTodosOsProjetosParaGerente();
      final projetos = (projetoIdsFiltrados == null || projetoIdsFiltrados.isEmpty)
          ? todosProjetos
          : todosProjetos.where((p) => projetoIdsFiltrados.contains(p.id!)).toList();
      
      if (projetos.isEmpty) {
        ProgressDialog.hide(context);
        if(context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum projeto encontrado para o filtro selecionado.'), backgroundColor: Colors.orange));
        }
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

      final todasAsParcelas = await _parcelaRepository.getTodasAsParcelas();
      final parcelasFiltradas = todasAsParcelas.where((p) => talhoesMap.containsKey(p.talhaoId));

      for (final parcela in parcelasFiltradas) {
        if (parcela.talhaoId == null) continue;
        final talhao = talhoesMap[parcela.talhaoId];
        if (talhao == null) continue;
        final atividade = atividadesMap[talhao.fazendaAtividadeId];
        if (atividade == null) continue;
        final projeto = projetosMap[atividade.projetoId];
        if (projeto == null) continue;

        final arvores = await _parcelaRepository.getArvoresDaParcela(parcela.dbId!);
        
        final covas = <String>{};
        for (var a in arvores) { covas.add('${a.linha}-${a.posicaoNaLinha}'); }
        
        final fustes = arvores.where((a) => a.codigo != Codigo.Falha && a.codigo != Codigo.Caida).length;
        final falhas = arvores.where((a) => a.codigo == Codigo.Falha).length;
        final codigosEspeciais = arvores.where((a) => 
            a.codigo != Codigo.Normal && a.codigo != Codigo.Falha && a.codigo != Codigo.Caida
        ).length;

        allColetasData.add({
          'projeto_nome': projeto.nome,
          'atividade_tipo': atividade.tipo,
          'fazenda_nome': parcela.nomeFazenda,
          'talhao_nome': parcela.nomeTalhao,
          'id_coleta': parcela.idParcela,
          'talhao_area_ha': talhao.areaHa,
          'situacao': parcela.exportada ? 'Exportada' : parcela.status.name,
          'data_alteracao': parcela.dataColeta?.toIso8601String(),
          'responsavel': parcela.nomeLider,
          'latitude': parcela.latitude,
          'longitude': parcela.longitude,
          'parcela_area_m2': parcela.areaMetrosQuadrados,
          'parcela_lado1_m': parcela.lado1,
          'parcela_lado2_m': parcela.lado2,
          'parcela_observacao': parcela.observacao,
          'total_fustes': fustes,
          'total_covas': covas.length,
          'total_falhas': falhas,
          'total_codigos_especiais': codigosEspeciais,
          'cubagem_classe': null,
          'cubagem_cap': null,
          'cubagem_altura': null,
        });
      }

      final todasAsCubagens = await _cubagemRepository.getTodasCubagens();
      final cubagensFiltradas = todasAsCubagens.where((c) => talhoesMap.containsKey(c.talhaoId));

      for (final cubagem in cubagensFiltradas) {
        if (cubagem.talhaoId == null) continue;
        final talhao = talhoesMap[cubagem.talhaoId];
        if (talhao == null) continue;
        final atividade = atividadesMap[talhao.fazendaAtividadeId];
        if (atividade == null) continue;
        final projeto = projetosMap[atividade.projetoId];
        if (projeto == null) continue;

        allColetasData.add({
          'projeto_nome': projeto.nome,
          'atividade_tipo': atividade.tipo,
          'fazenda_nome': cubagem.nomeFazenda,
          'talhao_nome': cubagem.nomeTalhao,
          'id_coleta': cubagem.identificador,
          'id_unico_amostra': null,
          'talhao_area_ha': talhao.areaHa,
          'situacao': cubagem.exportada ? 'Exportada' : (cubagem.alturaTotal > 0 ? 'Concluida' : 'Pendente'),
          'data_alteracao': null, 
          'responsavel': cubagem.nomeLider,
          'latitude': null, 'longitude': null,
          'parcela_area_m2': null,
          'parcela_lado1_m': null,
          'parcela_lado2_m': null,
          'parcela_observacao': null,
          'total_fustes': 1,
          'total_covas': 1,
          'total_falhas': 0,
          'total_codigos_especiais': 0,
          'cubagem_classe': cubagem.classe,
          'cubagem_cap': cubagem.valorCAP,
          'cubagem_altura': cubagem.alturaTotal,
        });
      }
      
      if(allColetasData.isEmpty) {
        ProgressDialog.hide(context);
        if(context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma coleta encontrada para os filtros selecionados.'), backgroundColor: Colors.orange));
        }
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final payload = _DevEquipePayload(
        coletasData: allColetasData,
        nomeZona: prefs.getString('zona_utm_selecionada') ?? 'SIRGAS 2000 / UTM Zona 22S',
        proj4Defs: proj4Definitions,
      );

      final String csvData = await compute(_generateDevEquipeCsvInIsolate, payload);
      
      final fName = 'relatorio_desenvolvimento_equipes_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.csv';
      
      await _salvarECompartilharCsv(context, csvData, fName, 'Relatório de Desenvolvimento de Equipes - GeoForest');

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
    final String fName = 'geoforest_export_${nomeArquivoColetor}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv';
    
    final path = await _gerarCsvParcela(parcelas, fName);
    
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
    
    final String fName = 'geoforest_MEU_BACKUP_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.csv';
    final path = await _gerarCsvParcela(parcelas, fName);
    
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
        builder: (dialogContext) => ManagerExportDialog(
          isBackup: isBackup,
          projetosDisponiveis: todosProjetos,
          lideresDisponiveis: todosLideres,
        ),
      );

      if (result != null && context.mounted) {
        _executarExportacaoGerente(context, result);
      }
    }
  }

  Future<void> _executarExportacaoGerente(BuildContext context, ExportFilters filters) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Buscando dados com base nos filtros...')));
    
    List<Parcela> parcelasParaExportar;
    if (filters.isBackup) {
      parcelasParaExportar = await _parcelaRepository.getTodasConcluidasParcelasFiltrado(
        projetoIds: filters.selectedProjetoIds.isNotEmpty ? filters.selectedProjetoIds : null,
        lideresNomes: filters.selectedLideres.isNotEmpty ? filters.selectedLideres : null,
      );
    } else {
      parcelasParaExportar = await _parcelaRepository.getUnexportedConcludedParcelasFiltrado(
        projetoIds: filters.selectedProjetoIds.isNotEmpty ? filters.selectedProjetoIds : null,
        lideresNomes: filters.selectedLideres.isNotEmpty ? filters.selectedLideres : null,
      );
    }
    
    if (parcelasParaExportar.isEmpty && context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma parcela encontrada para os filtros selecionados.')));
      return;
    }

    final tipo = filters.isBackup ? "BACKUP_GERENTE" : "EXPORT_GERENTE";
    final String fName = 'geoforest_${tipo}_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.csv';
    final path = await _gerarCsvParcela(parcelasParaExportar, fName);

    if (context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      await Share.shareXFiles([XFile(path)], subject: 'Exportação do Gerente - GeoForest');
      if (!filters.isBackup) {
        final idsParaMarcar = parcelasParaExportar.map((p) => p.dbId).whereType<int>().toList();
        await _parcelaRepository.marcarParcelasComoExportadas(idsParaMarcar);
      }
    }
  }
  
  Future<String> _gerarCsvParcela(List<Parcela> parcelas, String nomeArquivo) async {
    final Map<int, List<Map<String, dynamic>>> arvoresPorParcelaMap = {};
    final Set<int> talhaoIds = parcelas.map((p) => p.talhaoId).whereType<int>().toSet();
    final Map<int, Map<String, dynamic>> talhoesMapParaIsolate = {};

    for (final talhaoId in talhaoIds) {
      final talhao = await _talhaoRepository.getTalhaoById(talhaoId);
      if (talhao != null) {
        talhoesMapParaIsolate[talhaoId] = talhao.toMap();
      }
    }
    
    for (final parcela in parcelas) {
      if (parcela.dbId != null) {
        final arvores = await _parcelaRepository.getArvoresDaParcela(parcela.dbId!);
        arvoresPorParcelaMap[parcela.dbId!] = arvores.map((a) => a.toMap()).toList();
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final payload = _CsvParcelaPayload(
      parcelasMap: parcelas.map((p) => p.toMap()).toList(),
      arvoresPorParcelaMap: arvoresPorParcelaMap,
      talhoesMap: talhoesMapParaIsolate,
      nomeLider: prefs.getString('nome_lider') ?? 'N/A',
      nomesAjudantes: prefs.getString('nomes_ajudantes') ?? 'N/A',
      nomeZona: prefs.getString('zona_utm_selecionada') ?? 'SIRGAS 2000 / UTM Zona 22S',
      proj4Defs: proj4Definitions,
    );

    final String csvData = await compute(_generateCsvParcelaDataInIsolate, payload);
    
    return await _salvarEObterCaminho(csvData, nomeArquivo);
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
        final nomeArquivo = 'geoforest_export_cubagens_$hoje.csv';
        await _gerarCsvCubagem(context, cubagensConcluidas, nomeArquivo, true);
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
        final nomeArquivo = 'geoforest_BACKUP_CUBAGENS_$hoje.csv';
        await _gerarCsvCubagem(context, cubagensConcluidas, nomeArquivo, false);
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
        builder: (dialogContext) => ManagerExportDialog(
          isBackup: isBackup,
          projetosDisponiveis: todosProjetos,
          lideresDisponiveis: todosLideres,
        ),
      );

      if (result != null && context.mounted) {
        await _executarExportacaoGerenteCubagem(context, result);
      }
    }
  }

  Future<void> _executarExportacaoGerenteCubagem(BuildContext context, ExportFilters filters) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Buscando cubagens com base nos filtros...')));
    
    final List<CubagemArvore> cubagensParaExportar = await _cubagemRepository.getConcludedCubagensFiltrado(
      projetoIds: filters.selectedProjetoIds.isNotEmpty ? filters.selectedProjetoIds : null,
      lideresNomes: filters.selectedLideres.isNotEmpty ? filters.selectedLideres : null,
    );
    
    if (cubagensParaExportar.isEmpty && context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma cubagem encontrada para os filtros selecionados.')));
      return;
    }

    final tipo = filters.isBackup ? "BACKUP_CUBAGEM_GERENTE" : "EXPORT_CUBAGEM_GERENTE";
    final String fName = 'geoforest_${tipo}_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.csv';
    
    await _gerarCsvCubagem(context, cubagensParaExportar, fName, !filters.isBackup);
  }

  Future<void> _gerarCsvCubagem(BuildContext context, List<CubagemArvore> cubagens, String nomeArquivoOuCaminhoCompleto, bool marcarComoExportado) async {
    if (cubagens.isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma cubagem encontrada para exportar.'), backgroundColor: Colors.orange));
      return;
    }
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gerando CSV de cubagens em segundo plano...')));

    final Set<int> talhaoIds = cubagens.map((c) => c.talhaoId).whereType<int>().toSet();
    final Map<int, Map<String, dynamic>> talhoesMapParaIsolate = {};
    for (final talhaoId in talhaoIds) {
      final talhao = await _talhaoRepository.getTalhaoById(talhaoId);
      if (talhao != null) {
        talhoesMapParaIsolate[talhaoId] = talhao.toMap();
      }
    }

    final Map<int, List<Map<String, dynamic>>> secoesPorCubagemMap = {};
    for (final cubagem in cubagens) {
      if (cubagem.id != null) {
        final secoes = await _cubagemRepository.getSecoesPorArvoreId(cubagem.id!);
        secoesPorCubagemMap[cubagem.id!] = secoes.map((s) => s.toMap()).toList();
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
    );
    final String csvData = await compute(_generateCsvCubagemDataInIsolate, payload);
    
    String path;
    if (nomeArquivoOuCaminhoCompleto.contains('/')) {
        path = nomeArquivoOuCaminhoCompleto;
    } else {
        path = await _salvarEObterCaminho(csvData, nomeArquivoOuCaminhoCompleto);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      await Share.shareXFiles([XFile(path)], subject: 'Exportação de Cubagens GeoForest');
      if (marcarComoExportado) {
        final idsParaMarcar = cubagens.map((c) => c.id).whereType<int>().toList();
        await _cubagemRepository.marcarCubagensComoExportadas(idsParaMarcar);
      }
    }
  }

  Future<void> exportarAnaliseTalhaoCsv({
    required BuildContext context,
    required Talhao talhao,
    required TalhaoAnalysisResult analise,
  }) async {
    try {
      if (!await _requestPermission(context)) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gerando arquivo CSV...')));
      
      final nf1 = NumberFormat("0.0", "pt_BR");
      final nf2 = NumberFormat("0.00", "pt_BR");
      final nf4 = NumberFormat("0.0000", "pt_BR");

      List<List<dynamic>> rows = [];
      rows.add(['Resumo do Talhão']);
      rows.add(['Métrica', 'Valor']);
      rows.add(['Fazenda', talhao.fazendaNome ?? 'N/A']);
      rows.add(['Talhão', talhao.nome]);
      rows.add(['Nº de Parcelas Amostradas', analise.totalParcelasAmostradas]);
      rows.add(['Nº de Árvores Medidas', analise.totalArvoresAmostradas]);
      rows.add(['Área Total Amostrada (ha)', nf4.format(analise.areaTotalAmostradaHa)]);
      rows.add(['']);
      rows.add(['Resultados por Hectare']);
      rows.add(['Métrica', 'Valor']);
      rows.add(['Árvores / ha', analise.arvoresPorHectare]);
      rows.add(['Área Basal (G) m²/ha', nf2.format(analise.areaBasalPorHectare)]);
      rows.add(['Volume Estimado m³/ha', nf2.format(analise.volumePorHectare)]);
      rows.add(['']);
      rows.add(['Estatísticas da Amostra']);
      rows.add(['Métrica', 'Valor']);
      rows.add(['CAP Médio (cm)', nf1.format(analise.mediaCap)]);
      rows.add(['Altura Média (m)', nf1.format(analise.mediaAltura)]);
      rows.add(['']);
      rows.add(['Distribuição Diamétrica (CAP)']);
      rows.add(['Classe (cm)', 'Nº de Árvores', '%']);
      
      final totalArvoresVivas = analise.distribuicaoDiametrica.values.fold(0, (a, b) => a + b);
      analise.distribuicaoDiametrica.forEach((pontoMedio, contagem) {
        final inicioClasse = pontoMedio - 2.5;
        final fimClasse = pontoMedio + 2.5 - 0.1;
        final porcentagem = totalArvoresVivas > 0 ? (contagem / totalArvoresVivas) * 100 : 0;
        rows.add(['${nf1.format(inicioClasse)} - ${nf1.format(fimClasse)}', contagem, '${nf1.format(porcentagem)}%']);
      });

      final hoje = DateTime.now();
      final fName = 'analise_talhao_${talhao.nome.replaceAll(' ', '_')}_${DateFormat('yyyy-MM-dd_HH-mm').format(hoje)}.csv';
      final csvData = const ListToCsvConverter(fieldDelimiter: ';').convert(rows);

      await _salvarECompartilharCsv(context, csvData, fName, 'Análise do Talhão ${talhao.nome}');

    } catch (e, s) {
      _handleExportError(context, 'exportar análise', e, s);
    }
  }
  
  Future<void> exportarPlanoDeAmostragem({
    required BuildContext context,
    required List<int> parcelaIds,
  }) async {
    if (parcelaIds.isEmpty) {
      if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum plano de amostragem para exportar.'), backgroundColor: Colors.orange));
      return;
    }
    ProgressDialog.show(context, 'Gerando GeoJSON...');
    
    try {
      final List<Map<String, dynamic>> features = [];
      String nomeProjetoFinal = 'PlanoAmostragem';

      final allParcelas = (await Future.wait(parcelaIds.map((id) => _parcelaRepository.getParcelaById(id)))).whereType<Parcela>().toList();
      final talhaoIds = allParcelas.map((p) => p.talhaoId).whereType<int>().toSet();
      final allTalhoes = <int, Talhao>{};
      for(final talhaoId in talhaoIds){
        final talhao = await _talhaoRepository.getTalhaoById(talhaoId);
        if(talhao != null){
          allTalhoes[talhaoId] = talhao;
        }
      }
      if (allParcelas.isNotEmpty) {
        final projeto = await _projetoRepository.getProjetoPelaParcela(allParcelas.first);
        if(projeto != null) {
          nomeProjetoFinal = projeto.nome;
        }
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
              'atividade': parcela.atividadeTipo ?? 'N/A', 
              'bloco': talhao?.bloco,
              'fazenda_nome': parcela.nomeFazenda,         
              'fazenda_id': parcela.idFazenda,           
              'rf': parcela.up,
              'talhao_nome': parcela.nomeTalhao,          
              'parcela': parcela.idParcela,
              'area_talhao_ha': talhao?.areaHa,           
              'especie': talhao?.especie,
              'material': talhao?.materialGenetico,
              'espacamento': talhao?.espacamento,
              'plantio': talhao?.dataPlantio,
              'regime': null,
              'lado1': parcela.lado1,
              'lado2': parcela.lado2,
              'area_parcela_m2': parcela.areaMetrosQuadrados, 
              'tipo': parcela.tipoParcela,
              'ciclo': parcela.ciclo,
              'rotacao': parcela.rotacao,
              'situacao': null,
              'medir_?': 'SIM',                             
              'status': parcela.status.name,
              'data_realizacao': parcela.status == StatusParcela.concluida ? DateFormat('dd/MM/yyyy').format(parcela.dataColeta!) : null,
              'observacao': parcela.observacao,
              'zona_utm': zonaUtmStr,                        
              'long_x': pUtm.x.toStringAsFixed(0),          
              'lat_y': pUtm.y.toStringAsFixed(0),           
              'alt_z': parcela.altitude,                    
            }
          });
        }
      }

      final Map<String, dynamic> geoJson = {'type': 'FeatureCollection', 'features': features};
      const jsonEncoder = JsonEncoder.withIndent('  ');
      final jsonString = jsonEncoder.convert(geoJson);

      final hoje = DateTime.now();
      final fName = 'Plano_Amostragem_${nomeProjetoFinal.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd_HHmm').format(hoje)}.json';
      
      await _salvarECompartilhar(
        context: context, 
        fileContent: jsonString, 
        fileName: fName, 
        subject: 'Plano de Amostragem GeoForest'
      );

    } catch (e, s) {
      _handleExportError(context, 'exportar plano de amostragem', e, s);
    } finally {
      ProgressDialog.hide(context);
    }
  }

  Future<void> exportarTudoComoZip({
    required BuildContext context,
    required List<Talhao> talhoes,
  }) async {
    if (talhoes.isEmpty) return;
    try {
      if (!await _requestPermission(context)) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Iniciando exportação completa...'), duration: Duration(seconds: 20)));

      final directory = await getApplicationDocumentsDirectory();
      final hoje = DateTime.now();
      final nomePasta = 'Exportacao_Completa_${DateFormat('yyyy-MM-dd_HH-mm').format(hoje)}';
      final pastaDeExportacao = Directory('${directory.path}/$nomePasta');

      if (await pastaDeExportacao.exists()) {
        await pastaDeExportacao.delete(recursive: true);
      }
      await pastaDeExportacao.create(recursive: true);

      await _gerarCsvParcelasParaZip(context, talhoes, '${pastaDeExportacao.path}/parcelas_coletadas.csv');
      await _gerarCsvCubagensParaZip(context, talhoes, '${pastaDeExportacao.path}/cubagens_realizadas.csv');

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
    if (todasAsParcelas.isNotEmpty) {
      await _gerarCsvParcela(todasAsParcelas, filePath);
    }
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
    if (todasAsCubagens.isNotEmpty) {
      await _gerarCsvCubagem(context, todasAsCubagens, outputPath, false);
    }
  }

  Future<bool> _requestPermission(BuildContext context) async {
    final permissionService = PermissionService();
    final hasPermission = await permissionService.requestStoragePermission();
    if (!hasPermission && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permissão de acesso ao armazenamento negada.'), backgroundColor: Colors.red));
    }
    return hasPermission;
  }

  void _handleExportError(BuildContext context, String action, Object e, StackTrace s) {
    debugPrint('Erro ao $action: $e\n$s');
    if (context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Falha ao $action: ${e.toString()}'),
          backgroundColor: Colors.red));
    }
  }

  Future<String> _salvarEObterCaminho(String fileContent, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$fileName';
    final bom = [0xEF, 0xBB, 0xBF]; 
    final bytes = utf8.encode(fileContent);
    await File(path).writeAsBytes(fileName.endsWith('.csv') ? [...bom, ...bytes] : bytes);
    return path;
  }
  
  Future<void> _salvarECompartilhar({
    required BuildContext context,
    required String fileContent,
    required String fileName,
    required String subject,
  }) async {
      final path = await _salvarEObterCaminho(fileContent, fileName);
      if (context.mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        await Share.shareXFiles([XFile(path, name: fileName)], subject: subject);
      }
  }

  Future<void> _salvarECompartilharCsv(BuildContext context, String csvData, String fileName, String subject) async {
    await _salvarECompartilhar(
      context: context, 
      fileContent: csvData, 
      fileName: fileName, 
      subject: subject
    );
  }
}
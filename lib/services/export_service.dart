// lib/services/export_service.dart (VERSÃO COMPLETA COM EXPORTAÇÃO ENRIQUECIDA)

import 'dart:io';
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
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

// PAYLOADS ATUALIZADOS PARA INCLUIR DADOS DOS TALHÕES
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

  _CsvCubagemPayload({
    required this.cubagensMap,
    required this.secoesPorCubagemMap,
    required this.talhoesMap,
    required this.nomeLider,
    required this.nomesAjudantes,
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

// FUNÇÃO ISOLATE ATUALIZADA PARA PARCELAS
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

  List<List<dynamic>> rows = [];
  // CABEÇALHO ATUALIZADO
  rows.add(['Atividade', 'Lider_Equipe', 'Ajudantes', 'ID_Db_Parcela', 'Codigo_Fazenda', 'Fazenda', 'Talhao', 'Area_Talhao_ha', 'Especie', 'Espacamento', 'Idade_Anos', 'ID_Coleta_Parcela', 'Area_m2', 'Largura_m', 'Comprimento_m', 'Raio_m', 'Observacao_Parcela', 'Easting', 'Northing', 'Data_Coleta', 'Status_Parcela', 'Linha', 'Posicao_na_Linha', 'Fuste_Num', 'Codigo_Arvore', 'Codigo_Arvore_2', 'CAP_cm', 'Altura_m', 'Dominante']);
  
  for (var pMap in payload.parcelasMap) {
    final p = Parcela.fromMap(pMap);
    final talhaoData = payload.talhoesMap[p.talhaoId] ?? {};
    
    String easting = '', northing = '';
    if (p.latitude != null && p.longitude != null) {
      var pUtm = projWGS84.transform(projUTM, proj4.Point(x: p.longitude!, y: p.latitude!));
      easting = pUtm.x.toStringAsFixed(2);
      northing = pUtm.y.toStringAsFixed(2);
    }
    
    final arvoresMap = payload.arvoresPorParcelaMap[p.dbId] ?? [];
    final arvores = arvoresMap.map((aMap) => Arvore.fromMap(aMap)).toList();

    final liderDaColeta = p.nomeLider ?? payload.nomeLider;
    if (arvores.isEmpty) {
      rows.add([p.atividadeTipo ?? 'IPC', liderDaColeta, payload.nomesAjudantes, p.dbId, p.idFazenda, p.nomeFazenda, p.nomeTalhao, talhaoData['areaHa'], talhaoData['especie'], talhaoData['espacamento'], talhaoData['idadeAnos'], p.idParcela, p.areaMetrosQuadrados, p.largura, p.comprimento, p.raio, p.observacao, easting, northing, p.dataColeta?.toIso8601String(), p.status.name, null, null, null, null, null, null, null, null]);
    } else {
      Map<String, int> fusteCounter = {};
      for (final a in arvores) {
        String key = '${a.linha}-${a.posicaoNaLinha}';
        fusteCounter[key] = (fusteCounter[key] ?? 0) + 1;
        rows.add([p.atividadeTipo ?? 'IPC', liderDaColeta, payload.nomesAjudantes, p.dbId, p.idFazenda, p.nomeFazenda, p.nomeTalhao, talhaoData['areaHa'], talhaoData['especie'], talhaoData['espacamento'], talhaoData['idadeAnos'], p.idParcela, p.areaMetrosQuadrados, p.largura, p.comprimento, p.raio, p.observacao, easting, northing, p.dataColeta?.toIso8601String(), p.status.name, a.linha, a.posicaoNaLinha, fusteCounter[key], a.codigo.name, a.codigo2?.name, a.cap, a.altura, a.dominante ? 'Sim' : 'Não']);
      }
    }
  }
  return const ListToCsvConverter().convert(rows);
}

// FUNÇÃO ISOLATE ATUALIZADA PARA CUBAGEM
Future<String> _generateCsvCubagemDataInIsolate(_CsvCubagemPayload payload) async {
  List<List<dynamic>> rows = [];
  // CABEÇALHO ATUALIZADO
  rows.add(['Atividade', 'Lider_Equipe', 'Ajudantes', 'id_db_arvore', 'id_fazenda', 'fazenda', 'talhao', 'area_talhao_ha', 'especie', 'espacamento', 'idade_anos', 'identificador_arvore', 'classe', 'altura_total_m', 'tipo_medida_cap', 'valor_cap', 'altura_base_m', 'altura_medicao_secao_m', 'circunferencia_secao_cm', 'casca1_mm', 'casca2_mm', 'dsc_cm']);
  for (var cMap in payload.cubagensMap) {
    final arvore = CubagemArvore.fromMap(cMap);
    final talhaoData = payload.talhoesMap[arvore.talhaoId] ?? {};

    final secoesMap = payload.secoesPorCubagemMap[arvore.id] ?? [];
    final secoes = secoesMap.map((sMap) => CubagemSecao.fromMap(sMap)).toList();
    
    final liderDaColeta = arvore.nomeLider ?? payload.nomeLider;
    if (secoes.isEmpty) {
      rows.add(['CUB', liderDaColeta, payload.nomesAjudantes, arvore.id, arvore.idFazenda, arvore.nomeFazenda, arvore.nomeTalhao, talhaoData['areaHa'], talhaoData['especie'], talhaoData['espacamento'], talhaoData['idadeAnos'], arvore.identificador, arvore.classe, arvore.alturaTotal, arvore.tipoMedidaCAP, arvore.valorCAP, arvore.alturaBase, null, null, null, null, null]);
    } else {
      for (var secao in secoes) {
        rows.add(['CUB', liderDaColeta, payload.nomesAjudantes, arvore.id, arvore.idFazenda, arvore.nomeFazenda, arvore.nomeTalhao, talhaoData['areaHa'], talhaoData['especie'], talhaoData['espacamento'], talhaoData['idadeAnos'], arvore.identificador, arvore.classe, arvore.alturaTotal, arvore.tipoMedidaCAP, arvore.valorCAP, arvore.alturaBase, secao.alturaMedicao, secao.circunferencia, secao.casca1_mm, secao.casca2_mm, secao.diametroSemCasca.toStringAsFixed(2)]);
      }
    }
  }
  return const ListToCsvConverter().convert(rows);
}

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

  List<List<dynamic>> rows = [];
  rows.add([
    'Projeto', 'Atividade', 'Fazenda', 'Talhao', 'ID_Amostra_Coleta', 'Area_Talhao_ha',
    'Situacao', 'Data_Alteracao', 'Responsavel', 'Coord_X_UTM', 'Coord_Y_UTM', 'Area_Parcela_m2',
    'Largura_m', 'Comprimento_m', 'Observacao_Parcela', 'Total_Fustes', 'Total_Covas', 'Total_Falhas', 'Total_Codigos_Especiais'
  ]);

  for (final rowData in payload.coletasData) {
    String easting = '', northing = '';
    final lat = rowData['latitude'] as double?;
    final lon = rowData['longitude'] as double?;
    if (lat != null && lon != null) {
      var pUtm = projWGS84.transform(projUTM, proj4.Point(x: lon, y: lat));
      easting = pUtm.x.toStringAsFixed(2);
      northing = pUtm.y.toStringAsFixed(2);
    }
    
    rows.add([
      rowData['projeto_nome'],
      rowData['atividade_tipo'],
      rowData['fazenda_nome'],
      rowData['talhao_nome'],
      rowData['id_coleta'],
      rowData['talhao_area_ha'],
      rowData['situacao'],
      rowData['data_alteracao'],
      rowData['responsavel'],
      easting,
      northing,
      rowData['parcela_area_m2'],
      rowData['parcela_largura_m'],
      rowData['parcela_comprimento_m'],
      rowData['parcela_observacao'],
      rowData['total_fustes'],
      rowData['total_covas'],
      rowData['total_falhas'],
      rowData['total_codigos_especiais'],
    ]);
  }

  return const ListToCsvConverter().convert(rows);
}


class ExportService {
  final _parcelaRepository = ParcelaRepository();
  final _cubagemRepository = CubagemRepository();
  final _projetoRepository = ProjetoRepository();
  final _atividadeRepository = AtividadeRepository();
  final _talhaoRepository = TalhaoRepository();
  
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
        arvores.forEach((a) => covas.add('${a.linha}-${a.posicaoNaLinha}'));
        
        final fustes = arvores.where((a) => a.codigo != Codigo.falha && a.codigo != Codigo.caida).length;
        
        final falhas = arvores.where((a) => a.codigo == Codigo.falha).length;
        
        final codigosEspeciais = arvores.where((a) => 
            a.codigo != Codigo.normal && a.codigo != Codigo.falha && a.codigo != Codigo.caida
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
          'parcela_largura_m': parcela.largura,
          'parcela_comprimento_m': parcela.comprimento,
          'parcela_observacao': parcela.observacao,
          'total_fustes': fustes,
          'total_covas': covas.length,
          'total_falhas': falhas,
          'total_codigos_especiais': codigosEspeciais,
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
          'talhao_area_ha': talhao.areaHa,
          'situacao': cubagem.exportada ? 'Exportada' : (cubagem.alturaTotal > 0 ? 'Concluida' : 'Pendente'),
          'data_alteracao': null, 'responsavel': cubagem.nomeLider,
          'latitude': null, 'longitude': null, 'parcela_area_m2': null, 'parcela_largura_m': null, 'parcela_comprimento_m': null,
          'parcela_observacao': null, 'total_fustes': 1, 'total_covas': 1, 'total_falhas': 0, 'total_codigos_especiais': 0,
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
      
      final dir = await getApplicationDocumentsDirectory();
      final fName = 'relatorio_desenvolvimento_equipes_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.csv';
      final path = '${dir.path}/$fName';
      final bom = [0xEF, 0xBB, 0xBF];
      final bytes = utf8.encode(csvData);
      await File(path).writeAsBytes([...bom, ...bytes]);

      ProgressDialog.hide(context);
      if (context.mounted) {
        await Share.shareXFiles([XFile(path)], subject: 'Relatório de Desenvolvimento de Equipes - GeoForest');
      }

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

    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$nomeArquivo';
    final bom = [0xEF, 0xBB, 0xBF];
    final bytes = utf8.encode(csvData);
    await File(path).writeAsBytes([...bom, ...bytes]);
    return path;
  }
  
  Future<void> exportarNovasCubagens(BuildContext context) async {
    try {
      if (!await _requestPermission(context)) return;
      final cubagens = await _cubagemRepository.getUnexportedCubagens();
      final hoje = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final nomeArquivo = 'geoforest_export_cubagens_$hoje.csv';
      await _gerarCsvCubagem(context, cubagens, nomeArquivo, true);
    } catch (e, s) {
      _handleExportError(context, 'exportar cubagens', e, s);
    }
  }

  Future<void> exportarTodasCubagensBackup(BuildContext context) async {
    try {
      if (!await _requestPermission(context)) return;
      final cubagens = await _cubagemRepository.getTodasCubagensParaBackup();
      final hoje = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final nomeArquivo = 'geoforest_BACKUP_CUBAGENS_$hoje.csv';
      await _gerarCsvCubagem(context, cubagens, nomeArquivo, false);
    } catch (e, s) {
      _handleExportError(context, 'backup de cubagens', e, s);
    }
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
    final payload = _CsvCubagemPayload(
      cubagensMap: cubagens.map((c) => c.toMap()).toList(),
      secoesPorCubagemMap: secoesPorCubagemMap,
      talhoesMap: talhoesMapParaIsolate,
      nomeLider: teamProvider.lider ?? 'N/A',
      nomesAjudantes: teamProvider.ajudantes ?? 'N/A',
    );
    final String csvData = await compute(_generateCsvCubagemDataInIsolate, payload);
    
    String path;
    if (nomeArquivoOuCaminhoCompleto.contains('/')) {
        path = nomeArquivoOuCaminhoCompleto;
    } else {
        final dir = await getApplicationDocumentsDirectory();
        path = '${dir.path}/$nomeArquivoOuCaminhoCompleto';
    }
    
    final bom = [0xEF, 0xBB, 0xBF];
    final bytes = utf8.encode(csvData);
    await File(path).writeAsBytes([...bom, ...bytes]);

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
      List<List<dynamic>> rows = [];
      rows.add(['Resumo do Talhão']);
      rows.add(['Métrica', 'Valor']);
      rows.add(['Fazenda', talhao.fazendaNome ?? 'N/A']);
      rows.add(['Talhão', talhao.nome]);
      rows.add(['Nº de Parcelas Amostradas', analise.totalParcelasAmostradas]);
      rows.add(['Nº de Árvores Medidas', analise.totalArvoresAmostradas]);
      rows.add(['Área Total Amostrada (ha)', analise.areaTotalAmostradaHa.toStringAsFixed(4)]);
      rows.add(['']);
      rows.add(['Resultados por Hectare']);
      rows.add(['Métrica', 'Valor']);
      rows.add(['Árvores / ha', analise.arvoresPorHectare]);
      rows.add(['Área Basal (G) m²/ha', analise.areaBasalPorHectare.toStringAsFixed(2)]);
      rows.add(['Volume Estimado m³/ha', analise.volumePorHectare.toStringAsFixed(2)]);
      rows.add(['']);
      rows.add(['Estatísticas da Amostra']);
      rows.add(['Métrica', 'Valor']);
      rows.add(['CAP Médio (cm)', analise.mediaCap.toStringAsFixed(1)]);
      rows.add(['Altura Média (m)', analise.mediaAltura.toStringAsFixed(1)]);
      rows.add(['']);
      rows.add(['Distribuição Diamétrica (CAP)']);
      rows.add(['Classe (cm)', 'Nº de Árvores', '%']);
      final totalArvoresVivas = analise.distribuicaoDiametrica.values.fold(0, (a, b) => a + b);
      analise.distribuicaoDiametrica.forEach((pontoMedio, contagem) {
        final inicioClasse = pontoMedio - 2.5;
        final fimClasse = pontoMedio + 2.5 - 0.1;
        final porcentagem = totalArvoresVivas > 0 ? (contagem / totalArvoresVivas) * 100 : 0;
        rows.add(['${inicioClasse.toStringAsFixed(1)} - ${fimClasse.toStringAsFixed(1)}', contagem, '${porcentagem.toStringAsFixed(1)}%']);
      });
      final dir = await getApplicationDocumentsDirectory();
      final hoje = DateTime.now();
      final fName = 'analise_talhao_${talhao.nome.replaceAll(' ', '_')}_${DateFormat('yyyy-MM-dd_HH-mm').format(hoje)}.csv';
      final path = '${dir.path}/$fName';
      final csvData = const ListToCsvConverter().convert(rows);
      await File(path).writeAsString(csvData, encoding: utf8);
      if (context.mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        await Share.shareXFiles([XFile(path)], subject: 'Análise do Talhão ${talhao.nome}');
      }
    } catch (e, s) {
      _handleExportError(context, 'exportar análise', e, s);
    }
  }

  Future<void> exportarPlanoDeAmostragem({
    required BuildContext context,
    required List<int> parcelaIds,
  }) async {
    if (parcelaIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma amostra planejada para exportar.'), backgroundColor: Colors.orange));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preparando plano para exportação...')));
    
    try {
      final List<Map<String, dynamic>> features = [];
      String nomeProjeto = 'Plano';

      for (final id in parcelaIds) {
        final parcela = await _parcelaRepository.getParcelaById(id);
        if (parcela == null) continue;

        final projeto = await _projetoRepository.getProjetoPelaParcela(parcela);
        if (projeto != null && nomeProjeto == 'Plano') {
          nomeProjeto = projeto.nome;
        }
        
        if (parcela.latitude != null && parcela.longitude != null) {
          features.add({
            'type': 'Feature',
            'geometry': {'type': 'Point', 'coordinates': [parcela.longitude, parcela.latitude]},
            'properties': {
              'talhao': parcela.nomeTalhao, 'fazenda': parcela.nomeFazenda,
              'empresa': projeto?.empresa, 'municipio': 'N/I', 'area_m2': parcela.areaMetrosQuadrados,
              'projeto_nome': projeto?.nome, 'responsavel': projeto?.responsavel, 'fazenda_id': parcela.idFazenda,
              'parcela_id_plano': parcela.idParcela,
            }
          });
        }
      }

      final Map<String, dynamic> geoJson = {'type': 'FeatureCollection', 'features': features};
      const jsonEncoder = JsonEncoder.withIndent('  ');
      final jsonString = jsonEncoder.convert(geoJson);

      final directory = await getApplicationDocumentsDirectory();
      final hoje = DateTime.now();
      final fName = 'Plano_Amostragem_${nomeProjeto.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd_HHmm').format(hoje)}.json';
      final path = '${directory.path}/$fName';
      await File(path).writeAsString(jsonString);

      if (context.mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        await Share.shareXFiles([XFile(path, name: fName)], subject: 'Plano de Amostragem GeoForest');
      }
    } catch (e, s) {
      _handleExportError(context, 'exportar plano de amostragem', e, s);
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
}
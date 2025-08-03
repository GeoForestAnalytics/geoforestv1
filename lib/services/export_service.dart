// lib/services/export_service.dart (VERSÃO DEFINITIVA - COMPLETA E CORRIGIDA)

import 'dart:io';
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:provider/provider.dart';

import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/analise_result_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
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
import 'package:geoforestv1/utils/constants.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/widgets/manager_export_dialog.dart';
import 'package:geoforestv1/models/cubagem_secao_model.dart';

// --- PAYLOADS E FUNÇÕES PARA EXECUÇÃO EM BACKGROUND (COMPUTE) ---
class _CsvParcelaPayload {
  final List<Map<String, dynamic>> parcelasMap;
  final String nomeLider;
  final String nomesAjudantes;
  final String nomeZona;
  _CsvParcelaPayload({required this.parcelasMap, required this.nomeLider, required this.nomesAjudantes, required this.nomeZona});
}

class _CsvCubagemPayload {
  final List<Map<String, dynamic>> cubagensMap;
  final String nomeLider;
  final String nomesAjudantes;

  _CsvCubagemPayload({
    required this.cubagensMap,
    required this.nomeLider,
    required this.nomesAjudantes,
  });
}

void _initServicesForIsolate() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

Future<String> _generateCsvParcelaDataInIsolate(_CsvParcelaPayload payload) async {
  _initServicesForIsolate();
  final parcelaRepository = ParcelaRepository();
  final codigoEpsg = zonasUtmSirgas2000[payload.nomeZona] ?? 31982;
  
  try {
      proj4.Projection.get('EPSG:4326');
  } catch(_) {
      proj4.Projection.add('EPSG:4326', '+proj=longlat +datum=WGS84 +no_defs');
      proj4Definitions.forEach((epsg, def) {
        proj4.Projection.add('EPSG:$epsg', def);
      });
  }
  final projWGS84 = proj4.Projection.get('EPSG:4326')!;
  final projUTM = proj4.Projection.get('EPSG:$codigoEpsg')!;

  List<List<dynamic>> rows = [];
  rows.add(['Atividade', 'Lider_Equipe', 'Ajudantes', 'ID_Db_Parcela', 'Codigo_Fazenda', 'Fazenda', 'Talhao', 'ID_Coleta_Parcela', 'Area_m2', 'Largura_m', 'Comprimento_m', 'Raio_m', 'Observacao_Parcela', 'Easting', 'Northing', 'Data_Coleta', 'Status_Parcela', 'Linha', 'Posicao_na_Linha', 'Fuste_Num', 'Codigo_Arvore', 'Codigo_Arvore_2', 'CAP_cm', 'Altura_m', 'Dominante']);
  
  for (var pMap in payload.parcelasMap) {
    final p = Parcela.fromMap(pMap);
    String easting = '', northing = '';
    if (p.latitude != null && p.longitude != null) {
      var pUtm = projWGS84.transform(projUTM, proj4.Point(x: p.longitude!, y: p.latitude!));
      easting = pUtm.x.toStringAsFixed(2);
      northing = pUtm.y.toStringAsFixed(2);
    }
    
    List<Arvore> arvores = [];
    if (p.dbId != null) {
        arvores = await parcelaRepository.getArvoresDaParcela(p.dbId!);
    }

    final liderDaColeta = p.nomeLider ?? payload.nomeLider;
    if (arvores.isEmpty) {
      rows.add(['IPC', liderDaColeta, payload.nomesAjudantes, p.dbId, p.idFazenda, p.nomeFazenda, p.nomeTalhao, p.idParcela, p.areaMetrosQuadrados, p.largura, p.comprimento, p.raio, p.observacao, easting, northing, p.dataColeta?.toIso8601String(), p.status.name, null, null, null, null, null, null, null, null]);
    } else {
      Map<String, int> fusteCounter = {};
      for (final a in arvores) {
        String key = '${a.linha}-${a.posicaoNaLinha}';
        fusteCounter[key] = (fusteCounter[key] ?? 0) + 1;
        rows.add(['IPC', liderDaColeta, payload.nomesAjudantes, p.dbId, p.idFazenda, p.nomeFazenda, p.nomeTalhao, p.idParcela, p.areaMetrosQuadrados, p.largura, p.comprimento, p.raio, p.observacao, easting, northing, p.dataColeta?.toIso8601String(), p.status.name, a.linha, a.posicaoNaLinha, fusteCounter[key], a.codigo.name, a.codigo2?.name, a.cap, a.altura, a.dominante ? 'Sim' : 'Não']);
      }
    }
  }
  return const ListToCsvConverter().convert(rows);
}

Future<String> _generateCsvCubagemDataInIsolate(_CsvCubagemPayload payload) async {
  _initServicesForIsolate();
  final cubagemRepository = CubagemRepository();
  List<List<dynamic>> rows = [];
  rows.add(['Atividade', 'Lider_Equipe', 'Ajudantes', 'id_db_arvore', 'id_fazenda', 'fazenda', 'talhao', 'identificador_arvore', 'classe', 'altura_total_m', 'tipo_medida_cap', 'valor_cap', 'altura_base_m', 'altura_medicao_secao_m', 'circunferencia_secao_cm', 'casca1_mm', 'casca2_mm', 'dsc_cm']);
  for (var cMap in payload.cubagensMap) {
    final arvore = CubagemArvore.fromMap(cMap);
    
    List<CubagemSecao> secoes = [];
    if (arvore.id != null) {
      secoes = await cubagemRepository.getSecoesPorArvoreId(arvore.id!);
    }
    
    final liderDaColeta = arvore.nomeLider ?? payload.nomeLider;
    if (secoes.isEmpty) {
      rows.add(['CUB', liderDaColeta, payload.nomesAjudantes, arvore.id, arvore.idFazenda, arvore.nomeFazenda, arvore.nomeTalhao, arvore.identificador, arvore.classe, arvore.alturaTotal, arvore.tipoMedidaCAP, arvore.valorCAP, arvore.alturaBase, null, null, null, null, null]);
    } else {
      for (var secao in secoes) {
        rows.add(['CUB', liderDaColeta, payload.nomesAjudantes, arvore.id, arvore.idFazenda, arvore.nomeFazenda, arvore.nomeTalhao, arvore.identificador, arvore.classe, arvore.alturaTotal, arvore.tipoMedidaCAP, arvore.valorCAP, arvore.alturaBase, secao.alturaMedicao, secao.circunferencia, secao.casca1_mm, secao.casca2_mm, secao.diametroSemCasca.toStringAsFixed(2)]);
      }
    }
  }
  return const ListToCsvConverter().convert(rows);
}

class ExportService {
  final _parcelaRepository = ParcelaRepository();
  final _cubagemRepository = CubagemRepository();
  final _projetoRepository = ProjetoRepository();

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
      await _parcelaRepository.marcarParcelasComoExportadas(parcelas.map((p) => p.dbId!).toList());
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
    
    debugPrint("--- [DEBUG EXPORT GERENTE] ---");
    debugPrint("Modo Backup: ${filters.isBackup}");
    debugPrint("Projetos Selecionados (IDs): ${filters.selectedProjetoIds.isEmpty ? 'TODOS' : filters.selectedProjetoIds}");
    debugPrint("Líderes Selecionados: ${filters.selectedLideres.isEmpty ? 'TODOS' : filters.selectedLideres}");
    debugPrint("---------------------------------");

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
    
    debugPrint("[DEBUG EXPORT GERENTE] Parcelas encontradas no banco: ${parcelasParaExportar.length}");

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
        await _parcelaRepository.marcarParcelasComoExportadas(parcelasParaExportar.map((p) => p.dbId!).toList());
      }
    }
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

  Future<String> _gerarCsvParcela(List<Parcela> parcelas, String nomeArquivo) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _CsvParcelaPayload(
      parcelasMap: parcelas.map((p) => p.toMap()).toList(),
      nomeLider: prefs.getString('nome_lider') ?? 'N/A',
      nomesAjudantes: prefs.getString('nomes_ajudantes') ?? 'N/A',
      nomeZona: prefs.getString('zona_utm_selecionada') ?? 'SIRGAS 2000 / UTM Zona 22S',
    );
    final String csvData = await compute(_generateCsvParcelaDataInIsolate, payload);
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$nomeArquivo';
    await File(path).writeAsString(csvData);
    return path;
  }

  Future<void> _gerarCsvCubagem(BuildContext context, List<CubagemArvore> cubagens, String nomeArquivo, bool marcarComoExportado) async {
    if (cubagens.isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma cubagem encontrada para exportar.'), backgroundColor: Colors.orange));
      return;
    }
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gerando CSV de cubagens em segundo plano...')));

    final teamProvider = Provider.of<TeamProvider>(context, listen: false);

    final payload = _CsvCubagemPayload(
      cubagensMap: cubagens.map((c) => c.toMap()).toList(),
      nomeLider: teamProvider.lider ?? 'N/A',
      nomesAjudantes: teamProvider.ajudantes ?? 'N/A',
    );
    final String csvData = await compute(_generateCsvCubagemDataInIsolate, payload);

    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$nomeArquivo';
    await File(path).writeAsString(csvData);

    if (context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      await Share.shareXFiles([XFile(path)], subject: 'Exportação de Cubagens GeoForest');
      if (marcarComoExportado) {
        await _cubagemRepository.marcarCubagensComoExportadas(cubagens.map((c) => c.id!).toList());
      }
    }
  }

  Future<void> _gerarCsvParcelasParaZip(BuildContext context, List<Talhao> talhoes, String filePath) async {
    final List<Parcela> todasAsParcelas = [];
    for (final talhao in talhoes) {
      final parcelasDoTalhao = await _parcelaRepository.getParcelasDoTalhao(talhao.id!);
      todasAsParcelas.addAll(parcelasDoTalhao.where((p) => p.status == StatusParcela.concluida));
    }
    if (todasAsParcelas.isNotEmpty) {
      await _gerarCsvParcela(todasAsParcelas, filePath);
    }
  }

  Future<void> _gerarCsvCubagensParaZip(BuildContext context, List<Talhao> talhoes, String outputPath) async {
    final List<CubagemArvore> todasAsCubagens = [];
    for (final talhao in talhoes) {
      final cubagensDoTalhao = await _cubagemRepository.getTodasCubagensDoTalhao(talhao.id!);
      todasAsCubagens.addAll(cubagensDoTalhao.where((c) => c.alturaTotal > 0));
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
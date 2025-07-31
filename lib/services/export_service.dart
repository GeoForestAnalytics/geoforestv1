// lib/services/export_service.dart (VERSÃO COMPLETA E CORRIGIDA)

import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/models/analise_result_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/services/pdf_service.dart';
import 'package:geoforestv1/services/permission_service.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';

// --- NOVOS IMPORTS ---
import 'package:geoforestv1/data/datasources/local/database_helper.dart'; // Para queries complexas
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/utils/constants.dart'; // <-- IMPORTA O NOVO ARQUIVO DE CONSTANTES
// ---------------------

class ExportService {
  final _parcelaRepository = ParcelaRepository();
  final _cubagemRepository = CubagemRepository();
  final _dbHelper = DatabaseHelper.instance;
  final pdfService = PdfService(); 

  Future<void> exportarDados(BuildContext context) async {
    final permissionService = PermissionService();
    final bool hasPermission = await permissionService.requestStoragePermission();
    if (!hasPermission) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Permissão de acesso ao armazenamento negada.'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Buscando dados para exportação...')));

    try {
      final List<Parcela> parcelas = await _parcelaRepository.getUnexportedConcludedParcelas();

      if (parcelas.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Nenhuma parcela nova para exportar.'),
              backgroundColor: Colors.orange));
        }
        return;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Gerando arquivo CSV...')));
      }

      final prefs = await SharedPreferences.getInstance();
      final nomeLider = prefs.getString('nome_lider') ?? 'N/A';
      final nomesAjudantes = prefs.getString('nomes_ajudantes') ?? 'N/A';
      final nomeZona = prefs.getString('zona_utm_selecionada') ?? 'SIRGAS 2000 / UTM Zona 22S';
      
      // Usa a constante importada
      final codigoEpsg = zonasUtmSirgas2000[nomeZona]!;
      
      final projWGS84 = proj4.Projection.get('EPSG:4326')!;
      final projUTM = proj4.Projection.get('EPSG:$codigoEpsg')!;

      List<List<dynamic>> rows = [];
      rows.add([
        'Atividade', 'Lider_Equipe', 'Ajudantes', 'ID_Db_Parcela', 'Codigo_Fazenda', 'Fazenda', 'Talhao',
        'ID_Coleta_Parcela', 'Area_m2', 'Largura_m', 'Comprimento_m', 'Raio_m',
        'Observacao_Parcela', 'Easting', 'Northing', 'Data_Coleta',
        'Status_Parcela', 'Linha', 'Posicao_na_Linha', 'Fuste_Num',
        'Codigo_Arvore', 'Codigo_Arvore_2', 'CAP_cm', 'Altura_m', 'Dominante'
      ]);

      final List<int> idsParaMarcar = [];

      for (var p in parcelas) {
        idsParaMarcar.add(p.dbId!);
        String easting = '', northing = '';
        if (p.latitude != null && p.longitude != null) {
          var pUtm = projWGS84.transform(
              projUTM, proj4.Point(x: p.longitude!, y: p.latitude!));
          easting = pUtm.x.toStringAsFixed(2);
          northing = pUtm.y.toStringAsFixed(2);
        }

        final arvores = await _parcelaRepository.getArvoresDaParcela(p.dbId!);
        if (arvores.isEmpty) {
          rows.add([
            'IPC', nomeLider, nomesAjudantes, p.dbId, p.idFazenda, p.nomeFazenda, p.nomeTalhao,
            p.idParcela, p.areaMetrosQuadrados, p.largura, p.comprimento,
            p.raio, p.observacao, easting, northing,
            p.dataColeta?.toIso8601String(), p.status.name, null, null,
            null, null, null, null, null, null
          ]);
        } else {
          Map<String, int> fusteCounter = {};
          for (final a in arvores) {
            String key = '${a.linha}-${a.posicaoNaLinha}';
            fusteCounter[key] = (fusteCounter[key] ?? 0) + 1;
            rows.add([
              'IPC', nomeLider, nomesAjudantes, p.dbId, p.idFazenda, p.nomeFazenda, p.nomeTalhao,
              p.idParcela, p.areaMetrosQuadrados, p.largura, p.comprimento,
              p.raio, p.observacao, easting, northing,
              p.dataColeta?.toIso8601String(), p.status.name, a.linha,
              a.posicaoNaLinha, fusteCounter[key], a.codigo.name, a.codigo2?.name,
              a.cap, a.altura, a.dominante ? 'Sim' : 'Não'
            ]);
          }
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final hoje = DateTime.now();
      final pastaData = DateFormat('yyyy-MM-dd').format(hoje);
      final pastaDia = Directory('${dir.path}/$pastaData');
      if (!await pastaDia.exists()) await pastaDia.create(recursive: true);

      final fName = 'geoforest_export_coleta_${DateFormat('HH-mm-ss').format(hoje)}.csv';
      final path = '${pastaDia.path}/$fName';

      await File(path).writeAsString(const ListToCsvConverter().convert(rows));

      if (context.mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        await Share.shareXFiles([XFile(path)], subject: 'Exportação GeoForest - Coleta de Campo');
        await _parcelaRepository.marcarParcelasComoExportadas(idsParaMarcar);
      }
    } catch (e, s) {
      debugPrint('Erro na exportação de dados: $e\n$s');
      if (context.mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Falha na exportação: ${e.toString()}'),
            backgroundColor: Colors.red));
      }
    }
  }

  Future<void> exportarAnaliseTalhaoCsv({
    required BuildContext context,
    required Talhao talhao,
    required TalhaoAnalysisResult analise,
  }) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gerando arquivo CSV...')));

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
        rows.add([
          '${inicioClasse.toStringAsFixed(1)} - ${fimClasse.toStringAsFixed(1)}',
          contagem,
          '${porcentagem.toStringAsFixed(1)}%',
        ]);
      });

      final dir = await getApplicationDocumentsDirectory();
      final hoje = DateTime.now();
      final fName = 'analise_talhao_${talhao.nome}_${DateFormat('yyyy-MM-dd_HH-mm').format(hoje)}.csv';
      final path = '${dir.path}/$fName';

      final csvData = const ListToCsvConverter().convert(rows);
      await File(path).writeAsString(csvData, encoding: utf8);

      if (context.mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        await Share.shareXFiles([XFile(path)], subject: 'Análise do Talhão ${talhao.nome}');
      }
    } catch (e, s) {
      debugPrint('Erro ao exportar análise CSV: $e\n$s');
      if (context.mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Falha na exportação: ${e.toString()}'),
            backgroundColor: Colors.red));
      }
    }
  }

  Future<void> exportarTodasAsParcelasBackup(BuildContext context) async {
    final permissionService = PermissionService();

    final bool hasPermission = await permissionService.requestStoragePermission();
    if (!hasPermission) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Permissão de acesso ao armazenamento negada.'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Buscando dados para o backup completo...')));

    try {
      final List<Parcela> parcelas = await _parcelaRepository.getTodasAsParcelasConcluidasParaBackup();

      if (parcelas.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Nenhuma parcela concluída encontrada para o backup.'),
              backgroundColor: Colors.orange));
        }
        return;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gerando arquivo de backup...')));
      }

      final prefs = await SharedPreferences.getInstance();
      final nomeLider = prefs.getString('nome_lider') ?? 'N/A';
      final nomesAjudantes = prefs.getString('nomes_ajudantes') ?? 'N/A';
      final nomeZona = prefs.getString('zona_utm_selecionada') ?? 'SIRGAS 2000 / UTM Zona 22S';
      
      // Usa a constante importada
      final codigoEpsg = zonasUtmSirgas2000[nomeZona]!;

      final projWGS84 = proj4.Projection.get('EPSG:4326')!;
      final projUTM = proj4.Projection.get('EPSG:$codigoEpsg')!;

      List<List<dynamic>> rows = [];
      rows.add([
        'Atividade', 'Lider_Equipe', 'Ajudantes', 'ID_Db_Parcela', 'Codigo_Fazenda', 'Fazenda', 'Talhao',
        'ID_Coleta_Parcela', 'Area_m2', 'Largura_m', 'Comprimento_m', 'Raio_m',
        'Observacao_Parcela', 'Easting', 'Northing', 'Data_Coleta',
        'Status_Parcela', 'Linha', 'Posicao_na_Linha', 'Fuste_Num',
        'Codigo_Arvore', 'Codigo_Arvore_2', 'CAP_cm', 'Altura_m', 'Dominante'
      ]);

      for (var p in parcelas) {
        String easting = '', northing = '';
        if (p.latitude != null && p.longitude != null) {
          var pUtm = projWGS84.transform(
              projUTM, proj4.Point(x: p.longitude!, y: p.latitude!));
          easting = pUtm.x.toStringAsFixed(2);
          northing = pUtm.y.toStringAsFixed(2);
        }

        final arvores = await _parcelaRepository.getArvoresDaParcela(p.dbId!);
        if (arvores.isEmpty) {
          rows.add([
            'IPC', nomeLider, nomesAjudantes, p.dbId, p.idFazenda, p.nomeFazenda, p.nomeTalhao,
            p.idParcela, p.areaMetrosQuadrados, p.largura, p.comprimento,
            p.raio, p.observacao, easting, northing,
            p.dataColeta?.toIso8601String(), p.status.name, null, null,
            null, null, null, null, null, null
          ]);
        } else {
          Map<String, int> fusteCounter = {};
          for (final a in arvores) {
            String key = '${a.linha}-${a.posicaoNaLinha}';
            fusteCounter[key] = (fusteCounter[key] ?? 0) + 1;
            rows.add([
              'IPC', nomeLider, nomesAjudantes, p.dbId, p.idFazenda, p.nomeFazenda, p.nomeTalhao,
              p.idParcela, p.areaMetrosQuadrados, p.largura, p.comprimento,
              p.raio, p.observacao, easting, northing,
              p.dataColeta?.toIso8601String(), p.status.name, a.linha,
              a.posicaoNaLinha, fusteCounter[key], a.codigo.name, a.codigo2?.name,
              a.cap, a.altura, a.dominante ? 'Sim' : 'Não'
            ]);
          }
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final hoje = DateTime.now();
      final pastaData = DateFormat('yyyy-MM-dd').format(hoje);
      final pastaDia = Directory('${dir.path}/$pastaData');
      if (!await pastaDia.exists()) await pastaDia.create(recursive: true);

      final fName = 'geoforest_BACKUP_COMPLETO_${DateFormat('HH-mm-ss').format(hoje)}.csv';
      final path = '${pastaDia.path}/$fName';

      await File(path).writeAsString(const ListToCsvConverter().convert(rows));

      if (context.mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        await Share.shareXFiles([XFile(path)], subject: 'Backup Completo GeoForest');
      }
    } catch (e, s) {
      debugPrint('Erro no backup completo: $e\n$s');
      if (context.mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Falha no backup: ${e.toString()}'),
            backgroundColor: Colors.red));
      }
    }
  }

  Future<void> exportarPlanoDeAmostragem({
    required BuildContext context,
    required List<int> parcelaIds,
  }) async {
    if (parcelaIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nenhuma amostra planejada para exportar.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preparando plano para exportação...')));
    
    String nomeProjeto = 'Plano';

    try {
      final db = await _dbHelper.database;
      final String whereClause = 'P.id IN (${List.filled(parcelaIds.length, '?').join(',')})';

      final List<Map<String, dynamic>> results = await db.rawQuery('''
        SELECT 
          P.*,
          T.nome as talhao, T.especie as especie, T.areaHa as area_ha, T.idadeAnos as idade_anos, T.espacamento as espacam,
          F.id as fazenda_id, F.nome as fazenda, F.municipio as municipio, F.estado as estado,
          PROJ.nome as projeto_nome, PROJ.empresa as empresa, PROJ.responsavel as responsavel
        FROM parcelas P
        LEFT JOIN talhoes T ON P.talhaoId = T.id
        LEFT JOIN fazendas F ON T.fazendaId = F.id AND T.fazendaAtividadeId = F.atividadeId
        LEFT JOIN atividades A ON F.atividadeId = A.id
        LEFT JOIN projetos PROJ ON A.projetoId = PROJ.id
        WHERE $whereClause
      ''', parcelaIds);

      if (results.isEmpty) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao buscar dados das parcelas.')));
        return;
      }

      nomeProjeto = results.first['projeto_nome'] ?? 'Plano_Sem_Nome';

      final List<Map<String, dynamic>> features = [];
      for (final row in results) {
        if (row['latitude'] != null && row['longitude'] != null) {
          features.add({
            'type': 'Feature',
            'geometry': {'type': 'Point', 'coordinates': [row['longitude'], row['latitude']]},
            'properties': {
              'talhao': row['talhao'], 'fazenda': row['fazenda'], 'area_ha': row['area_ha'],
              'idade_anos': row['idade_anos'], 'especie': row['especie'], 'espacam': row['espacam'],
              'empresa': row['empresa'], 'municipio': row['municipio'], 'area_m2': row['areaMetrosQuadrados'],
              'projeto_nome': row['projeto_nome'], 'responsavel': row['responsavel'], 'fazenda_id': row['fazenda_id'],
              'parcela_id_plano': row['idParcela'],
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
      debugPrint('Erro na exportação do plano de amostragem: $e\n$s');
      if (context.mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Falha na exportação do plano: ${e.toString()}'),
            backgroundColor: Colors.red));
      }
    }
  }

  Future<void> exportarTudoComoZip({
    required BuildContext context,
    required List<Talhao> talhoes,
  }) async {
    if (talhoes.isEmpty) return;

    final List<int> talhaoIds = talhoes.map((t) => t.id!).toList();

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Iniciando exportação completa...'),
      duration: Duration(seconds: 20),
    ));

    try {
      final directory = await getApplicationDocumentsDirectory();
      final hoje = DateTime.now();
      final nomePasta = 'Exportacao_Completa_${DateFormat('yyyy-MM-dd_HH-mm').format(hoje)}';
      final pastaDeExportacao = Directory('${directory.path}/$nomePasta');
      if (await pastaDeExportacao.exists()) {
        await pastaDeExportacao.delete(recursive: true);
      }
      await pastaDeExportacao.create(recursive: true);

      await _gerarCsvParcelas(talhaoIds, '${pastaDeExportacao.path}/parcelas_coletadas.csv');
      await _gerarCsvCubagens(talhaoIds, '${pastaDeExportacao.path}/cubagens_realizadas.csv');
      
      // await pdfService.gerarRelatorioUnificadoPdf(context: context, talhoes: talhoes);

      final zipFilePath = '${directory.path}/$nomePasta.zip';
      final zipFile = File(zipFilePath);

      await ZipFile.createFromDirectory(sourceDir: pastaDeExportacao, zipFile: zipFile, recurseSubDirs: true);

      if (context.mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        await Share.shareXFiles([XFile(zipFilePath)], subject: 'Exportação Completa - GeoForest');
      }
    } catch (e, s) {
      debugPrint('Erro ao criar arquivo ZIP: $e\n$s');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Falha ao gerar pacote de exportação: ${e.toString()}'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _gerarCsvParcelas(List<int> talhaoIds, String outputPath) async {
    final db = await _dbHelper.database;
    final String whereClause = 'talhaoId IN (${List.filled(talhaoIds.length, '?').join(',')}) AND status = ?';
    final List<dynamic> whereArgs = [...talhaoIds, StatusParcela.concluida.name];
    final List<Map<String, dynamic>> parcelasMaps = await db.query('parcelas', where: whereClause, whereArgs: whereArgs);

    if (parcelasMaps.isEmpty) return;

    List<List<dynamic>> rows = [];
    rows.add([
      'ID_Db_Parcela', 'Codigo_Fazenda', 'Fazenda', 'Talhao', 'ID_Coleta_Parcela', 'Area_m2', 
      'Linha', 'Posicao_na_Linha', 'Codigo_Arvore', 'CAP_cm', 'Altura_m', 'Dominante'
    ]);

    for (var pMap in parcelasMaps) {
      final arvores = await _parcelaRepository.getArvoresDaParcela(pMap['id'] as int);
      for (final a in arvores) {
        rows.add([
          pMap['id'], pMap['idFazenda'], pMap['nomeFazenda'], pMap['nomeTalhao'],
          pMap['idParcela'], pMap['areaMetrosQuadrados'],
          a.linha, a.posicaoNaLinha, a.codigo.name, a.cap, a.altura, a.dominante ? 'Sim' : 'Não'
        ]);
      }
    }
    await File(outputPath).writeAsString(const ListToCsvConverter().convert(rows));
  }

  Future<void> _gerarCsvCubagens(List<int> talhaoIds, String outputPath) async {
    final db = await _dbHelper.database;
    final String whereClause = 'talhaoId IN (${List.filled(talhaoIds.length, '?').join(',')})';
    final List<Map<String, dynamic>> arvoresMaps = await db.query('cubagens_arvores', where: whereClause, whereArgs: talhaoIds);

    if (arvoresMaps.isEmpty) return;

    List<List<dynamic>> rows = [];
    rows.add([
      'id_fazenda', 'fazenda', 'talhao', 'identificador_arvore', 'altura_total_m', 
      'cap_cm', 'altura_medicao_m', 'circunferencia_cm', 'casca1_mm', 'casca2_mm'
    ]);

    for (var aMap in arvoresMaps) {
      final secoes = await _cubagemRepository.getSecoesPorArvoreId(aMap['id'] as int);
      for (var s in secoes) {
        rows.add([
          aMap['id_fazenda'], aMap['nome_fazenda'], aMap['nome_talhao'], aMap['identificador'], 
          aMap['alturaTotal'], aMap['valorCAP'], s.alturaMedicao, s.circunferencia, s.casca1_mm, s.casca2_mm
        ]);
      }
    }
    await File(outputPath).writeAsString(const ListToCsvConverter().convert(rows));
  }
  
  Future<void> exportarNovasCubagens(BuildContext context) async {
    try {
      final cubagens = await _cubagemRepository.getUnexportedCubagens();
      final hoje = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final nomeArquivo = 'geoforest_export_cubagens_$hoje.csv';
      await _gerarCsvCubagem(context, cubagens, nomeArquivo, true);
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro ao exportar cubagens: $e'),
            backgroundColor: Colors.red));
    }
  }

  Future<void> exportarTodasCubagensBackup(BuildContext context) async {
    try {
      final cubagens = await _cubagemRepository.getTodasCubagensParaBackup();
      final hoje = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final nomeArquivo = 'geoforest_BACKUP_CUBAGENS_$hoje.csv';
      await _gerarCsvCubagem(context, cubagens, nomeArquivo, false);
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro no backup de cubagens: $e'),
            backgroundColor: Colors.red));
    }
  }

  Future<void> _gerarCsvCubagem(BuildContext context, List<CubagemArvore> cubagens, String nomeArquivo, bool marcarComoExportado) async {
    if (cubagens.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Nenhuma cubagem encontrada para exportar.'),
            backgroundColor: Colors.orange));
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Gerando CSV de cubagens...')));
    }

    List<List<dynamic>> rows = [];
    rows.add([
      'Atividade', 'id_db_arvore', 'id_fazenda', 'fazenda', 'talhao',
      'identificador_arvore', 'classe', 'altura_total_m', 'tipo_medida_cap',
      'valor_cap', 'altura_base_m', 'altura_medicao_secao_m',
      'circunferencia_secao_cm', 'casca1_mm', 'casca2_mm', 'dsc_cm'
    ]);

    final List<int> idsParaMarcar = [];

    for (var arvore in cubagens) {
      if (marcarComoExportado) {
        idsParaMarcar.add(arvore.id!);
      }
      final secoes = await _cubagemRepository.getSecoesPorArvoreId(arvore.id!);
      if (secoes.isEmpty) {
        rows.add([
          'CUB', arvore.id, arvore.idFazenda, arvore.nomeFazenda, arvore.nomeTalhao,
          arvore.identificador, arvore.classe, arvore.alturaTotal,
          arvore.tipoMedidaCAP, arvore.valorCAP, arvore.alturaBase,
          null, null, null, null, null
        ]);
      } else {
        for (var secao in secoes) {
          rows.add([
            'CUB', arvore.id, arvore.idFazenda, arvore.nomeFazenda, arvore.nomeTalhao,
            arvore.identificador, arvore.classe, arvore.alturaTotal,
            arvore.tipoMedidaCAP, arvore.valorCAP, arvore.alturaBase,
            secao.alturaMedicao, secao.circunferencia, secao.casca1_mm,
            secao.casca2_mm, secao.diametroSemCasca.toStringAsFixed(2)
          ]);
        }
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$nomeArquivo';

    await File(path).writeAsString(const ListToCsvConverter().convert(rows));

    if (context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      await Share.shareXFiles([XFile(path)], subject: 'Exportação de Cubagens GeoForest');
      if (marcarComoExportado) {
        await _cubagemRepository.marcarCubagensComoExportadas(idsParaMarcar);
      }
    }
  }
}
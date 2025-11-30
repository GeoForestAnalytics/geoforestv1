// lib/services/pdf_service.dart (VERSÃO CORRIGIDA FINAL)

import 'dart:io';
import 'package:collection/collection.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/data/repositories/analise_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/models/analise_result_model.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/models/enums.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/services/analysis_service.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_android/path_provider_android.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';

class PdfService {
  final _analiseRepository = AnaliseRepository();
  final _talhaoRepository = TalhaoRepository();

  //region Infraestrutura de PDF (Permissões e Salvamento)

  Future<bool> _requestPermission(BuildContext context) async {
    PermissionStatus status;
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 30) {
        status = await Permission.manageExternalStorage.request();
      } else {
        status = await Permission.storage.request();
      }
    } else {
      status = await Permission.storage.request();
    }

    if (status.isGranted) {
      return true;
    }

    if (context.mounted) {
      if (status.isPermanentlyDenied) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Permissão negada. Habilite o acesso nas configurações do app.'),
          duration: Duration(seconds: 5),
        ));
        await openAppSettings();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'A permissão de armazenamento é necessária para salvar arquivos.'),
          backgroundColor: Colors.red,
        ));
      }
    }
    return false;
  }

  Future<Directory?> _getDownloadsDirectory(BuildContext context) async {
    try {
      if (Platform.isAndroid) {
        final PathProviderAndroid provider = PathProviderAndroid();
        final String? path = await provider.getDownloadsPath();
        if (path != null) return Directory(path);
      }
      return await getApplicationDocumentsDirectory();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao encontrar pasta de Downloads: $e'),
          backgroundColor: Colors.red,
        ));
      }
      return null;
    }
  }

  Future<void> _salvarEAbriPdf(
      BuildContext context, pw.Document pdf, String nomeArquivo) async {
    try {
      if (!await _requestPermission(context)) return;

      final downloadsDirectory = await _getDownloadsDirectory(context);
      if (downloadsDirectory == null) return;

      final relatoriosDir =
          Directory('${downloadsDirectory.path}/GeoForest/Relatorios');
      if (!await relatoriosDir.exists()) {
        await relatoriosDir.create(recursive: true);
      }

      final path = '${relatoriosDir.path}/$nomeArquivo';
      final file = File(path);
      await file.writeAsBytes(await pdf.save());

      if (context.mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
                  title: const Text('Exportação Concluída'),
                  content: Text(
                      'O relatório foi salvo em: ${relatoriosDir.path}. Deseja abri-lo?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Fechar')),
                    FilledButton(
                        onPressed: () {
                          OpenFile.open(path);
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('Abrir Arquivo')),
                  ],
                ));
      }
    } catch (e) {
      debugPrint("Erro ao salvar/abrir PDF: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao gerar o PDF: $e')));
      }
    }
  }
  //endregion

  //region Geradores de Relatórios PDF

  Future<void> gerarRelatorioAnaliseTalhaoPdf({
    required BuildContext context,
    required Talhao talhao,
    required TalhaoAnalysisResult analise,
    required pw.ImageProvider graficoDispersaoImagem,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (pw.Context context) => _buildHeader(
            'Análise de Talhão', "${talhao.fazendaNome ?? 'N/A'} / ${talhao.nome}"),
        footer: (pw.Context context) => _buildFooter(),
        build: (pw.Context context) {
          final codeAnalysis = analise.analiseDeCodigos;
          return [
            pw.Text(
              'Relatório de Análise de Inventário',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
              textAlign: pw.TextAlign.center,
            ),
            pw.Divider(height: 20),
            _buildResumoTalhaoPdf(analise),
            if (codeAnalysis != null) ...[
                pw.SizedBox(height: 20),
                _buildComposicaoPovoamentoPdf(codeAnalysis),
                pw.SizedBox(height: 20),
                _buildTabelaEstatisticasCodigoPdf(codeAnalysis),
              ],
            pw.SizedBox(height: 20),
            _buildTabelaDistribuicaoPdf(analise),
            pw.SizedBox(height: 20),
            pw.Text('Gráfico de Dispersão CAP vs. Altura',
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
            pw.SizedBox(height: 10),
            pw.Center(child: pw.Image(graficoDispersaoImagem, width: 450)),
            _buildInsightsPdf("Alertas", analise.warnings, PdfColors.red100),
            _buildInsightsPdf("Insights", analise.insights, PdfColors.blue100),
            _buildInsightsPdf(
                "Recomendações", analise.recommendations, PdfColors.orange100),
          ];
        },
      ),
    );
    final nomeArquivo =
        'Analise_Talhao_${talhao.nome.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf';
    await _salvarEAbriPdf(context, pdf, nomeArquivo);
  }
 
  Future<void> gerarRelatorioDiarioConsolidadoPdf({
    required BuildContext context,
    required DiarioDeCampo diario,
    required List<Parcela> parcelas,
    required List<CubagemArvore> cubagens,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (pw.Context ctx) =>
            _buildHeader('Relatório Diário de Atividades', diario.nomeLider),
        footer: (pw.Context ctx) => _buildFooter(),
        build: (pw.Context ctx) {
          return [
            pw.Text(
              'Relatório Consolidado de ${DateFormat('dd/MM/yyyy').format(DateTime.parse(diario.dataRelatorio))}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
              textAlign: pw.TextAlign.center,
            ),
            pw.Divider(height: 20),
            _buildTabelaDiarioPdf(diario),
            pw.SizedBox(height: 20),
            _buildResumoColetasPdf(parcelas, cubagens),
            pw.SizedBox(height: 20),
            _buildDetalhesColetasPdf(parcelas, cubagens),
          ];
        },
      ),
    );

    final nomeLiderFmt = diario.nomeLider.replaceAll(RegExp(r'\\s+'), '_');
    final nomeArquivo =
        'Relatorio_Diario_${nomeLiderFmt}_${diario.dataRelatorio}.pdf';

    await _salvarEAbriPdf(context, pdf, nomeArquivo);
  }

  Future<void> gerarRelatorioVolumetricoPdf({
    required BuildContext context,
    required Map<String, dynamic> resultadoRegressao,
    required Map<String, dynamic> diagnosticoRegressao,
    required Map<String, dynamic> producaoInventario,
    required List<VolumePorSortimento> producaoSortimento,
    required List<VolumePorCodigo> volumePorCodigo,
  }) async {
    final pdf = pw.Document();
    final nomeTalhoes = producaoInventario['talhoes'] ?? 'Talhões Selecionados';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (pw.Context ctx) =>
            _buildHeader('Relatório Volumétrico', nomeTalhoes),
        footer: (pw.Context ctx) => _buildFooter(),
        build: (pw.Context ctx) {
          return [
            pw.Text(
              'Relatório de Análise Volumétrica Completa',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
              textAlign: pw.TextAlign.center,
            ),
            pw.Divider(height: 20),
            _buildTabelaEquacaoPdf(resultadoRegressao),
            pw.SizedBox(height: 10),
            _buildTabelaDiagnosticoPdf(diagnosticoRegressao),
            pw.SizedBox(height: 20),
            _buildTabelaProducaoPdf(producaoInventario),
            pw.SizedBox(height: 20),
            _buildTabelaSortimentoPdf(producaoInventario, producaoSortimento),
            pw.SizedBox(height: 20),
            _buildTabelaVolumePorCodigoPdf(volumePorCodigo),
          ];
        },
      ),
    );

    final nomeArquivo =
        'Analise_Volumetrica_${nomeTalhoes.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf';
    await _salvarEAbriPdf(context, pdf, nomeArquivo);
  }

  Future<void> gerarRelatorioUnificadoPdf({
    required BuildContext context,
    required List<Talhao> talhoes,
  }) async {
    if (talhoes.isEmpty) return;

    final analysisService = AnalysisService();
    final pdf = pw.Document();
    int talhoesProcessados = 0;

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Gerando relatório unificado...'),
      duration: Duration(seconds: 15),
    ));

    for (final talhao in talhoes) {
      final dadosAgregados =
          await _analiseRepository.getDadosAgregadosDoTalhao(talhao.id!);
      final parcelas = dadosAgregados['parcelas'] as List<Parcela>;
      final arvores = dadosAgregados['arvores'] as List<Arvore>;

      if (parcelas.isEmpty || arvores.isEmpty) {
        continue;
      }

      final analiseGeral = analysisService.getTalhaoInsights(talhao, parcelas, arvores);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          header: (pw.Context ctx) => _buildHeader(
              'Análise de Talhão', "${talhao.fazendaNome ?? 'N/A'} / ${talhao.nome}"),
          footer: (pw.Context ctx) => _buildFooter(),
          build: (pw.Context ctx) {
            final codeAnalysis = analiseGeral.analiseDeCodigos;
            
            return [
              _buildResumoTalhaoPdf(analiseGeral),
              
              if (codeAnalysis != null) ...[
                pw.SizedBox(height: 20),
                _buildComposicaoPovoamentoPdf(codeAnalysis),
                pw.SizedBox(height: 20),
                _buildTabelaEstatisticasCodigoPdf(codeAnalysis),
              ],
              
              pw.SizedBox(height: 20),
              pw.Text('Distribuição Diamétrica (CAP)',
                  style:
                      pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.SizedBox(height: 10),
              _buildTabelaDistribuicaoPdf(analiseGeral),
            ];
          },
        ),
      );
      talhoesProcessados++;
    }

    if (talhoesProcessados == 0 && context.mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nenhum talhão com dados para gerar relatório.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final hoje = DateTime.now();
    final nomeArquivo =
        'Relatorio_Comparativo_GeoForest_${DateFormat('yyyy-MM-dd_HH-mm').format(hoje)}.pdf';
    await _salvarEAbriPdf(context, pdf, nomeArquivo);
  }

  Future<void> gerarPdfUnificadoDePlanosDeCubagem({
    required BuildContext context,
    required Map<Talhao, Map<String, int>> planosPorTalhao,
    required MetricaDistribuicao metrica, // <<< PARÂMETRO ADICIONADO
  }) async {
    if (planosPorTalhao.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nenhum plano para gerar PDF.')));
      return;
    }

    final pdf = pw.Document();

    for (var entry in planosPorTalhao.entries) {
      final talhao = entry.key;
      final plano = entry.value;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          header: (pw.Context ctx) => _buildHeader('Plano de Cubagem',
              "${talhao.fazendaNome ?? 'N/A'} / ${talhao.nome}"),
          footer: (pw.Context ctx) => _buildFooter(),
          build: (pw.Context ctx) {
            return [
              pw.SizedBox(height: 20),
              pw.Text(
                'Plano de Cubagem Estratificada por Classe',
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
                textAlign: pw.TextAlign.center,
              ),
              pw.Divider(height: 20),
              _buildTabelaPlano(plano, metrica), // <<< PASSANDO A MÉTRICA
            ];
          },
        ),
      );
    }

    final hoje = DateTime.now();
    final nomeArquivo =
        'Planos_de_Cubagem_GeoForest_${DateFormat('yyyy-MM-dd_HH-mm').format(hoje)}.pdf';
    await _salvarEAbriPdf(context, pdf, nomeArquivo);
  }

  Future<void> gerarPdfDePlanoExistente({
    required BuildContext context,
    required Atividade atividade,
    required List<CubagemArvore> placeholders,
  }) async {
    if (placeholders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nenhum dado de plano encontrado para esta atividade.')));
      return;
    }

    final pdf = pw.Document();

    final grupoPorTalhao =
        groupBy(placeholders, (CubagemArvore c) => c.talhaoId);

    for (var talhaoId in grupoPorTalhao.keys) {
      final arvoresDoTalhao = grupoPorTalhao[talhaoId]!;
      final primeiroItem = arvoresDoTalhao.first;
      final talhao = await _talhaoRepository.getTalhaoById(talhaoId!);

      final plano = <String, int>{};
      for (var arvore in arvoresDoTalhao) {
        if (arvore.classe != null) {
          plano.update(arvore.classe!, (value) => value + 1,
              ifAbsent: () => 1);
        }
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          header: (pw.Context ctx) => _buildHeader(
              'Plano de Cubagem',
              "${talhao?.fazendaNome ?? primeiroItem.nomeFazenda} / ${talhao?.nome ?? primeiroItem.nomeTalhao}"),
          footer: (pw.Context ctx) => _buildFooter(),
          build: (pw.Context ctx) {
            return [
              pw.SizedBox(height: 20),
              pw.Text(
                'Plano de Cubagem Estratificada por Classe Diamétrica',
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
                textAlign: pw.TextAlign.center,
              ),
              pw.Divider(height: 20),
              // <<< CORREÇÃO APLICADA AQUI >>>
              // Adicionado o parâmetro 'metrica' que estava faltando, usando DAP como padrão.
              _buildTabelaPlano(plano, MetricaDistribuicao.dap),
            ];
          },
        ),
      );
    }

    final hoje = DateTime.now();
    final nomeArquivo =
        'Plano_de_Cubagem_Regerado_${DateFormat('yyyy-MM-dd_HH-mm').format(hoje)}.pdf';
    await _salvarEAbriPdf(context, pdf, nomeArquivo);
  }

  
  Future<void> gerarRelatorioSimulacaoPdf({
    required BuildContext context,
    required String nomeFazenda,
    required String nomeTalhao,
    required double intensidade,
    required TalhaoAnalysisResult analiseInicial,
    required TalhaoAnalysisResult resultadoSimulacao,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (pw.Context ctx) => _buildHeader(nomeFazenda, nomeTalhao),
        footer: (pw.Context ctx) => _buildFooter(),
        build: (pw.Context ctx) {
          return [
            pw.Text(
              'Relatório de Simulação de Desbaste',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Intensidade Aplicada: ${intensidade.toStringAsFixed(0)}%',
              style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
              textAlign: pw.TextAlign.center,
            ),
            pw.Divider(height: 20),
            _buildTabelaSimulacaoPdf(analiseInicial, resultadoSimulacao),
          ];
        },
      ),
    );

    final nomeArquivo =
        'Simulacao_Desbaste_${nomeTalhao.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf';
    await _salvarEAbriPdf(context, pdf, nomeArquivo);
  }

  //endregion

  //region Widgets Construtores para PDF (Builders)

  pw.Widget _buildHeader(String titulo, String subtitulo) {
    return pw.Container(
      alignment: pw.Alignment.centerLeft,
      margin: const pw.EdgeInsets.only(bottom: 20.0),
      padding: const pw.EdgeInsets.only(bottom: 8.0),
      decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey, width: 2))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(titulo,
                  style:
                      pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20)),
              pw.SizedBox(height: 5),
              pw.Text(subtitulo),
            ],
          ),
          pw.Text('Data: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  pw.Widget _buildFooter() {
    return pw.Center(
      child: pw.Text(
        'Documento gerado pelo Analista GeoForest',
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
      ),
    );
  }

  pw.Widget _buildResumoTalhaoPdf(TalhaoAnalysisResult result) {
    return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey),
          borderRadius: pw.BorderRadius.circular(5),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            _buildPdfStat(
                'Volume/ha', '${result.volumePorHectare.toStringAsFixed(1)} m³'),
            _buildPdfStat('Árvores/ha', result.arvoresPorHectare.toString()),
            _buildPdfStat('Área Basal',
                '${result.areaBasalPorHectare.toStringAsFixed(1)} m²'),
            if (result.alturaDominante > 0)
              _buildPdfStat('HD', '${result.alturaDominante.toStringAsFixed(1)} m'),
            if (result.indiceDeSitio > 0)
              _buildPdfStat('Sítio (7a)', result.indiceDeSitio.toStringAsFixed(1)),
          ],
        ));
  }

  pw.Widget _buildComposicaoPovoamentoPdf(CodeAnalysisResult codeAnalysis) {
    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Composição do Povoamento',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.Divider(height: 10),
          _buildPdfStatRow(
              'Total de Fustes Amostrados:', codeAnalysis.totalFustes.toString()),
          _buildPdfStatRow('Total de Covas Amostradas:',
              codeAnalysis.totalCovasAmostradas.toString()),
          if (codeAnalysis.totalCovasAmostradas > 0)
            _buildPdfStatRow('Covas Ocupadas (Sobrevivência):',
                '${codeAnalysis.totalCovasOcupadas} (${(codeAnalysis.totalCovasOcupadas / codeAnalysis.totalCovasAmostradas * 100).toStringAsFixed(1)}%)'),
        ]);
  }

  pw.Widget _buildTabelaDiarioPdf(DiarioDeCampo diario) {
    final nf = NumberFormat("#,##0.00", "pt_BR");
    final distancia = (diario.kmFinal ?? 0) - (diario.kmInicial ?? 0);

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Diário de Campo e Despesas',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
      pw.Divider(height: 10),
      pw.SizedBox(height: 5),
      pw.TableHelper.fromTextArray(
        cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        cellStyle: const pw.TextStyle(fontSize: 10),
        columnWidths: {
          0: const pw.FixedColumnWidth(120),
          1: const pw.FlexColumnWidth(),
        },
        cellAlignment: pw.Alignment.centerLeft,
        data: <List<String>>[
          ['Equipe Completa:', diario.equipeNoCarro ?? 'N/A'],
          [
            'Veículo:',
            '${diario.veiculoModelo ?? 'N/A'} - ${diario.veiculoPlaca ?? 'N/A'}'
          ],
          ['KM Inicial:', diario.kmInicial?.toString() ?? 'N/A'],
          ['KM Final:', diario.kmFinal?.toString() ?? 'N/A'],
          [
            'Distância Percorrida:',
            distancia > 0 ? '${distancia.toStringAsFixed(1)} km' : 'N/A'
          ],
          ['Destino:', diario.localizacaoDestino ?? 'N/A'],
          [
            'Pedágio (R\$):',
            diario.pedagioValor != null
                ? 'R\$ ${nf.format(diario.pedagioValor)}'
                : 'N/A'
          ],
          [
            'Abastecimento (R\$):',
            diario.abastecimentoValor != null
                ? 'R\$ ${nf.format(diario.abastecimentoValor)}'
                : 'N/A'
          ],
          [
            'Alimentação:',
            '${diario.alimentacaoMarmitasQtd ?? 0} marmitas. ${diario.alimentacaoDescricao ?? ''}'
          ],
          [
            'Outras Refeições (R\$):',
            diario.alimentacaoRefeicaoValor != null
                ? 'R\$ ${nf.format(diario.alimentacaoRefeicaoValor)}'
                : 'N/A'
          ],
          [
            'Outras Despesas (R\$):',
            diario.outrasDespesasValor != null
                ? 'R\$ ${nf.format(diario.outrasDespesasValor)}'
                : 'N/A'
          ],
          [
            'Descrição Outras Despesas:',
            diario.outrasDespesasDescricao ?? 'N/A'
          ],
        ],
        border: null,
      ),
    ]);
  }

  pw.Widget _buildResumoColetasPdf(
      List<Parcela> parcelas, List<CubagemArvore> cubagens) {
    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Resumo das Coletas',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.Divider(height: 10),
          pw.SizedBox(height: 5),
          pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildPdfStat('Parcelas (Inventário)', parcelas.length.toString()),
                _buildPdfStat('Árvores (Cubagem)', cubagens.length.toString()),
              ])
        ]);
  }

  pw.Widget _buildDetalhesColetasPdf(
      List<Parcela> parcelas, List<CubagemArvore> cubagens) {
    final allColetas = [...parcelas, ...cubagens];
    if (allColetas.isEmpty) return pw.Container();

    final grupoPorLocal = groupBy(allColetas, (item) {
      if (item is Parcela) {
        return '${item.projetoId}-${item.nomeFazenda}-${item.nomeTalhao}';
      }
      if (item is CubagemArvore) {
        return 'ProjetoDesconhecido-${item.nomeFazenda}-${item.nomeTalhao}';
      }
      return 'Desconhecido';
    });

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 10),
        pw.Text('Detalhes das Coletas por Local',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
        pw.Divider(height: 10),
        ...grupoPorLocal.entries.map((entry) {
          final localParts = entry.key.split('-');
          final nomeFazenda = localParts.length > 1 ? localParts[1] : 'N/A';
          final nomeTalhao = localParts.length > 2 ? localParts[2] : 'N/A';
          final coletas = entry.value;

          return pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('$nomeFazenda / $nomeTalhao',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 12)),
                  pw.TableHelper.fromTextArray(
                    cellPadding:
                        const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                    cellStyle: const pw.TextStyle(fontSize: 9),
                    headerStyle:
                        pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                    data: <List<String>>[
                      ['Tipo', 'ID Amostra', 'Status'],
                      ...coletas.map((item) {
                        if (item is Parcela) {
                          return ['Inventário', item.idParcela, item.status.name];
                        }
                        if (item is CubagemArvore) {
                          return [
                            'Cubagem',
                            item.identificador,
                            item.alturaTotal > 0 ? 'Concluída' : 'Pendente'
                          ];
                        }
                        return <String>[];
                      }).where((list) => list.isNotEmpty),
                    ],
                  ),
                ]),
          );
        }),
      ],
    );
  }

  pw.Widget _buildTabelaEquacaoPdf(Map<String, dynamic> resultadoRegressao) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Equação de Volume Gerada',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
      pw.Divider(color: PdfColors.grey, height: 10),
      pw.SizedBox(height: 5),
      pw.RichText(
        text: pw.TextSpan(children: [
          const pw.TextSpan(
              text: 'Equação: ', style: pw.TextStyle(color: PdfColors.grey)),
          pw.TextSpan(
              text: resultadoRegressao['equacao'],
              style: pw.TextStyle(font: pw.Font.courier())),
        ]),
      ),
      pw.SizedBox(height: 5),
      pw.Text(
          'Coeficiente (R²): ${(resultadoRegressao['R2'] as double).toStringAsFixed(4)}'),
      pw.Text('Nº de Amostras Usadas: ${resultadoRegressao['n_amostras']}'),
    ]);
  }

  pw.Widget _buildTabelaDiagnosticoPdf(Map<String, dynamic> diagnostico) {
    final pValue = diagnostico['shapiro_wilk_p_value'] as double?;
    String resultadoShapiro;
    PdfColor corShapiro;

    if (pValue == null) {
      resultadoShapiro = "N/A";
      corShapiro = PdfColors.grey;
    } else if (pValue > 0.05) {
      resultadoShapiro = "Aprovado (p > 0.05)";
      corShapiro = PdfColors.green;
    } else {
      resultadoShapiro = "Rejeitado (p <= 0.05)";
      corShapiro = PdfColors.red;
    }

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Diagnóstico do Modelo Estatístico',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
      pw.Divider(color: PdfColors.grey, height: 10),
      pw.SizedBox(height: 5),
      pw.TableHelper.fromTextArray(
        cellAlignment: pw.Alignment.centerLeft,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        data: <List<String>>[
          ['Métrica', 'Valor', 'Interpretação'],
          [
            'Erro Padrão Residual (Syx)',
            (diagnostico['syx'] as double).toStringAsFixed(4),
            'Dispersão média dos dados em torno da regressão.'
          ],
          [
            'Syx (%)',
            '${(diagnostico['syx_percent'] as double).toStringAsFixed(2)}%',
            'Erro padrão em termos percentuais (geralmente < 10% é bom).'
          ],
          [
            'Normalidade (Shapiro-Wilk)',
            resultadoShapiro,
            'Verifica se os erros do modelo são normalmente distribuídos.'
          ],
        ],
        cellStyle: const pw.TextStyle(fontSize: 10),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.5),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(2),
        },
        cellAlignments: {
          1: pw.Alignment.centerRight,
        },
        // =========================================================================
        // ========================== INÍCIO DA CORREÇÃO =========================
        // O erro ocorre porque a função cellDecoration não pode retornar 'null'.
        // Devemos retornar uma decoração vazia para as células que não queremos colorir.
        // =========================================================================
        cellDecoration: (index, data, rowNum) {
          if (rowNum == 3 && index == 1) { // Linha do Shapiro-Wilk, coluna do valor
            return pw.BoxDecoration(color: corShapiro.shade(0.2));
          }
          return const pw.BoxDecoration(); // Retorna uma decoração vazia em vez de null
        },
        // =========================================================================
        // =========================== FIM DA CORREÇÃO ===========================
        // =========================================================================
      ),
    ]);
  }

  pw.Widget _buildTabelaProducaoPdf(Map<String, dynamic> producaoInventario) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Totais do Inventário',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
      pw.Divider(color: PdfColors.grey, height: 10),
      pw.SizedBox(height: 5),
      pw.Text('Aplicado aos talhões: ${producaoInventario['talhoes']}'),
      pw.SizedBox(height: 10),
      pw.TableHelper.fromTextArray(
        cellAlignment: pw.Alignment.centerLeft,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        data: <List<String>>[
          ['Métrica', 'Valor'],
          [
            'Volume por Hectare',
            '${(producaoInventario['volume_ha'] as double).toStringAsFixed(2)} m³/ha'
          ],
          [
            'Árvores por Hectare',
            '${producaoInventario['arvores_ha']} árv/ha'
          ],
          [
            'Área Basal por Hectare',
            '${(producaoInventario['area_basal_ha'] as double).toStringAsFixed(2)} m²/ha'
          ],
          if ((producaoInventario['volume_total_lote'] as double) > 0)
            [
              'Volume Total para ${(producaoInventario['area_total_lote'] as double).toStringAsFixed(2)} ha',
              '${(producaoInventario['volume_total_lote'] as double).toStringAsFixed(2)} m³'
            ],
        ],
      ),
    ]);
  }

  pw.Widget _buildTabelaSortimentoPdf(Map<String, dynamic> producaoInventario,
      List<VolumePorSortimento> producaoSortimento) {
    if (producaoSortimento.isEmpty) {
      return pw.Text('Nenhuma produção por sortimento foi calculada.');
    }

    final List<List<String>> data = producaoSortimento.map((item) {
      return [
        item.nome,
        '${item.volumeHa.toStringAsFixed(2)} m³/ha',
        '${item.porcentagem.toStringAsFixed(1)}%'
      ];
    }).toList();

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Produção por Sortimento',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
      pw.Divider(color: PdfColors.grey, height: 10),
      pw.SizedBox(height: 5),
      pw.TableHelper.fromTextArray(
        headers: ['Classe', 'Volume por Hectare', '% do Total'],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        data: data,
        cellAlignment: pw.Alignment.centerLeft,
        cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
      ),
    ]);
  }

  pw.Widget _buildTabelaVolumePorCodigoPdf(List<VolumePorCodigo> data) {
    if (data.isEmpty) return pw.Container();

    final List<List<String>> rows = data.map((item) {
      return [
        item.codigo,
        '${item.volumeTotal.toStringAsFixed(2)} m³/ha',
        '${item.porcentagem.toStringAsFixed(1)}%'
      ];
    }).toList();

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Contribuição Volumétrica por Código',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
      pw.Divider(color: PdfColors.grey, height: 10),
      pw.SizedBox(height: 5),
      pw.TableHelper.fromTextArray(
        headers: ['Código', 'Volume por Hectare', '% do Total'],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        data: rows,
        cellAlignment: pw.Alignment.centerLeft,
        cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
      ),
    ]);
  }  

  pw.Widget _buildTabelaDistribuicaoPdf(TalhaoAnalysisResult analise) {
    final headers = ['Classe (CAP)', 'Nº de Árvores', '%'];
    final totalArvoresVivas =
        analise.distribuicaoDiametrica.values.fold(0, (a, b) => a + b);

    final data = analise.distribuicaoDiametrica.entries.map((entry) {
      final pontoMedio = entry.key;
      final contagem = entry.value;
      final inicioClasse = pontoMedio - 2.5;
      final fimClasse = pontoMedio + 2.5 - 0.1;
      final porcentagem =
          totalArvoresVivas > 0 ? (contagem / totalArvoresVivas) * 100 : 0;
      return [
        '${inicioClasse.toStringAsFixed(1)} - ${fimClasse.toStringAsFixed(1)}',
        contagem.toString(),
        '${porcentagem.toStringAsFixed(1)}%',
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle:
          pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
      cellAlignment: pw.Alignment.center,
      cellAlignments: {0: pw.Alignment.centerLeft},
    );
  }

   pw.Widget _buildTabelaPlano(Map<String, int> plano, MetricaDistribuicao metrica) {
  final String headerText = metrica == MetricaDistribuicao.cap
      ? 'Classe de CAP'
      : 'Classe Diamétrica (DAP)';

  final headers = [headerText, 'Nº de Árvores para Cubar'];

  if (plano.isEmpty) {
    return pw.Center(child: pw.Text("Nenhum dado para gerar o plano."));
  }

  final data =
      plano.entries.map((entry) => [entry.key, entry.value.toString()]).toList();
  final total = plano.values.fold(0, (a, b) => a + b);
  data.add(['Total', total.toString()]);

  // <<< INÍCIO DA CORREÇÃO >>>
  // Construindo a tabela manualmente para ter controle total sobre o estilo.
  return pw.Table(
    border: pw.TableBorder.all(),
    columnWidths: {
      0: const pw.FlexColumnWidth(2),
      1: const pw.FlexColumnWidth(1),
    },
    children: [
      // Linha do Cabeçalho
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
        children: headers
            .map((header) => pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(
                    header,
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                    textAlign: pw.TextAlign.center,
                  ),
                ))
            .toList(),
      ),
      // Linhas de Dados
      ...data.asMap().entries.map((entry) {
        final rowIndex = entry.key;
        final rowData = entry.value;
        final bool isLastRow = rowIndex == data.length - 1; // Verifica se é a linha "Total"

        return pw.TableRow(
          children: rowData.asMap().entries.map((cellEntry) {
            final colIndex = cellEntry.key;
            final cellText = cellEntry.value;
            return pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                cellText,
                // Alinha a segunda coluna (índice 1) ao centro
                textAlign: colIndex == 1 ? pw.TextAlign.center : pw.TextAlign.left,
                // Deixa a última linha (Total) em negrito
                style: isLastRow
                    ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                    : const pw.TextStyle(),
              ),
            );
          }).toList(),
        );
      }),
    ],
  );
  // <<< FIM DA CORREÇÃO >>>
}

  pw.Widget _buildTabelaSimulacaoPdf(
      TalhaoAnalysisResult antes, TalhaoAnalysisResult depois) {
    final headers = ['Parâmetro', 'Antes', 'Após'];

    final data = [
      [
        'Árvores/ha',
        antes.arvoresPorHectare.toString(),
        depois.arvoresPorHectare.toString()
      ],
      [
        'CAP Médio',
        '${antes.mediaCap.toStringAsFixed(1)} cm',
        '${depois.mediaCap.toStringAsFixed(1)} cm'
      ],
      [
        'Altura Média',
        '${antes.mediaAltura.toStringAsFixed(1)} m',
        '${depois.mediaAltura.toStringAsFixed(1)} m'
      ],
      [
        'Área Basal (G)',
        '${antes.areaBasalPorHectare.toStringAsFixed(2)} m²/ha',
        '${depois.areaBasalPorHectare.toStringAsFixed(2)} m²/ha'
      ],
      [
        'Volume',
        '${antes.volumePorHectare.toStringAsFixed(2)} m³/ha',
        '${depois.volumePorHectare.toStringAsFixed(2)} m³/ha'
      ],
    ];

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle:
          pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
      cellAlignment: pw.Alignment.center,
      cellAlignments: {0: pw.Alignment.centerLeft},
      cellStyle: const pw.TextStyle(fontSize: 11),
      border: pw.TableBorder.all(color: PdfColors.grey),
    );
  }

  pw.Widget _buildTabelaEstatisticasCodigoPdf(CodeAnalysisResult codeAnalysis) {
    final headers = [
      'Código',
      'Qtd.',
      'Média\nCAP',
      'Mediana\nCAP',
      'Moda\nCAP',
      'DP\nCAP',
      'Média\nAltura',
      'Mediana\nAltura',
      'Moda\nAltura',
      'DP\nAltura'
    ];

    final data = codeAnalysis.estatisticasPorCodigo.entries.map((entry) {
      final stats = entry.value;
      return [
        entry.key,
        codeAnalysis.contagemPorCodigo[entry.key]?.toString() ?? '0',
        stats.mediaCap.toStringAsFixed(1),
        stats.medianaCap.toStringAsFixed(1),
        stats.modaCap.toStringAsFixed(1),
        stats.desvioPadraoCap.toStringAsFixed(1),
        stats.mediaAltura.toStringAsFixed(1),
        stats.medianaAltura.toStringAsFixed(1),
        stats.modaAltura.toStringAsFixed(1),
        stats.desvioPadraoAltura.toStringAsFixed(1),
      ];
    }).toList();

    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Estatísticas por Código',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.SizedBox(height: 5),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: data,
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.center,
            cellAlignments: {0: pw.Alignment.centerLeft},
          ),
        ]);
  }

  pw.Widget _buildInsightsPdf(
      String title, List<String> items, PdfColor color) {
    if (items.isEmpty) return pw.SizedBox.shrink();
    return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                      color: color, borderRadius: pw.BorderRadius.circular(4)),
                  child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(title,
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 4),
                        ...items.map((item) => pw.Text('- $item',
                            style: const pw.TextStyle(fontSize: 10))),
                      ]))
            ]));
  }

  pw.Widget _buildPdfStatRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.0),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style:
                  const pw.TextStyle(color: PdfColors.grey800, fontSize: 10)),
          pw.Text(value,
              style:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }

  pw.Widget _buildPdfStat(String label, String value) {
    return pw.Column(children: [
      pw.Text(value,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
      pw.Text(label,
          style: const pw.TextStyle(color: PdfColors.grey, fontSize: 10)),
    ]);
  }
}
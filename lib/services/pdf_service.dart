// lib/services/pdf_service.dart (VERSÃO COMPLETA E CORRIGIDA)

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/arvore_model.dart';
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

import 'package:geoforestv1/models/analise_result_model.dart';


class PdfService {

  Future<bool> _requestPermission() async {
    Permission permission;
    if (Platform.isAndroid) {
      permission = Permission.manageExternalStorage;
    } else {
      permission = Permission.storage;
    }
    if (await permission.isGranted) return true;
    var result = await permission.request();
    return result == PermissionStatus.granted;
  }
  
  Future<Directory?> getDownloadsDirectory() async {
    if (Platform.isAndroid) {
      final PathProviderAndroid provider = PathProviderAndroid();
      final String? path = await provider.getDownloadsPath();
      if (path != null) return Directory(path);
      return null;
    }
    return await getApplicationDocumentsDirectory();
  }

  Future<void> _salvarEAbriPdf(BuildContext context, pw.Document pdf, String nomeArquivo) async {
    try {
      if (!await _requestPermission()) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permissão de armazenamento negada.'), backgroundColor: Colors.red));
        return;
      }
      final downloadsDirectory = await getDownloadsDirectory();
      if (downloadsDirectory == null) {
         if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível encontrar a pasta de Downloads.'), backgroundColor: Colors.red));
         return;
      }
      
      final relatoriosDir = Directory('${downloadsDirectory.path}/GeoForest/Relatorios');
      if (!await relatoriosDir.exists()) await relatoriosDir.create(recursive: true);
      
      final path = '${relatoriosDir.path}/$nomeArquivo';
      final file = File(path);
      await file.writeAsBytes(await pdf.save());

      if (context.mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        await showDialog(
          context: context, 
          builder: (ctx) => AlertDialog(
            title: const Text('Exportação Concluída'),
            content: Text('O relatório foi salvo em: ${relatoriosDir.path}. Deseja abri-lo?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fechar')),
              FilledButton(onPressed: (){
                OpenFile.open(path);
                Navigator.of(ctx).pop();
              }, child: const Text('Abrir Arquivo')),
            ],
          )
        );
      }
    } catch (e) {
      debugPrint("Erro ao salvar/abrir PDF: $e");
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao gerar o PDF: $e')));
    }
  }

  // --- FUNÇÕES PÚBLICAS DE GERAÇÃO DE PDF ---

  Future<void> gerarRelatorioVolumetricoPdf({
    required BuildContext context,
    required Map<String, dynamic> resultadoRegressao,
    required Map<String, dynamic> producaoInventario,
    required Map<String, dynamic> producaoSortimento,
  }) async {
    final pdf = pw.Document();
    final nomeTalhoes = producaoInventario['talhoes'] ?? 'Talhões Selecionados';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (pw.Context ctx) => _buildHeader('Relatório Volumétrico', nomeTalhoes),
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
            pw.SizedBox(height: 20),
            _buildTabelaProducaoPdf(producaoInventario),
            pw.SizedBox(height: 20),
            _buildTabelaSortimentoPdf(producaoInventario, producaoSortimento),
          ];
        },
      ),
    );

    final nomeArquivo = 'Analise_Volumetrica_${nomeTalhoes.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf';
    await _salvarEAbriPdf(context, pdf, nomeArquivo);
  }
  
  Future<void> gerarRelatorioUnificadoPdf({
    required BuildContext context,
    required List<Talhao> talhoes,
  }) async {
    if (talhoes.isEmpty) return;
    
    final analysisService = AnalysisService();
    final dbHelper = DatabaseHelper.instance;
    final pdf = pw.Document(); 
    int talhoesProcessados = 0;

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Gerando relatório unificado...'),
      duration: Duration(seconds: 15),
    ));

    for (final talhao in talhoes) {
      final dadosAgregados = await dbHelper.getDadosAgregadosDoTalhao(talhao.id!);
      final parcelas = dadosAgregados['parcelas'] as List<Parcela>;
      final arvores = dadosAgregados['arvores'] as List<Arvore>;

      if (parcelas.isEmpty || arvores.isEmpty) {
        continue;
      }
      
      final analiseGeral = analysisService.getTalhaoInsights(parcelas, arvores);
      
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          header: (pw.Context ctx) => _buildHeader('Análise de Talhão', "${talhao.fazendaNome ?? 'N/A'} / ${talhao.nome}"),
          footer: (pw.Context ctx) => _buildFooter(),
          build: (pw.Context ctx) {
            return [
              _buildTabelaProducaoPdf({
                  'talhoes': talhao.nome,
                  'volume_ha': analiseGeral.volumePorHectare,
                  'arvores_ha': analiseGeral.arvoresPorHectare,
                  'area_basal_ha': analiseGeral.areaBasalPorHectare,
                  'volume_total_lote': (talhao.areaHa != null && talhao.areaHa! > 0) ? analiseGeral.volumePorHectare * talhao.areaHa! : 0.0,
                  'area_total_lote': talhao.areaHa ?? 0.0,
              }),
              pw.SizedBox(height: 20),
              pw.Text('Distribuição Diamétrica (CAP)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
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
    final nomeArquivo = 'Relatorio_Comparativo_GeoForest_${DateFormat('yyyy-MM-dd_HH-mm').format(hoje)}.pdf';
    await _salvarEAbriPdf(context, pdf, nomeArquivo);
  }

  Future<void> gerarPdfUnificadoDePlanosDeCubagem({
    required BuildContext context,
    required Map<Talhao, Map<String, int>> planosPorTalhao,
  }) async {
    if (planosPorTalhao.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum plano para gerar PDF.')));
      return;
    }

    final pdf = pw.Document();

    for (var entry in planosPorTalhao.entries) {
      final talhao = entry.key;
      final plano = entry.value;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          header: (pw.Context ctx) => _buildHeader('Plano de Cubagem', "${talhao.fazendaNome ?? 'N/A'} / ${talhao.nome}"),
          footer: (pw.Context ctx) => _buildFooter(),
          build: (pw.Context ctx) {
            return [
              pw.SizedBox(height: 20),
              pw.Text(
                'Plano de Cubagem Estratificada por Classe Diamétrica',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
                textAlign: pw.TextAlign.center,
              ),
              pw.Divider(height: 20),
              _buildTabelaPlano(plano),
            ];
          },
        ),
      );
    }
    
    final hoje = DateTime.now();
    final nomeArquivo = 'Planos_de_Cubagem_GeoForest_${DateFormat('yyyy-MM-dd_HH-mm').format(hoje)}.pdf';
    await _salvarEAbriPdf(context, pdf, nomeArquivo);
  }
  
  Future<void> gerarRelatorioRendimentoPdf({
    required BuildContext context,
    required String nomeFazenda,
    required String nomeTalhao,
    required List<RendimentoDAP> dadosRendimento,
    required TalhaoAnalysisResult analiseGeral,
    required pw.ImageProvider graficoImagem,
  }) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (pw.Context context) => _buildHeader(nomeFazenda, nomeTalhao),
        footer: (pw.Context context) => _buildFooter(),
        build: (pw.Context context) {
          return [
            pw.Text(
              'Relatório de Rendimento Comercial por Classe Diamétrica',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
              textAlign: pw.TextAlign.center,
            ),
            pw.Divider(height: 20),
            _buildResumoTalhaoPdf(analiseGeral),
            pw.SizedBox(height: 20),
            pw.Center(
              child: pw.SizedBox(
                width: 400,
                child: pw.Image(graficoImagem),
              ),
            ),
            pw.SizedBox(height: 20),
            _buildTabelaRendimentoPdf(dadosRendimento),
          ];
        },
      ),
    );
    final nomeArquivo =
        'relatorio_rendimento_${nomeTalhao.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf';
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

    final nomeArquivo = 'Simulacao_Desbaste_${nomeTalhao.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf';
    await _salvarEAbriPdf(context, pdf, nomeArquivo);
  }

  // --- WIDGETS AUXILIARES PARA CONSTRUÇÃO DE PDF ---

  pw.Widget _buildHeader(String titulo, String subtitulo) {
    return pw.Container(
      alignment: pw.Alignment.centerLeft,
      margin: const pw.EdgeInsets.only(bottom: 20.0),
      padding: const pw.EdgeInsets.only(bottom: 8.0),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey, width: 2))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(titulo, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20)),
              pw.SizedBox(height: 5),
              pw.Text(subtitulo),
            ],
          ),
          pw.Text('Data: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 12)),
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
  
  // <<< FUNÇÃO RESTAURADA >>>
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
            _buildPdfStat(
                'Área Basal', '${result.areaBasalPorHectare.toStringAsFixed(1)} m²'),
          ],
        ));
  }

  pw.Widget _buildPdfStat(String label, String value) {
    return pw.Column(children: [
      pw.Text(value,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
      pw.Text(label,
          style: const pw.TextStyle(color: PdfColors.grey, fontSize: 10)),
    ]);
  }

  pw.Widget _buildTabelaEquacaoPdf(Map<String, dynamic> resultadoRegressao) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Equação de Volume Gerada', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
      pw.Divider(color: PdfColors.grey, height: 10),
      pw.SizedBox(height: 5),
      pw.RichText(
        text: pw.TextSpan(children: [
          const pw.TextSpan(text: 'Equação: ', style: pw.TextStyle(color: PdfColors.grey)),
          pw.TextSpan(text: resultadoRegressao['equacao'], style: pw.TextStyle(font: pw.Font.courier())),
        ]),
      ),
      pw.SizedBox(height: 5),
      pw.Text('Coeficiente (R²): ${(resultadoRegressao['R2'] as double).toStringAsFixed(4)}'),
      pw.Text('Nº de Amostras Usadas: ${resultadoRegressao['n_amostras']}'),
    ]);
  }

  pw.Widget _buildTabelaProducaoPdf(Map<String, dynamic> producaoInventario) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Totais do Inventário', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
      pw.Divider(color: PdfColors.grey, height: 10),
      pw.SizedBox(height: 5),
      pw.Text('Aplicado aos talhões: ${producaoInventario['talhoes']}'),
      pw.SizedBox(height: 10),
      pw.TableHelper.fromTextArray(
        cellAlignment: pw.Alignment.centerLeft,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        data: <List<String>>[
          ['Métrica', 'Valor'],
          ['Volume por Hectare', '${(producaoInventario['volume_ha'] as double).toStringAsFixed(2)} m³/ha'],
          ['Árvores por Hectare', '${producaoInventario['arvores_ha']} árv/ha'],
          ['Área Basal por Hectare', '${(producaoInventario['area_basal_ha'] as double).toStringAsFixed(2)} m²/ha'],
          if((producaoInventario['volume_total_lote'] as double) > 0)
            ['Volume Total para ${(producaoInventario['area_total_lote'] as double).toStringAsFixed(2)} ha', '${(producaoInventario['volume_total_lote'] as double).toStringAsFixed(2)} m³'],
        ],
      ),
    ]);
  }

  pw.Widget _buildTabelaSortimentoPdf(Map<String, dynamic> producaoInventario, Map<String, dynamic> producaoSortimento) {
    final Map<String, double> porcentagens = producaoSortimento['porcentagens'] ?? {};
    if (porcentagens.isEmpty) {
      return pw.Text('Nenhuma produção por sortimento foi calculada.');
    }
    
    final double volumeTotalHa = producaoInventario['volume_ha'] ?? 0.0;
    
    final sortedKeys = porcentagens.keys.toList()..sort((a,b) {
      final numA = double.tryParse(a.split('-').first.replaceAll('>', '')) ?? 99;
      final numB = double.tryParse(b.split('-').first.replaceAll('>', '')) ?? 99;
      return numB.compareTo(numA); 
    });

    final List<List<String>> data = [];
    for (var key in sortedKeys) {
      final pct = porcentagens[key]!;
      final volumeHaSortimento = volumeTotalHa * (pct / 100);
      data.add([key, '${volumeHaSortimento.toStringAsFixed(2)} m³/ha', '${pct.toStringAsFixed(1)}%']);
    }

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Produção por Sortimento', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
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
  
  pw.Widget _buildTabelaDistribuicaoPdf(TalhaoAnalysisResult analise) {
    final headers = ['Classe (CAP)', 'Nº de Árvores', '%'];
    final totalArvoresVivas = analise.distribuicaoDiametrica.values.fold(0, (a, b) => a + b);
    
    final data = analise.distribuicaoDiametrica.entries.map((entry) {
      final pontoMedio = entry.key;
      final contagem = entry.value;
      final inicioClasse = pontoMedio - 2.5;
      final fimClasse = pontoMedio + 2.5 - 0.1;
      final porcentagem = totalArvoresVivas > 0 ? (contagem / totalArvoresVivas) * 100 : 0;
      return [
        '${inicioClasse.toStringAsFixed(1)} - ${fimClasse.toStringAsFixed(1)}',
        contagem.toString(),
        '${porcentagem.toStringAsFixed(1)}%',
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
      cellAlignment: pw.Alignment.center,
      cellAlignments: {0: pw.Alignment.centerLeft},
    );
  }

  pw.Widget _buildTabelaPlano(Map<String, int> plano) {
    final headers = ['Classe Diamétrica (CAP)', 'Nº de Árvores para Cubar'];

    if (plano.isEmpty) {
      return pw.Center(child: pw.Text("Nenhum dado para gerar o plano."));
    }

    final data =
        plano.entries.map((entry) => [entry.key, entry.value.toString()]).toList();
    final total = plano.values.fold(0, (a, b) => a + b);
    data.add(['Total', total.toString()]);

    return pw.Table(
      border: pw.TableBorder.all(),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
          children: headers
              .map((header) => pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(header,
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white),
                        textAlign: pw.TextAlign.center),
                  ))
              .toList(),
        ),
        ...data.asMap().entries.map((entry) {
          final index = entry.key;
          final rowData = entry.value;
          final bool isLastRow = index == data.length - 1;

          return pw.TableRow(
            children: rowData.asMap().entries.map((cellEntry) {
              final colIndex = cellEntry.key;
              final cellText = cellEntry.value;
              return pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(
                  cellText,
                  textAlign:
                      colIndex == 1 ? pw.TextAlign.center : pw.TextAlign.left,
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
  }
  
  // <<< FUNÇÃO RESTAURADA >>>
  pw.Widget _buildTabelaRendimentoPdf(List<RendimentoDAP> dados) {
    final headers = ['Classe DAP', 'Volume (m³/ha)', '% do Total', 'Árv./ha'];
    
    final data = dados
        .map((item) => [
              item.classe,
              item.volumePorHectare.toStringAsFixed(1),
              '${item.porcentagemDoTotal.toStringAsFixed(1)}%',
              item.arvoresPorHectare.toString(),
            ])
        .toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
      cellAlignment: pw.Alignment.center,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
      },
    );
  }
  
  // <<< FUNÇÃO RESTAURADA >>>
  pw.Widget _buildTabelaSimulacaoPdf(TalhaoAnalysisResult antes, TalhaoAnalysisResult depois) {
    final headers = ['Parâmetro', 'Antes', 'Após'];
    
    final data = [
      ['Árvores/ha', antes.arvoresPorHectare.toString(), depois.arvoresPorHectare.toString()],
      ['CAP Médio', '${antes.mediaCap.toStringAsFixed(1)} cm', '${depois.mediaCap.toStringAsFixed(1)} cm'],
      ['Altura Média', '${antes.mediaAltura.toStringAsFixed(1)} m', '${depois.mediaAltura.toStringAsFixed(1)} m'],
      ['Área Basal (G)', '${antes.areaBasalPorHectare.toStringAsFixed(2)} m²/ha', '${depois.areaBasalPorHectare.toStringAsFixed(2)} m²/ha'],
      ['Volume', '${antes.volumePorHectare.toStringAsFixed(2)} m³/ha', '${depois.volumePorHectare.toStringAsFixed(2)} m³/ha'],
    ];

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
      cellAlignment: pw.Alignment.center,
      cellAlignments: {0: pw.Alignment.centerLeft},
      cellStyle: const pw.TextStyle(fontSize: 11),
      border: pw.TableBorder.all(color: PdfColors.grey),
    );
  }
}
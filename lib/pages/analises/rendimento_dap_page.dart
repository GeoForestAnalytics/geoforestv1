// lib/pages/analises/rendimento_dap_page.dart (VERSÃO COM SINTAXE DA APPBAR CORRIGIDA)

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:geoforestv1/models/analise_result_model.dart';
import 'package:geoforestv1/services/pdf_service.dart';
import 'package:pdf/widgets.dart' as pw;

class RendimentoDapPage extends StatefulWidget {
  final String nomeFazenda;
  final String nomeTalhao;
  final List<DapClassResult> dadosRendimento;
  final TalhaoAnalysisResult analiseGeral;

  const RendimentoDapPage({
    super.key,
    required this.nomeFazenda,
    required this.nomeTalhao,
    required this.dadosRendimento,
    required this.analiseGeral,
  });

  @override
  State<RendimentoDapPage> createState() => _RendimentoDapPageState();
}

class _RendimentoDapPageState extends State<RendimentoDapPage> {
  final GlobalKey _graficoKey = GlobalKey();
  final PdfService _pdfService = PdfService();
  bool _isExporting = false;

  Future<void> _exportarPdf() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    
    try {
      RenderRepaintBoundary boundary = _graficoKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();
      final graficoImagem = pw.MemoryImage(pngBytes);

      await _pdfService.gerarRelatorioRendimentoPdf(
        context: context,
        nomeFazenda: widget.nomeFazenda,
        nomeTalhao: widget.nomeTalhao,
        dadosRendimento: widget.dadosRendimento,
        analiseGeral: widget.analiseGeral,
        graficoImagem: graficoImagem,
      );
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar PDF: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if(mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final List<Color> barColors = [
      Colors.blue.shade300,
      Colors.green.shade300,
      Colors.orange.shade300,
      Colors.red.shade300,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Distribuição por DAP'),
        actions: [
          // <<< INÍCIO DA CORREÇÃO >>>
          // A lógica if/else foi reestruturada para ser um único elemento na lista.
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white)))
            )
          else
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _exportarPdf,
              tooltip: 'Exportar para PDF'
            ),
          // <<< FIM DA CORREÇÃO >>>
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Distribuição de Indivíduos por Classe de DAP', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            Text('${widget.nomeFazenda} / ${widget.nomeTalhao}', style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey.shade600), textAlign: TextAlign.center),
            const SizedBox(height: 32),
            RepaintBoundary(
              key: _graficoKey,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Theme.of(context).scaffoldBackgroundColor,
                child: SizedBox(
                  height: 300,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => Colors.blueGrey,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final item = widget.dadosRendimento[groupIndex];
                            return BarTooltipItem(
                              '${item.classe}\n',
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              children: <TextSpan>[
                                TextSpan(
                                  text: '${item.quantidade} árvores\n',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                                TextSpan(
                                  text: '${item.porcentagemDoTotal.toStringAsFixed(1)}%',
                                  style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (double value, TitleMeta meta) {
                              if (value.toInt() >= widget.dadosRendimento.length) return const SizedBox.shrink();
                              final classe = widget.dadosRendimento[value.toInt()].classe;
                              return Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(classe, style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                              );
                            },
                            reservedSize: 32,
                          ),
                        ),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(show: false),
                      barGroups: widget.dadosRendimento.asMap().entries.map((entry) {
                        final index = entry.key;
                        final data = entry.value;
                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: data.porcentagemDoTotal,
                              color: barColors[index % barColors.length],
                              width: 22,
                              borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildResumoTable(widget.dadosRendimento, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildResumoTable(List<DapClassResult> dados, ThemeData theme) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: DataTable(
        columnSpacing: 16,
        headingRowHeight: 48,
        headingRowColor: MaterialStateProperty.all(theme.primaryColor.withOpacity(0.1)),
        columns: const [
          DataColumn(label: Text('Classe DAP', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Quantidade\n(árvores)', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
          DataColumn(label: Text('% do Total', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
        ],
        rows: dados.map((item) {
          return DataRow(cells: [
            DataCell(Text(item.classe, style: const TextStyle(fontSize: 14))),
            DataCell(Text(item.quantidade.toString())),
            DataCell(Text('${item.porcentagemDoTotal.toStringAsFixed(1)}%')),
          ]);
        }).toList(),
      ),
    );
  }
}
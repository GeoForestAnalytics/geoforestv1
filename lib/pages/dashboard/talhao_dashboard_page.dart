// Arquivo: lib/pages/dashboard/talhao_dashboard_page.dart (VERSÃO COMPLETA E CORRIGIDA)

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/services/analysis_service.dart';
import 'package:geoforestv1/services/export_service.dart';
import 'package:geoforestv1/services/pdf_service.dart';
import 'package:geoforestv1/widgets/grafico_distribuicao_widget.dart';
import 'package:geoforestv1/pages/analises/simulacao_desbaste_page.dart';
import 'package:geoforestv1/models/analise_result_model.dart';
import 'package:geoforestv1/data/repositories/analise_repository.dart';
import 'package:geoforestv1/widgets/grafico_dispersao_cap_altura.dart';
import 'package:pdf/widgets.dart' as pw;


class TalhaoDashboardPage extends StatelessWidget {
  final Talhao talhao;
  final GlobalKey<_TalhaoDashboardContentState> _contentKey = GlobalKey();

  TalhaoDashboardPage({super.key, required this.talhao});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Análise: ${talhao.nome}'),
        actions: [
          Builder(builder: (context) {
            return IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Exportar Análise',
              onPressed: () {
                final currentState = _contentKey.currentState;
                
                if (currentState?._analysisResult != null) {
                  currentState!.mostrarDialogoExportacao(context);
                } else {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Aguarde a análise carregar para exportar.'),
                  ));
                }
              },
            );
          })
        ],
      ),
      body: TalhaoDashboardContent(key: _contentKey, talhao: talhao),
    );
  }
}

class TalhaoDashboardContent extends StatefulWidget {
  final Talhao talhao;
  const TalhaoDashboardContent({super.key, required this.talhao});

  @override
  State<TalhaoDashboardContent> createState() => _TalhaoDashboardContentState();
}

class _TalhaoDashboardContentState extends State<TalhaoDashboardContent> {
  final _analiseRepository = AnaliseRepository();
  final _analysisService = AnalysisService();
  final _exportService = ExportService();
  final _pdfService = PdfService();

  final GlobalKey _graficoDispersaoKey = GlobalKey();

  List<Parcela> _parcelasDoTalhao = [];
  List<Arvore> _arvoresDoTalhao = [];
  late Future<void> _dataLoadingFuture;
  TalhaoAnalysisResult? _analysisResult;

  @override
  void initState() {
    super.initState();
    _dataLoadingFuture = _carregarEAnalisarTalhao();
  }

  void mostrarDialogoExportacao(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.description_outlined, color: Colors.blue),
              title: const Text('Exportar Relatório Detalhado (PDF)'),
              subtitle: const Text('Gera um relatório visual completo da análise.'),
              onTap: () async {
                Navigator.of(ctx).pop();
                if (_analysisResult != null) {
                  RenderRepaintBoundary boundary = _graficoDispersaoKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
                  ui.Image image = await boundary.toImage(pixelRatio: 2.0);
                  ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
                  Uint8List pngBytes = byteData!.buffer.asUint8List();
                  final graficoImagem = pw.MemoryImage(pngBytes);
                  
                  await _pdfService.gerarRelatorioAnaliseTalhaoPdf(
                    context: context,
                    talhao: widget.talhao,
                    analise: _analysisResult!,
                    graficoDispersaoImagem: graficoImagem,
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_rows_outlined, color: Colors.green),
              title: const Text('Exportar Dados Resumidos (CSV)'),
              subtitle: const Text('Gera uma planilha com os dados da análise.'),
              onTap: () {
                Navigator.of(ctx).pop();
                if (_analysisResult != null) {
                  _exportService.exportarAnaliseTalhaoCsv(
                    context: context,
                    talhao: widget.talhao,
                    analise: _analysisResult!,
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _carregarEAnalisarTalhao() async {
    final dadosAgregados = await _analiseRepository.getDadosAgregadosDoTalhao(widget.talhao.id!);
    
    _parcelasDoTalhao = dadosAgregados['parcelas'] as List<Parcela>;
    _arvoresDoTalhao = dadosAgregados['arvores'] as List<Arvore>;
    if (!mounted || _parcelasDoTalhao.isEmpty || _arvoresDoTalhao.isEmpty) return;
    
    final resultado = _analysisService.getTalhaoInsights(widget.talhao, _parcelasDoTalhao, _arvoresDoTalhao);
    if (mounted) {
      setState(() => _analysisResult = resultado);
    }
  }
  
  void _navegarParaSimulacao() {
    if (_analysisResult == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SimulacaoDesbastePage(
          talhao: widget.talhao,
          parcelas: _parcelasDoTalhao,
          arvores: _arvoresDoTalhao,
          analiseInicial: _analysisResult!,
        ),
      ),
    );
  }  

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _dataLoadingFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro ao analisar talhão: ${snapshot.error}'));
        }
        if (_analysisResult == null || _analysisResult!.totalArvoresAmostradas == 0) {
          return const Center(child: Text('Não há dados de parcelas concluídas para a análise.'));
        }

        final result = _analysisResult!;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildResumoCard(result),
              const SizedBox(height: 16),
              if (result.analiseDeCodigos != null)
                _buildCodeAnalysisCard(result.analiseDeCodigos!),
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Distribuição Diamétrica (CAP)', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 24),
                      GraficoDistribuicaoWidget(dadosDistribuicao: result.distribuicaoDiametrica),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              RepaintBoundary(
                key: _graficoDispersaoKey,
                child: Container(
                  color: Theme.of(context).cardColor,
                  child: GraficoDispersaoCapAltura(arvores: _arvoresDoTalhao),
                ),
              ),
              const SizedBox(height: 16),
              _buildInsightsCard("⚠️ Alertas", result.warnings, Colors.red.shade100),
              const SizedBox(height: 12),
              _buildInsightsCard("💡 Insights", result.insights, Colors.blue.shade100),
              const SizedBox(height: 12),
              _buildInsightsCard("🛠️ Recomendações", result.recommendations, Colors.orange.shade100),
              
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _navegarParaSimulacao,
                icon: const Icon(Icons.content_cut_outlined),
                label: const Text('Simular Desbaste'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ✅ 1. CORREÇÃO DAS CORES DA TABELA (Texto visível no tema escuro)
  Widget _buildCodeAnalysisCard(CodeAnalysisResult codeAnalysis) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Se for Dark, fundo transparente e letra Dourada
    // Se for Light, fundo cinza claro e letra Azul Marinho
    final headerBgColor = isDark ? Colors.black26 : Colors.grey.shade200;
    final headerTextColor = isDark ? const Color(0xFFEBE4AB) : const Color(0xFF023853);
    
    final headerTextStyle = TextStyle(
      color: headerTextColor,
      fontWeight: FontWeight.bold,
      fontSize: 13,
    );

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Composição do Povoamento', style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 20),
            _buildStatRow('Total de Fustes Amostrados:', codeAnalysis.totalFustes.toString()),
            _buildStatRow('Total de Covas Amostradas:', codeAnalysis.totalCovasAmostradas.toString()),
            if (codeAnalysis.totalCovasAmostradas > 0)
              _buildStatRow(
                'Covas Ocupadas (Sobrevivência):', 
                '${codeAnalysis.totalCovasOcupadas} (${(codeAnalysis.totalCovasOcupadas / codeAnalysis.totalCovasAmostradas * 100).toStringAsFixed(1)}%)'
              ),
            const SizedBox(height: 16),
            Text('Estatísticas por Código', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18.0,
                headingRowColor: MaterialStateProperty.all(headerBgColor), 
                columns: [
                  DataColumn(label: Text('Código', style: headerTextStyle)),
                  DataColumn(label: Text('Qtd.', style: headerTextStyle), numeric: true),
                  DataColumn(label: Text('Média\nCAP', style: headerTextStyle, textAlign: TextAlign.center), numeric: true),
                  DataColumn(label: Text('Mediana\nCAP', style: headerTextStyle, textAlign: TextAlign.center), numeric: true),
                  DataColumn(label: Text('Moda\nCAP', style: headerTextStyle, textAlign: TextAlign.center), numeric: true),
                  DataColumn(label: Text('DP\nCAP', style: headerTextStyle, textAlign: TextAlign.center), numeric: true),
                  DataColumn(label: Text('Média\nAltura', style: headerTextStyle, textAlign: TextAlign.center), numeric: true),
                  DataColumn(label: Text('Mediana\nAltura', style: headerTextStyle, textAlign: TextAlign.center), numeric: true),
                  DataColumn(label: Text('Moda\nAltura', style: headerTextStyle, textAlign: TextAlign.center), numeric: true),
                  DataColumn(label: Text('DP\nAltura', style: headerTextStyle, textAlign: TextAlign.center), numeric: true),
                ],
                rows: codeAnalysis.estatisticasPorCodigo.entries.map((entry) {
                  final stats = entry.value;
                  return DataRow(cells: [
                    DataCell(Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text(codeAnalysis.contagemPorCodigo[entry.key]?.toString() ?? '0')),
                    DataCell(Text(stats.mediaCap.toStringAsFixed(1))),
                    DataCell(Text(stats.medianaCap.toStringAsFixed(1))),
                    DataCell(Text(stats.modaCap.toStringAsFixed(1))),
                    DataCell(Text(stats.desvioPadraoCap.toStringAsFixed(1))),
                    DataCell(Text(stats.mediaAltura.toStringAsFixed(1))),
                    DataCell(Text(stats.medianaAltura.toStringAsFixed(1))),
                    DataCell(Text(stats.modaAltura.toStringAsFixed(1))),
                    DataCell(Text(stats.desvioPadraoAltura.toStringAsFixed(1))),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumoCard(TalhaoAnalysisResult result) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resumo do Talhão', style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 20),
            _buildStatRow('Árvores/ha:', result.arvoresPorHectare.toString()),
            _buildStatRow('CAP Médio:', '${result.mediaCap.toStringAsFixed(1)} cm'),
            _buildStatRow('Altura Média:', '${result.mediaAltura.toStringAsFixed(1)} m'),
            _buildStatRow('Área Basal (G):', '${result.areaBasalPorHectare.toStringAsFixed(2)} m²/ha'),
            _buildStatRow('Volume Estimado:', '${result.volumePorHectare.toStringAsFixed(2)} m³/ha'),
            
            if (result.alturaDominante > 0)
              _buildStatRow('Altura Dominante (HD):', '${result.alturaDominante.toStringAsFixed(1)} m'),
            if (result.indiceDeSitio > 0)
              _buildStatRow('Índice de Sítio (7 anos):', result.indiceDeSitio.toStringAsFixed(1)),

            const Divider(height: 20, thickness: 0.5, indent: 20, endIndent: 20),
            _buildStatRow('Nº de Parcelas Amostradas:', result.totalParcelasAmostradas.toString()),
            _buildStatRow('Nº de Árvores Medidas:', result.totalArvoresAmostradas.toString()),
          ],
        ),
      ),
    );
  }

  // ✅ 2. CORREÇÃO DOS CARDS DE INSIGHTS (Contraste no modo escuro)
  Widget _buildInsightsCard(String title, List<String> items, Color color) {
    if (items.isEmpty) return const SizedBox.shrink();
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Ajusta o fundo para não ficar "pastel" demais no modo escuro
    final backgroundColor = isDark ? color.withOpacity(0.15) : color;
    // Título colorido no modo escuro para destaque, preto no claro
    final titleColor = isDark ? color.withOpacity(1.0) : Colors.black87;
    // Texto branco/cinza no escuro, preto no claro
    final textColor = isDark ? Colors.white70 : Colors.black87;

    return Card(
      color: backgroundColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark ? BorderSide(color: color.withOpacity(0.3)) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title, 
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: titleColor)
            ),
            const SizedBox(height: 8),
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 4.0), 
              child: Text('- $item', style: TextStyle(color: textColor))
            )),
          ],
        ),
      ),
    );
  }

  // ✅ 3. CORREÇÃO DO OVERFLOW NO TEXTO (Usa Expanded)
  Widget _buildStatRow(String label, String value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final colorLabel = isDark ? Colors.white70 : Colors.grey[700];
    final colorValue = isDark ? theme.colorScheme.secondary : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start, // Alinha ao topo se quebrar linha
        children: [
          // Expanded permite que o texto quebre linha se for longo
          Expanded(
            child: Text(label, style: TextStyle(color: colorLabel)),
          ),
          const SizedBox(width: 12), // Espaço entre label e valor
          Text(
            value, 
            style: TextStyle(
              fontWeight: FontWeight.bold, 
              fontSize: 16,
              color: colorValue
            ),
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }
}
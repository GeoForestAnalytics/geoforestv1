import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:geoforestv1/data/repositories/analise_repository.dart';
import 'package:geoforestv1/models/analise_result_model.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/services/analysis_service.dart';
import 'package:geoforestv1/services/pdf_service.dart';
import 'package:geoforestv1/widgets/grafico_dispersao_cap_altura.dart';
import 'package:geoforestv1/widgets/grafico_distribuicao_widget.dart';
import 'package:pdf/widgets.dart' as pw;

class EstratoDashboardPage extends StatefulWidget {
  final List<Talhao> talhoesSelecionados;

  const EstratoDashboardPage({super.key, required this.talhoesSelecionados});

  @override
  State<EstratoDashboardPage> createState() => _EstratoDashboardPageState();
}

class _EstratoDashboardPageState extends State<EstratoDashboardPage> {
  final _analiseRepository = AnaliseRepository();
  final _analysisService = AnalysisService();
  final _pdfService = PdfService();
  final GlobalKey _graficoDispersaoKey = GlobalKey();

  late Future<TalhaoAnalysisResult?> _analiseFuture;
  List<Arvore> _todasArvoresParaGrafico = [];

  @override
  void initState() {
    super.initState();
    _analiseFuture = _processarEstrato();
  }

  Future<TalhaoAnalysisResult?> _processarEstrato() async {
    final Map<int, List<Parcela>> parcelasMap = {};
    final Map<int, List<Arvore>> arvoresMap = {};
    _todasArvoresParaGrafico = [];

    for (var talhao in widget.talhoesSelecionados) {
      if (talhao.id == null) continue;

      final dados =
          await _analiseRepository.getDadosAgregadosDoTalhao(talhao.id!);
      final parcelas = dados['parcelas'] as List<Parcela>;
      final arvores = dados['arvores'] as List<Arvore>;

      if (parcelas.isNotEmpty) {
        parcelasMap[talhao.id!] = parcelas;
        arvoresMap[talhao.id!] = arvores;
        _todasArvoresParaGrafico.addAll(arvores);
      }
    }

    if (parcelasMap.isEmpty) return null;

    return _analysisService.analisarEstratoUnificado(
      talhoes: widget.talhoesSelecionados,
      parcelasPorTalhao: parcelasMap,
      arvoresPorTalhao: arvoresMap,
    );
  }

  // Reutilizamos o card de resumo do TalhaoDashboardPage, mas podemos customizar se quiser
  // Como o TalhaoDashboardPage tem o método _buildResumoCard privado, vamos copiar a lógica
  // ou torná-lo público. Para ser rápido, vou recriar um simples aqui.
  Widget _buildResumoEstrato(TalhaoAnalysisResult result) {
    return Card(
      elevation: 4,
      color: const Color(
          0xFFF0F4F8), // Um fundo levemente diferente para diferenciar
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.layers, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text('MÉDIAS DO ESTRATO',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.indigo)),
              ],
            ),
            const Divider(),
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                _statItem('Volume/ha',
                    '${result.volumePorHectare.toStringAsFixed(2)} m³'),
                _statItem('Área Basal/ha',
                    '${result.areaBasalPorHectare.toStringAsFixed(2)} m²'),
                _statItem('Árvores/ha', '${result.arvoresPorHectare}'),
                _statItem(
                    'CAP Médio', '${result.mediaCap.toStringAsFixed(1)} cm'),
                _statItem(
                    'Alt. Média', '${result.mediaAltura.toStringAsFixed(1)} m'),
                _statItem('Alt. Dominante',
                    '${result.alturaDominante.toStringAsFixed(1)} m'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
                "Área Total Consolidada: ${result.areaTotalAmostradaHa.toStringAsFixed(2)} ha",
                style: const TextStyle(
                    fontSize: 12, 
                    fontWeight: FontWeight.bold,
                    color: Colors.black54 // <--- CORRIGIDO: Forçando cor escura (cinza)
                )),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Rótulo em cinza escuro
        Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
        // Valor em Azul Marinho (sua cor primária) ou Preto para contraste máximo
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 16,
                color: Color(0xFF023853) // <--- FORÇANDO COR ESCURA AQUI
            )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Cria um "Talhão Virtual" para usar na exportação de PDF existente
    double totalArea = 0.0;
    for (var talhao in widget.talhoesSelecionados) {
      totalArea += talhao.areaHa ?? 0.0;
    }
    final talhaoRepresentativo = widget.talhoesSelecionados.first.copyWith(
      nome:
          "ESTRATO CONSOLIDADO (${widget.talhoesSelecionados.length} talhões)",
      areaHa: totalArea,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Análise de Estrato"),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Exportar PDF do Estrato",
            onPressed: () async {
              final result = await _analiseFuture;
              if (result != null && mounted) {
                RenderRepaintBoundary boundary =
                    _graficoDispersaoKey.currentContext!.findRenderObject()
                        as RenderRepaintBoundary;
                ui.Image image = await boundary.toImage(pixelRatio: 2.0);
                ByteData? byteData =
                    await image.toByteData(format: ui.ImageByteFormat.png);
                Uint8List pngBytes = byteData!.buffer.asUint8List();
                final graficoImagem = pw.MemoryImage(pngBytes);

                await _pdfService.gerarRelatorioAnaliseTalhaoPdf(
                  context: context,
                  talhao:
                      talhaoRepresentativo, // Passamos o talhão "fake" com nome do estrato
                  analise: result,
                  graficoDispersaoImagem: graficoImagem,
                );
              }
            },
          )
        ],
      ),
      body: FutureBuilder<TalhaoAnalysisResult?>(
        future: _analiseFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data == null) {
            return const Center(
                child: Text("Dados insuficientes para análise de estrato."));
          }

          final result = snapshot.data!;

          // Reutilizamos widgets do TalhaoDashboardContent para manter consistência visual
          // Como eles estão dentro de um arquivo, mas não são públicos,
          // aqui eu recriei o básico ou usei os Widgets públicos.

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    "Composição: ${widget.talhoesSelecionados.map((t) => t.nome).join(', ')}",
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 10),
                _buildResumoEstrato(result),
                const SizedBox(height: 20),

                // Gráfico de Distribuição
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text('Distribuição Diamétrica do Estrato',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 16),
                        GraficoDistribuicaoWidget(
                            dadosDistribuicao: result.distribuicaoDiametrica),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Gráfico de Dispersão (Todas as árvores do estrato)
                RepaintBoundary(
                  key: _graficoDispersaoKey,
                  child: Container(
                    color: Theme.of(context).cardColor,
                    child: GraficoDispersaoCapAltura(
                        arvores: _todasArvoresParaGrafico),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

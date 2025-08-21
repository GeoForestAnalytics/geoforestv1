// lib/pages/analises/simulacao_desbaste_page.dart (VERSÃO COM EXPORTAÇÃO FUNCIONAL)

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/services/analysis_service.dart';
import 'package:geoforestv1/models/analise_result_model.dart';
import 'package:geoforestv1/services/pdf_service.dart'; // <<< 1. IMPORTAR PDF SERVICE

class SimulacaoDesbastePage extends StatefulWidget {
  final List<Parcela> parcelas;
  final List<Arvore> arvores;
  final TalhaoAnalysisResult analiseInicial;

  const SimulacaoDesbastePage({
    super.key,
    required this.parcelas,
    required this.arvores,
    required this.analiseInicial,
  });

  @override
  State<SimulacaoDesbastePage> createState() => _SimulacaoDesbastePageState();
}

class _SimulacaoDesbastePageState extends State<SimulacaoDesbastePage> {
  final _analysisService = AnalysisService();
  final _pdfService = PdfService(); // <<< 2. INSTANCIAR PDF SERVICE
  double _intensidadeDesbaste = 0.0; // Em porcentagem (0 a 40)
  late TalhaoAnalysisResult _resultadoSimulacao;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    // O estado inicial da simulação é a própria análise inicial
    _resultadoSimulacao = widget.analiseInicial;
  }

  void _rodarSimulacao(double novaIntensidade) {
    setState(() {
      _intensidadeDesbaste = novaIntensidade;
      // Chama o serviço de análise para obter os resultados pós-desbaste
      _resultadoSimulacao = _analysisService.simularDesbaste(
        widget.parcelas,
        widget.arvores,
        _intensidadeDesbaste,
      );
    });
  }

  // <<< 3. FUNÇÃO DE EXPORTAÇÃO IMPLEMENTADA >>>
  Future<void> _exportarSimulacaoPdf() async {
  if (_isExporting) return;
  if (widget.parcelas.isEmpty) {
     ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Não há dados para exportar.')),
    );
    return;
  }
  setState(() => _isExporting = true);
  
  final nomeFazenda = widget.parcelas.first.nomeFazenda ?? 'Fazenda Desconhecida';
  final nomeTalhao = widget.parcelas.first.nomeTalhao ?? 'Talhão Desconhecido';

  try {
    // A chamada para o serviço é a mesma, mas ele agora lida com a permissão.
    await _pdfService.gerarRelatorioSimulacaoPdf(
      context: context,
      nomeFazenda: nomeFazenda,
      nomeTalhao: nomeTalhao,
      intensidade: _intensidadeDesbaste,
      analiseInicial: widget.analiseInicial,
      resultadoSimulacao: _resultadoSimulacao,
    );
  } catch(e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erro ao exportar: $e"), backgroundColor: Colors.red),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simulador de Desbaste'),
        actions: [
          // <<< 4. BOTÃO DE AÇÃO NA APPBAR >>>
          if (_isExporting)
            const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white,)))
          else
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _exportarSimulacaoPdf,
              tooltip: 'Exportar Simulação para PDF',
            )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildControleDesbaste(),
            const SizedBox(height: 24),
            _buildTabelaResultados(),
          ],
        ),
      ),
    );
  }

  Widget _buildControleDesbaste() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Intensidade do Desbaste: ${_intensidadeDesbaste.toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Remover as árvores mais finas (por CAP)',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            Slider(
              value: _intensidadeDesbaste,
              min: 0,
              max: 40, 
              divisions: 8,
              label: '${_intensidadeDesbaste.toStringAsFixed(0)}%',
              onChanged: (value) {
                setState(() {
                  _intensidadeDesbaste = value;
                });
              },
              onChangeEnd: (value) {
                _rodarSimulacao(value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabelaResultados() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Comparativo de Resultados', style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 20),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2), 
                1: FlexColumnWidth(1.2),
                2: FlexColumnWidth(1.2),
              },
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: Colors.grey.shade300,
                  width: 1,
                ),
              ),
              children: [
                _buildHeaderRow(),
                _buildDataRow(
                  'Árvores/ha',
                  widget.analiseInicial.arvoresPorHectare.toString(),
                  _resultadoSimulacao.arvoresPorHectare.toString(),
                ),
                _buildDataRow(
                  'CAP Médio',
                  '${widget.analiseInicial.mediaCap.toStringAsFixed(1)} cm',
                  '${_resultadoSimulacao.mediaCap.toStringAsFixed(1)} cm',
                ),
                 _buildDataRow(
                  'Altura Média',
                  '${widget.analiseInicial.mediaAltura.toStringAsFixed(1)} m',
                  '${_resultadoSimulacao.mediaAltura.toStringAsFixed(1)} m',
                ),
                _buildDataRow(
                  'Área Basal (G)',
                  '${widget.analiseInicial.areaBasalPorHectare.toStringAsFixed(2)} m²/ha',
                  '${_resultadoSimulacao.areaBasalPorHectare.toStringAsFixed(2)} m²/ha',
                ),
                _buildDataRow(
                  'Volume',
                  '${widget.analiseInicial.volumePorHectare.toStringAsFixed(2)} m³/ha',
                  '${_resultadoSimulacao.volumePorHectare.toStringAsFixed(2)} m³/ha',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TableRow _buildHeaderRow() {
    return TableRow(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
      ),
      children: [
        _buildHeaderCell('Parâmetro'),
        _buildHeaderCell('Antes'),
        _buildHeaderCell('Após'),
      ],
    );
  }

  TableRow _buildDataRow(String label, String valorAntes, String valorDepois) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
          child: Text(valorAntes, textAlign: TextAlign.center),
        ),
        Container(
          color: Colors.green.withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
            child: Text(
              valorDepois,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
    );
  }
}
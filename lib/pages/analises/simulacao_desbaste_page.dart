// Arquivo: lib\pages\analises\simulacao_desbaste_page.dart (VERSÃO CORRIGIDA)

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/services/analysis_service.dart';
import 'package:geoforestv1/models/analise_result_model.dart';
import 'package:geoforestv1/services/pdf_service.dart';

class SimulacaoDesbastePage extends StatefulWidget {
  final Talhao talhao;
  final List<Parcela> parcelas;
  final List<Arvore> arvores;
  final TalhaoAnalysisResult analiseInicial;

  const SimulacaoDesbastePage({
    super.key,
    required this.talhao,
    required this.parcelas,
    required this.arvores,
    required this.analiseInicial,
  });

  @override
  State<SimulacaoDesbastePage> createState() => _SimulacaoDesbastePageState();
}

class _SimulacaoDesbastePageState extends State<SimulacaoDesbastePage> {
  final _analysisService = AnalysisService();
  final _pdfService = PdfService();
  double _intensidadeDesbaste = 0.0;
  late TalhaoAnalysisResult _resultadoSimulacao;
  bool _isExporting = false;

  // ✅ ADICIONE ESTAS DUAS LINHAS AQUI
  bool _desbasteSistematicoAtivo = false;
  final _linhaSistematicaController = TextEditingController(text: '5');

  @override
  void initState() {
    super.initState();
    _resultadoSimulacao = widget.analiseInicial;
  }

  void _rodarSimulacao() {
  setState(() {
    _resultadoSimulacao = _analysisService.simularDesbaste(
      talhao: widget.talhao,
      // ✅ CORREÇÃO AQUI
      parcelasOriginais: widget.parcelas,
      todasAsArvores: widget.arvores,
      // ✅ FIM DA CORREÇÃO
      porcentagemRemocaoSeletiva: _intensidadeDesbaste,
      sistematicoAtivo: _desbasteSistematicoAtivo,
      linhaSistematica: int.tryParse(_linhaSistematicaController.text),
    );
  });
}

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
          // --- CONTROLE DE DESBASTE SELETIVO (JÁ EXISTE) ---
          Text(
            'Intensidade do Desbaste Seletivo: ${_intensidadeDesbaste.toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Remover as árvores mais finas (por CAP) nas linhas remanescentes', // Texto ajustado
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
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
              _rodarSimulacao(); // A função será atualizada
            },
          ),
          const Divider(height: 24),

          // --- NOVOS CONTROLES PARA DESBASTE SISTEMÁTICO ---
          SwitchListTile(
            title: const Text('Ativar Desbaste Sistemático', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Remove uma linha inteira para criar ramais.'),
            value: _desbasteSistematicoAtivo,
            onChanged: (value) {
              setState(() {
                _desbasteSistematicoAtivo = value;
              });
              _rodarSimulacao(); // Roda a simulação ao ativar/desativar
            },
            contentPadding: EdgeInsets.zero,
          ),
          
          if (_desbasteSistematicoAtivo) // Só mostra o campo se estiver ativo
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: TextFormField(
                controller: _linhaSistematicaController,
                decoration: const InputDecoration(
                  labelText: 'Remover a cada Xª linha',
                  border: OutlineInputBorder(),
                  helperText: 'Ex: 5 para remover a 5ª, 10ª, 15ª linha...',
                ),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: (_) => _rodarSimulacao(), // Roda a simulação ao mudar o valor
              ),
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
                  color: const Color.fromARGB(255, 224, 224, 224),
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
        color: const Color.fromARGB(237, 131, 146, 160),
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
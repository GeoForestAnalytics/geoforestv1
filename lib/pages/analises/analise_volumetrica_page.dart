// lib/pages/analises/analise_volumetrica_page.dart (VERSÃO COM FILTRO DE ATIVIDADE)

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/models/analise_result_model.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/services/analysis_service.dart';
import 'package:geoforestv1/services/pdf_service.dart';
// Repositórios
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/data/repositories/fazenda_repository.dart';



class AnaliseVolumetricaPage extends StatefulWidget {
  const AnaliseVolumetricaPage({super.key});

  @override
  State<AnaliseVolumetricaPage> createState() => _AnaliseVolumetricaPageState();
}

class _AnaliseVolumetricaPageState extends State<AnaliseVolumetricaPage> {
  // Repositórios e Serviços
  final _projetoRepository = ProjetoRepository();
  final _atividadeRepository = AtividadeRepository();
  final _fazendaRepository = FazendaRepository();
  final _talhaoRepository = TalhaoRepository();
  final _cubagemRepository = CubagemRepository();
  final _analysisService = AnalysisService();
  final _pdfService = PdfService();

  // <<< MUDANÇA 1: ADIÇÃO DOS ESTADOS PARA O NOVO FILTRO DE ATIVIDADE >>>
  List<Projeto> _projetosDisponiveis = [];
  Projeto? _projetoSelecionado;
  List<Atividade> _atividadesDisponiveis = [];
  Atividade? _atividadeSelecionada;
  List<Fazenda> _fazendasDisponiveis = [];
  Fazenda? _fazendaSelecionada;

  // Listas de Talhões
  List<Talhao> _talhoesComCubagemDisponiveis = [];
  List<Talhao> _talhoesComInventarioDisponiveis = [];
  final Set<int> _talhoesCubadosSelecionados = {};
  final Set<int> _talhoesInventarioSelecionados = {};

  AnaliseVolumetricaCompletaResult? _analiseResult;
  
  // Controle de UI
  bool _isLoading = true;
  bool _isAnalyzing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _carregarProjetosIniciais();
  }

  Future<void> _carregarProjetosIniciais() async {
    setState(() => _isLoading = true);
    _projetosDisponiveis = await _projetoRepository.getTodosOsProjetosParaGerente();
    setState(() => _isLoading = false);
  }

  // <<< MUDANÇA 2: LÓGICA DE FILTRO EM CASCATA ATUALIZADA >>>
  Future<void> _onProjetoSelecionado(Projeto? projeto) async {
    setState(() {
      _projetoSelecionado = projeto;
      _atividadeSelecionada = null;
      _fazendaSelecionada = null;
      _atividadesDisponiveis = [];
      _fazendasDisponiveis = [];
      _talhoesComCubagemDisponiveis = [];
      _talhoesComInventarioDisponiveis = [];
      _talhoesCubadosSelecionados.clear();
      _talhoesInventarioSelecionados.clear();
      _limparResultados();
      if (projeto == null) {
        _isLoading = false;
        return;
      }
      _isLoading = true;
    });

    _atividadesDisponiveis = await _atividadeRepository.getAtividadesDoProjeto(projeto!.id!);
    setState(() => _isLoading = false);
  }

  Future<void> _onAtividadeSelecionada(Atividade? atividade) async {
    setState(() {
      _atividadeSelecionada = atividade;
      _fazendaSelecionada = null;
      _fazendasDisponiveis = [];
      _talhoesComCubagemDisponiveis = [];
      _talhoesComInventarioDisponiveis = [];
      _talhoesCubadosSelecionados.clear();
      _talhoesInventarioSelecionados.clear();
      _limparResultados();
      if (atividade == null) {
        _isLoading = false;
        return;
      }
      _isLoading = true;
    });

    _fazendasDisponiveis = await _fazendaRepository.getFazendasDaAtividade(atividade!.id!);
    setState(() => _isLoading = false);
  }

  Future<void> _onFazendaSelecionada(Fazenda? fazenda) async {
    setState(() {
      _fazendaSelecionada = fazenda;
      _talhoesComCubagemDisponiveis = [];
      _talhoesComInventarioDisponiveis = [];
      _talhoesCubadosSelecionados.clear();
      _talhoesInventarioSelecionados.clear();
      _limparResultados();
      if (fazenda == null) {
        _isLoading = false;
        return;
      }
      _isLoading = true;
    });
    
    await _carregarTalhoesParaSelecao();
    setState(() => _isLoading = false);
  }

  // <<< MUDANÇA 3: LÓGICA DE BUSCA DOS TALHÕES COMPLETAMENTE REFEITA >>>
  Future<void> _carregarTalhoesParaSelecao() async {
    if (_projetoSelecionado == null || _atividadeSelecionada == null || _fazendaSelecionada == null) return;
    
    // 1. Carrega os talhões de INVENTÁRIO (baseado nos filtros que o usuário selecionou)
    final todosTalhoesDaFazendaInventario = await _talhaoRepository.getTalhoesDaFazenda(_fazendaSelecionada!.id, _fazendaSelecionada!.atividadeId);
    final talhoesCompletosInvIds = (await _talhaoRepository.getTalhoesComParcelasConcluidas()).map((t) => t.id).toSet();
    final talhoesInventarioEncontrados = todosTalhoesDaFazendaInventario.where((t) => talhoesCompletosInvIds.contains(t.id)).toList();

    // 2. Procura inteligentemente pelos talhões de CUBAGEM
    List<Talhao> talhoesCubagemEncontrados = [];
    // Busca todas as atividades do projeto para encontrar uma de cubagem
    final todasAtividadesDoProjeto = await _atividadeRepository.getAtividadesDoProjeto(_projetoSelecionado!.id!);
    final atividadeCub = todasAtividadesDoProjeto.cast<Atividade?>().firstWhere((a) => a?.tipo.toUpperCase().contains('CUB') ?? false, orElse: () => null);
    
    if (atividadeCub != null) {
      // Encontra a fazenda com o MESMO NOME dentro da atividade de cubagem
      final fazendasDaAtividadeCub = await _fazendaRepository.getFazendasDaAtividade(atividadeCub.id!);
      final fazendaCub = fazendasDaAtividadeCub.cast<Fazenda?>().firstWhere((f) => f?.nome == _fazendaSelecionada!.nome, orElse: () => null);
      
      if (fazendaCub != null) {
        final todosTalhoesDaFazendaCub = await _talhaoRepository.getTalhoesDaFazenda(fazendaCub.id, fazendaCub.atividadeId);
        final todasCubagens = await _cubagemRepository.getTodasCubagens();
        final talhoesCompletosCubIds = todasCubagens.where((c) => c.alturaTotal > 0 && c.talhaoId != null).map((c) => c.talhaoId!).toSet();
        talhoesCubagemEncontrados = todosTalhoesDaFazendaCub.where((t) => talhoesCompletosCubIds.contains(t.id)).toList();
      }
    }

    setState(() {
        _talhoesComInventarioDisponiveis = talhoesInventarioEncontrados;
        _talhoesComCubagemDisponiveis = talhoesCubagemEncontrados;
    });
  }
  
  void _limparResultados() {
    setState(() {
        _analiseResult = null;
    });
  }

  Future<void> _gerarAnaliseCompleta() async {
    if (_talhoesCubadosSelecionados.isEmpty || _talhoesInventarioSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Selecione ao menos um talhão de cubagem E um de inventário.'),
          backgroundColor: Colors.orange));
      return;
    }
    setState(() { _isAnalyzing = true; _errorMessage = null; _limparResultados(); });
    
    try {
      List<CubagemArvore> arvoresParaRegressao = [];
      for(final talhaoId in _talhoesCubadosSelecionados) {
        arvoresParaRegressao.addAll(await _cubagemRepository.getTodasCubagensDoTalhao(talhaoId));
      }

      List<Talhao> talhoesInventarioAnalisados = [];
      for (final talhaoId in _talhoesInventarioSelecionados) {
        final talhao = await _talhaoRepository.getTalhaoById(talhaoId);
        if (talhao != null) talhoesInventarioAnalisados.add(talhao);
      }

      final resultadoCompleto = await _analysisService.gerarAnaliseVolumetricaCompleta(
        arvoresParaRegressao: arvoresParaRegressao,
        talhoesInventario: talhoesInventarioAnalisados,
      );

      if (mounted) {
        setState(() {
          _analiseResult = resultadoCompleto;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Erro na análise: ${e.toString()}";
        });
      }
    } finally {
      if (mounted) {
        setState(() { _isAnalyzing = false; });
      }
    }
  }

  Future<void> _exportarPdf() async {
    if (_analiseResult == null) return;
    
    final resultadoRegressao = _analiseResult!.resultadoRegressao;
    final producaoInventario = _analiseResult!.totaisInventario;
    
    final producaoSortimento = {
      'porcentagens': {for (var v in _analiseResult!.producaoPorSortimento) v.nome: v.porcentagem}
    };
    
    await _pdfService.gerarRelatorioVolumetricoPdf(
      context: context,
      resultadoRegressao: resultadoRegressao,
      producaoInventario: producaoInventario,
      producaoSortimento: producaoSortimento,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Análise Volumétrica'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: (_analiseResult == null || _isAnalyzing) ? null : _exportarPdf,
            tooltip: 'Exportar Relatório (PDF)',
          ),
        ],
      ),
      body: _errorMessage != null
          ? Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text(_errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center,)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
              children: [
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        DropdownButtonFormField<Projeto>(
                          value: _projetoSelecionado, hint: const Text('Selecione um Projeto'), isExpanded: true,
                          items: _projetosDisponiveis.map((p) => DropdownMenuItem(value: p, child: Text(p.nome, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: _onProjetoSelecionado, decoration: const InputDecoration(border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 10),
                        // <<< MUDANÇA 4: ADIÇÃO DO DROPDOWN DE ATIVIDADE NA UI >>>
                        DropdownButtonFormField<Atividade>(
                          value: _atividadeSelecionada,
                          hint: const Text('Selecione uma Atividade'),
                          disabledHint: const Text('Selecione um projeto primeiro'),
                          isExpanded: true,
                          items: _atividadesDisponiveis.map((a) => DropdownMenuItem(value: a, child: Text(a.tipo, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: _projetoSelecionado == null ? null : _onAtividadeSelecionada,
                          decoration: const InputDecoration(border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<Fazenda>(
                          value: _fazendaSelecionada,
                          hint: const Text('Selecione uma Fazenda'),
                          disabledHint: const Text('Selecione uma atividade primeiro'),
                          isExpanded: true,
                          items: _fazendasDisponiveis.map((f) => DropdownMenuItem(value: f, child: Text(f.nome, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: _atividadeSelecionada == null ? null : _onFazendaSelecionada,
                          decoration: const InputDecoration(border: OutlineInputBorder()),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildTalhaoSelectionCard(
                  title: '1. Selecione os Talhões CUBADOS', subtitle: 'Serão usados para gerar a equação de volume.',
                  talhoesDisponiveis: _talhoesComCubagemDisponiveis, talhoesSelecionadosSet: _talhoesCubadosSelecionados,
                ),
                const SizedBox(height: 16),
                _buildTalhaoSelectionCard(
                  title: '2. Selecione os Talhões de INVENTÁRIO', subtitle: 'A equação será aplicada nestes talhões.',
                  talhoesDisponiveis: _talhoesComInventarioDisponiveis, talhoesSelecionadosSet: _talhoesInventarioSelecionados,
                ),
                if (_analiseResult != null) ...[
                  _buildResultCard(_analiseResult!),
                  _buildProductionTable(_analiseResult!),
                  _buildProducaoComercialCard(_analiseResult!),
                  _buildVolumePorCodigoCard(_analiseResult!),
                ]
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isAnalyzing ? null : _gerarAnaliseCompleta,
        icon: _isAnalyzing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.functions),
        label: Text(_isAnalyzing ? 'Analisando...' : 'Gerar Análise Completa'),
      ),
    );
  }

  Widget _buildTalhaoSelectionCard({
    required String title, required String subtitle,
    required List<Talhao> talhoesDisponiveis, required Set<int> talhoesSelecionadosSet,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            Text(subtitle, style: const TextStyle(color: Colors.grey)),
            const Divider(),
            if (_isLoading) const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
            // <<< MUDANÇA 5: TEXTO DE AVISO ATUALIZADO >>>
            else if (_fazendaSelecionada == null) const Center(child: Text('Selecione um projeto, atividade e fazenda para ver os talhões.'))
            else if (talhoesDisponiveis.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(8.0), child: Text('Nenhum talhão com dados encontrado.')))
            else
              ListView.builder(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: talhoesDisponiveis.length,
                itemBuilder: (context, index) {
                  final talhao = talhoesDisponiveis[index];
                  return CheckboxListTile(
                    title: Text(talhao.nome), value: talhoesSelecionadosSet.contains(talhao.id!),
                    onChanged: (isSelected) {
                      setState(() {
                        if (isSelected == true) { talhoesSelecionadosSet.add(talhao.id!); }
                        else { talhoesSelecionadosSet.remove(talhao.id!); }
                      });
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildResultCard(AnaliseVolumetricaCompletaResult result) {
    return Card( elevation: 2, color: Colors.blueGrey.shade50, child: Padding( padding: const EdgeInsets.all(16.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text('Resultados da Regressão', style: Theme.of(context).textTheme.titleLarge), const Divider(), Text('Equação Gerada:', style: Theme.of(context).textTheme.titleMedium), SelectableText( result.resultadoRegressao['equacao'], style: const TextStyle(fontFamily: 'monospace', fontSize: 12, backgroundColor: Colors.black12), ), const SizedBox(height: 8), _buildStatRow('Coeficiente (R²):', (result.resultadoRegressao['R2'] as double).toStringAsFixed(4)), _buildStatRow('Nº de Amostras Usadas:', '${result.resultadoRegressao['n_amostras']}'), ], ), ), );
  }

  Widget _buildProductionTable(AnaliseVolumetricaCompletaResult result) {
    final totais = result.totaisInventario;
    return Card( elevation: 2, child: Padding( padding: const EdgeInsets.all(16.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text('Totais do Inventário', style: Theme.of(context).textTheme.titleLarge), const Divider(), _buildStatRow('Talhões Aplicados:', '${totais['talhoes']}'), _buildStatRow('Volume por Hectare:', '${(totais['volume_ha'] as double).toStringAsFixed(2)} m³/ha'), _buildStatRow('Árvores por Hectare:', '${totais['arvores_ha']}'), _buildStatRow('Área Basal por Hectare:', '${(totais['area_basal_ha'] as double).toStringAsFixed(2)} m²/ha'), const Divider(height: 15), _buildStatRow('Volume Total para ${(totais['area_total_lote'] as double).toStringAsFixed(2)} ha:', '${(totais['volume_total_lote'] as double).toStringAsFixed(2)} m³'), ], ), ), );
  }

  Widget _buildProducaoComercialCard(AnaliseVolumetricaCompletaResult result) {
    final data = result.producaoPorSortimento;
    if (data.isEmpty) return const SizedBox.shrink();
    
    final List<Color> colors = [
      Colors.blue.shade700,
      Colors.green.shade700,
      Colors.orange.shade700,
      Colors.red.shade700,
      Colors.purple.shade700
    ];

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Produção Comercial Estimada', style: Theme.of(context).textTheme.titleLarge),
            const Divider(),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: data.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return PieChartSectionData(
                      value: item.porcentagem,
                      title: '${item.nome}\n${item.porcentagem.toStringAsFixed(1)}%',
                      color: colors[index % colors.length],
                      radius: 80,
                      titleStyle: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    );
                  }).toList(),
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildDetailedTable(
              headers: ['Sortimento', 'Volume (m³/ha)', '% Total'],
              rows: data.map((item) => [
                item.nome,
                item.volumeHa.toStringAsFixed(2),
                '${item.porcentagem.toStringAsFixed(1)}%',
              ]).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumePorCodigoCard(AnaliseVolumetricaCompletaResult result) {
    final data = result.volumePorCodigo;
    if (data.isEmpty) return const SizedBox.shrink();

    final barGroups = data.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(toY: entry.value.volumeTotal, color: Colors.teal, width: 20, borderRadius: BorderRadius.circular(4))
        ],
      );
    }).toList();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Contribuição Volumétrica por Código', style: Theme.of(context).textTheme.titleLarge),
            const Divider(),
            SizedBox(height: 200, child: BarChart(
              BarChartData(
                barGroups: barGroups,
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) => Text(data[value.toInt()].codigo, style: const TextStyle(fontSize: 10)))),
                )
              )
            )),
            const SizedBox(height: 20),
            _buildDetailedTable(
              headers: ['Código', 'Volume (m³/ha)', '% Total'],
              rows: data.map((item) => [
                item.codigo,
                item.volumeTotal.toStringAsFixed(2),
                '${item.porcentagem.toStringAsFixed(1)}%',
              ]).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedTable({required List<String> headers, required List<List<String>> rows}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 24,
        headingRowHeight: 32,
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
        columns: headers.map((h) => DataColumn(label: Text(h, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
        rows: rows.map((row) => DataRow(
          cells: row.map((cell) => DataCell(Text(cell))).toList()
        )).toList(),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding( padding: const EdgeInsets.symmetric(vertical: 4.0), child: Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Expanded(child: Text(label, style: const TextStyle(color: Colors.black54))), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), ], ), );
  }
}
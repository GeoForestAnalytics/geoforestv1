// lib/pages/analises/analise_volumetrica_page.dart (VERSÃO FINAL - ESTILO NEON)

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

  // Estados para filtros
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

    _atividadesDisponiveis =
        await _atividadeRepository.getAtividadesDoProjeto(projeto!.id!);
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

    _fazendasDisponiveis =
        await _fazendaRepository.getFazendasDaAtividade(atividade!.id!);
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

  Future<void> _carregarTalhoesParaSelecao() async {
    if (_projetoSelecionado == null ||
        _atividadeSelecionada == null ||
        _fazendaSelecionada == null) return;

    final todosTalhoesDaFazendaInventario =
        await _talhaoRepository.getTalhoesDaFazenda(
            _fazendaSelecionada!.id, _fazendaSelecionada!.atividadeId);
    final talhoesCompletosInvIds = (await _talhaoRepository
            .getTalhoesComParcelasConcluidas())
        .map((t) => t.id)
        .toSet();
    final talhoesInventarioEncontrados = todosTalhoesDaFazendaInventario
        .where((t) => talhoesCompletosInvIds.contains(t.id))
        .toList();

    List<Talhao> talhoesCubagemEncontrados = [];
    final todasAtividadesDoProjeto =
        await _atividadeRepository.getAtividadesDoProjeto(_projetoSelecionado!.id!);
    final atividadeCub = todasAtividadesDoProjeto
        .cast<Atividade?>()
        .firstWhere((a) => a?.tipo.toUpperCase().contains('CUB') ?? false,
            orElse: () => null);

    if (atividadeCub != null) {
      final fazendasDaAtividadeCub =
          await _fazendaRepository.getFazendasDaAtividade(atividadeCub.id!);
      final fazendaCub = fazendasDaAtividadeCub
          .cast<Fazenda?>()
          .firstWhere((f) => f?.nome == _fazendaSelecionada!.nome,
              orElse: () => null);

      if (fazendaCub != null) {
        final todosTalhoesDaFazendaCub =
            await _talhaoRepository.getTalhoesDaFazenda(
                fazendaCub.id, fazendaCub.atividadeId);
        final todasCubagens = await _cubagemRepository.getTodasCubagens();
        final talhoesCompletosCubIds = todasCubagens
            .where((c) => c.alturaTotal > 0 && c.talhaoId != null)
            .map((c) => c.talhaoId!)
            .toSet();
        talhoesCubagemEncontrados = todosTalhoesDaFazendaCub
            .where((t) => talhoesCompletosCubIds.contains(t.id))
            .toList();
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
    if (_talhoesCubadosSelecionados.isEmpty ||
        _talhoesInventarioSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Selecione ao menos um talhão de cubagem E um de inventário.'),
          backgroundColor: Colors.orange));
      return;
    }
    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _limparResultados();
    });

    try {
      List<CubagemArvore> arvoresParaRegressao = [];
      for (final talhaoId in _talhoesCubadosSelecionados) {
        arvoresParaRegressao
            .addAll(await _cubagemRepository.getTodasCubagensDoTalhao(talhaoId));
      }

      List<Talhao> talhoesInventarioAnalisados = [];
      for (final talhaoId in _talhoesInventarioSelecionados) {
        final talhao = await _talhaoRepository.getTalhaoById(talhaoId);
        if (talhao != null) talhoesInventarioAnalisados.add(talhao);
      }

      final resultadoCompleto =
          await _analysisService.gerarAnaliseVolumetricaCompleta(
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
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  Future<void> _exportarPdf() async {
    if (_analiseResult == null) return;

    await _pdfService.gerarRelatorioVolumetricoPdf(
      context: context,
      resultadoRegressao: _analiseResult!.resultadoRegressao,
      diagnosticoRegressao: _analiseResult!.diagnosticoRegressao,
      producaoInventario: _analiseResult!.totaisInventario,
      producaoSortimento: _analiseResult!.producaoPorSortimento,
      volumePorCodigo: _analiseResult!.volumePorCodigo,
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
          ? Center(
              child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(_errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                  ),
              ),
            )
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
                          value: _projetoSelecionado,
                          hint: const Text('Selecione um Projeto'),
                          isExpanded: true,
                          items: _projetosDisponiveis
                              .map((p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(p.nome,
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: _onProjetoSelecionado,
                          decoration:
                              const InputDecoration(border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<Atividade>(
                          value: _atividadeSelecionada,
                          hint: const Text('Selecione uma Atividade'),
                          disabledHint:
                              const Text('Selecione um projeto primeiro'),
                          isExpanded: true,
                          items: _atividadesDisponiveis
                              .map((a) => DropdownMenuItem(
                                  value: a,
                                  child: Text(a.tipo,
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: _projetoSelecionado == null
                              ? null
                              : _onAtividadeSelecionada,
                          decoration:
                              const InputDecoration(border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<Fazenda>(
                          value: _fazendaSelecionada,
                          hint: const Text('Selecione uma Fazenda'),
                          disabledHint:
                              const Text('Selecione uma atividade primeiro'),
                          isExpanded: true,
                          items: _fazendasDisponiveis
                              .map((f) => DropdownMenuItem(
                                  value: f,
                                  child: Text(f.nome,
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: _atividadeSelecionada == null
                              ? null
                              : _onFazendaSelecionada,
                          decoration:
                              const InputDecoration(border: OutlineInputBorder()),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildTalhaoSelectionCard(
                  title: '1. Selecione os Talhões CUBADOS',
                  subtitle: 'Serão usados para gerar a equação de volume.',
                  talhoesDisponiveis: _talhoesComCubagemDisponiveis,
                  talhoesSelecionadosSet: _talhoesCubadosSelecionados,
                ),
                const SizedBox(height: 16),
                _buildTalhaoSelectionCard(
                  title: '2. Selecione os Talhões de INVENTÁRIO',
                  subtitle: 'A equação será aplicada nestes talhões.',
                  talhoesDisponiveis: _talhoesComInventarioDisponiveis,
                  talhoesSelecionadosSet: _talhoesInventarioSelecionados,
                ),
                if (_analiseResult != null) ...[
                  _buildResultCard(_analiseResult!.resultadoRegressao, _analiseResult!.diagnosticoRegressao),
                  _buildProductionTable(_analiseResult!),
                  
                  // GRAFICOS ATUALIZADOS AQUI
                  const SizedBox(height: 16),
                  _buildProducaoComercialCard(_analiseResult!),
                  const SizedBox(height: 16),
                  _buildVolumePorCodigoCard(_analiseResult!),
                ]
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isAnalyzing ? null : _gerarAnaliseCompleta,
        icon: _isAnalyzing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.functions),
        label: Text(_isAnalyzing ? 'Analisando...' : 'Gerar Análise Completa'),
      ),
    );
  }

  Widget _buildTalhaoSelectionCard({
    required String title,
    required String subtitle,
    required List<Talhao> talhoesDisponiveis,
    required Set<int> talhoesSelecionadosSet,
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
            if (_isLoading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator()))
            else if (_fazendaSelecionada == null)
              const Center(
                  child: Text(
                      'Selecione um projeto, atividade e fazenda para ver os talhões.'))
            else if (talhoesDisponiveis.isEmpty)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text('Nenhum talhão com dados encontrado.')))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: talhoesDisponiveis.length,
                itemBuilder: (context, index) {
                  final talhao = talhoesDisponiveis[index];
                  return CheckboxListTile(
                    title: Text(talhao.nome),
                    value: talhoesSelecionadosSet.contains(talhao.id!),
                    onChanged: (isSelected) {
                      setState(() {
                        if (isSelected == true) {
                          talhoesSelecionadosSet.add(talhao.id!);
                        } else {
                          talhoesSelecionadosSet.remove(talhao.id!);
                        }
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

  Widget _buildResultCard(Map<String, dynamic> resultados, Map<String, dynamic> diagnostico) {
    final syx = diagnostico['syx'] as double?;
    final syxPercent = diagnostico['syx_percent'] as double?;
    final shapiroPValue = diagnostico['shapiro_wilk_p_value'] as double?;

    String resultadoNormalidade;
    Color corNormalidade;

    if (shapiroPValue == null) {
      resultadoNormalidade = "N/A";
      corNormalidade = Colors.grey;
    } else if (shapiroPValue > 0.05) {
      resultadoNormalidade = "Aprovado (p > 0.05)";
      corNormalidade = Colors.green;
    } else {
      resultadoNormalidade = "Rejeitado (p <= 0.05)";
      corNormalidade = Colors.red;
    }

    return Card(
      elevation: 2,
      color: const Color.fromARGB(0, 29, 2, 73),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resultados da Regressão',
                style: Theme.of(context).textTheme.titleLarge),
            const Divider(),
            Text('Equação Gerada:',
                style: Theme.of(context).textTheme.titleMedium),
            SelectableText(
              resultados['equacao'],
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  backgroundColor: Color.fromARGB(103, 236, 235, 235)),
            ),
            const SizedBox(height: 12),
            _buildStatRow('Coeficiente (R²):',
                (resultados['R2'] as double).toStringAsFixed(4)),
            _buildStatRow(
                'Nº de Amostras Usadas:', '${resultados['n_amostras']}'),
            const Divider(height: 20),
            Text('Diagnóstico do Modelo',
                style: Theme.of(context).textTheme.titleMedium),
            _buildStatRow('Erro Padrão Residual (Syx):',
                syx?.toStringAsFixed(4) ?? "N/A"),
            _buildStatRow('Syx (%):',
                syxPercent != null ? '${syxPercent.toStringAsFixed(2)}%' : "N/A"),
            _buildStatRow('Normalidade (Shapiro-Wilk):',
                resultadoNormalidade,
                valueColor: corNormalidade),
          ],
        ),
      ),
    );
  }

  Widget _buildProductionTable(AnaliseVolumetricaCompletaResult result) {
    final totais = result.totaisInventario;
    return Card(
        elevation: 2,
        child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Totais do Inventário',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Divider(),
                  _buildStatRow('Talhões Aplicados:', '${totais['talhoes']}'),
                  _buildStatRow('Volume por Hectare:',
                      '${(totais['volume_ha'] as double).toStringAsFixed(2)} m³/ha'),
                  _buildStatRow(
                      'Árvores por Hectare:', '${totais['arvores_ha']}'),
                  _buildStatRow('Área Basal por Hectare:',
                      '${(totais['area_basal_ha'] as double).toStringAsFixed(2)} m²/ha'),
                  const Divider(height: 15),
                  _buildStatRow(
                      'Volume Total para ${(totais['area_total_lote'] as double).toStringAsFixed(2)} ha:',
                      '${(totais['volume_total_lote'] as double).toStringAsFixed(2)} m³'),
                ])));
  }

  // >>> GRÁFICO 1: PRODUÇÃO COMERCIAL (ATUALIZADO) <<<
  Widget _buildProducaoComercialCard(AnaliseVolumetricaCompletaResult result) {
    final data = result.producaoPorSortimento;
    if (data.isEmpty) return const SizedBox.shrink();

    // Configuração de Cores para Alto Contraste
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const Color corTexto = Colors.white;

    // Gradiente Ciano -> Azul
    final LinearGradient gradienteBarras = LinearGradient(
      colors: [Colors.cyan.shade300, Colors.blue.shade900],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    // Maior valor para definir altura do track
    final double maxY = data.map((e) => e.volumeHa).reduce((a, b) => a > b ? a : b);

    final barGroups = data.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
              toY: entry.value.volumeHa,
              gradient: gradienteBarras, // Gradiente aplicado
              width: 24,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
              // Fundo da barra
              backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY * 1.1,
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200,
              ),
          )
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
            Text('Produção Comercial Estimada',
                style: Theme.of(context).textTheme.titleLarge),
            const Divider(),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  barGroups: barGroups,
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= data.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: SizedBox(
                              width: 60,
                              child: Text(
                                data[value.toInt()].nome,
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: corTexto),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF1E293B), // Fundo Escuro Fixo
                      tooltipMargin: 8,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final item = data[groupIndex];
                        return BarTooltipItem(
                          '${item.nome}\n',
                          const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                          children: [
                            TextSpan(
                              text: '${item.volumeHa.toStringAsFixed(2)} m³/ha',
                              style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w900, fontSize: 16),
                            )
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildDetailedTable(
              corTexto: const Color.fromARGB(255, 4, 3, 61), // <--- AQUI VOCÊ ESCOLHE A COR AGORA
              headers: ['Sortimento', 'Volume (m³/ha)', '% Total'],
              rows: data
                  .map((item) => [
                        item.nome,
                        item.volumeHa.toStringAsFixed(2),
                        '${item.porcentagem.toStringAsFixed(1)}%',
                      ])
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  // >>> GRÁFICO 2: VOLUME POR CÓDIGO (ATUALIZADO) <<<
  Widget _buildVolumePorCodigoCard(AnaliseVolumetricaCompletaResult result) {
    final data = result.volumePorCodigo;
    if (data.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    const Color corTexto = Colors.white;

    // Gradiente Teal para diferenciar (mas ainda estilo Neon)
    final LinearGradient gradienteBarras = LinearGradient(
      colors: [Colors.teal.shade300, Colors.teal.shade900], 
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    final double maxY = data.map((e) => e.volumeTotal).reduce((a, b) => a > b ? a : b);

    final barGroups = data.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
              toY: entry.value.volumeTotal,
              gradient: gradienteBarras,
              width: 24,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
              backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY * 1.1,
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200,
              ),
          )
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
            Text('Contribuição Volumétrica por Código',
                style: Theme.of(context).textTheme.titleLarge),
            const Divider(),
            SizedBox(
                height: 220,
                child: BarChart(
                    BarChartData(
                  barGroups: barGroups,
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() >= data.length) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                    data[value.toInt()].codigo,
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: corTexto)
                                ),
                              );
                            }
                        ),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF1E293B), // Fundo Escuro Fixo
                      tooltipMargin: 8,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final item = data[groupIndex];
                        return BarTooltipItem(
                          '${item.codigo}\n',
                          const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                          children: [
                            TextSpan(
                              text: '${item.volumeTotal.toStringAsFixed(2)} m³',
                              style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.w900, fontSize: 16),
                            )
                          ],
                        );
                      },
                    ),
                  ),
                ))),
            const SizedBox(height: 20),
            _buildDetailedTable(
              headers: ['Código', 'Volume (m³/ha)', '% Total'],
              rows: data
                  .map((item) => [
                        item.codigo,
                        item.volumeTotal.toStringAsFixed(2),
                        '${item.porcentagem.toStringAsFixed(1)}%',
                      ])
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedTable({
  required List<String> headers,
  required List<List<String>> rows,
  Color corTexto = Colors.white, // Adicionamos a opção de cor (padrão branco)
}) {
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      columnSpacing: 24,
      headingRowHeight: 32,
      // Fundo do cabeçalho cinza claro
      headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
      columns: headers
          .map((h) => DataColumn(
              label: Text(h,
                  // Forçamos PRETO no cabeçalho para dar contraste com o fundo cinza claro
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black))))
          .toList(),
      rows: rows
          .map((row) => DataRow(
              cells: row
                  .map((cell) => DataCell(
                        // Aqui aplicamos a cor que você escolher
                        Text(cell, style: TextStyle(color: corTexto)), 
                      ))
                  .toList()))
          .toList(),
    ),
  );
}

  Widget _buildStatRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
              child: Text(label, style: const TextStyle(color: Colors.black54))),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15, color: valueColor)),
        ],
      ),
    );
  }
}
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart'; // Importante para firstWhereOrNull se necessário
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
  // Parâmetro opcional para receber talhões já selecionados (Estrato)
  final List<Talhao>? talhoesPreSelecionados;

  const AnaliseVolumetricaPage({
    super.key,
    this.talhoesPreSelecionados,
  });

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
    _inicializarPagina();
  }

  Future<void> _inicializarPagina() async {
    await _carregarProjetosIniciais();
    // Se vieram talhões pré-selecionados (do botão de Estrato), processa eles agora
    _processarPreSelecao();
  }

  Future<void> _carregarProjetosIniciais() async {
    setState(() => _isLoading = true);
    final projetos = await _projetoRepository.getTodosOsProjetosParaGerente();
    if (mounted) {
      setState(() {
        _projetosDisponiveis = projetos;
        _isLoading = false;
      });
    }
  }

  // --- LÓGICA DE PRÉ-SELEÇÃO (ESTRATO) ---
  void _processarPreSelecao() {
    if (widget.talhoesPreSelecionados != null && widget.talhoesPreSelecionados!.isNotEmpty) {
      setState(() {
        // 1. Popula a lista de inventário com o que veio da tela anterior
        _talhoesComInventarioDisponiveis = widget.talhoesPreSelecionados!;
        
        // 2. Marca todos como selecionados automaticamente
        for (var t in widget.talhoesPreSelecionados!) {
          if (t.id != null) _talhoesInventarioSelecionados.add(t.id!);
        }
        
        // 3. Tenta preencher os dropdowns (Projeto/Atividade/Fazenda) baseado no primeiro talhão
        // Isso ajuda o usuário a achar os talhões de Cubagem mais rápido.
        final primeiro = widget.talhoesPreSelecionados!.first;
        _autoSelecionarFiltros(primeiro);
      });
    }
  }

  Future<void> _autoSelecionarFiltros(Talhao talhaoExemplo) async {
    try {
      // Tenta achar e setar o Projeto
      final projetoId = talhaoExemplo.projetoId;
      if (projetoId != null) {
        final projeto = _projetosDisponiveis.firstWhereOrNull((p) => p.id == projetoId);
        if (projeto != null) {
          setState(() => _projetoSelecionado = projeto);
          
          // Carrega atividades deste projeto
          final atividades = await _atividadeRepository.getAtividadesDoProjeto(projeto.id!);
          setState(() => _atividadesDisponiveis = atividades);

          // Tenta achar e setar a Atividade
          final atividade = atividades.firstWhereOrNull((a) => a.id == talhaoExemplo.fazendaAtividadeId);
          if (atividade != null) {
            setState(() => _atividadeSelecionada = atividade);
            
            // Carrega fazendas desta atividade
            final fazendas = await _fazendaRepository.getFazendasDaAtividade(atividade.id!);
            setState(() => _fazendasDisponiveis = fazendas);

            // Tenta achar e setar a Fazenda
            final fazenda = fazendas.firstWhereOrNull((f) => f.id == talhaoExemplo.fazendaId);
            if (fazenda != null) {
              setState(() => _fazendaSelecionada = fazenda);
              // Carrega os talhões disponíveis, MAS preservando a lista de inventário que já temos
              await _carregarTalhoesParaSelecao(preservarInventario: true);
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Erro ao auto-selecionar filtros: $e");
    }
  }
  // ---------------------------------------

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

    final atividades = await _atividadeRepository.getAtividadesDoProjeto(projeto!.id!);
    if (mounted) {
      setState(() {
        _atividadesDisponiveis = atividades;
        _isLoading = false;
      });
    }
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

    final fazendas = await _fazendaRepository.getFazendasDaAtividade(atividade!.id!);
    if (mounted) {
      setState(() {
        _fazendasDisponiveis = fazendas;
        _isLoading = false;
      });
    }
  }

  Future<void> _onFazendaSelecionada(Fazenda? fazenda) async {
    setState(() {
      _fazendaSelecionada = fazenda;
      // Se não veio de pré-seleção, limpa as listas
      if (widget.talhoesPreSelecionados == null) {
        _talhoesComCubagemDisponiveis = [];
        _talhoesComInventarioDisponiveis = [];
        _talhoesCubadosSelecionados.clear();
        _talhoesInventarioSelecionados.clear();
      }
      _limparResultados();
      
      if (fazenda == null) {
        _isLoading = false;
        return;
      }
      _isLoading = true;
    });

    // Chama o carregamento normal
    await _carregarTalhoesParaSelecao(preservarInventario: widget.talhoesPreSelecionados != null);
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// Carrega talhões de Cubagem e Inventário baseados na seleção atual.
  /// Se [preservarInventario] for true, não sobrescreve a lista de inventário (útil para Estrato).
  Future<void> _carregarTalhoesParaSelecao({bool preservarInventario = false}) async {
    if (_projetoSelecionado == null || _atividadeSelecionada == null || _fazendaSelecionada == null) return;

    List<Talhao> talhoesInventarioEncontrados = [];
    
    // 1. Busca os talhões de INVENTÁRIO (da atividade selecionada) se necessário
    if (!preservarInventario) {
      final todosTalhoesDaFazendaInventario = await _talhaoRepository.getTalhoesDaFazenda(
          _fazendaSelecionada!.id, _fazendaSelecionada!.atividadeId);
      
      final talhoesCompletosInvIds = (await _talhaoRepository.getTalhoesComParcelasConcluidas())
          .map((t) => t.id)
          .toSet();
      
      talhoesInventarioEncontrados = todosTalhoesDaFazendaInventario
          .where((t) => talhoesCompletosInvIds.contains(t.id))
          .toList();
    }

    // 2. Busca os talhões de CUBAGEM (procurando a atividade irmã)
    List<Talhao> talhoesCubagemEncontrados = [];
    
    final todasAtividadesDoProjeto = await _atividadeRepository.getAtividadesDoProjeto(_projetoSelecionado!.id!);
    
    // Tenta encontrar uma atividade que contenha "CUB" no nome
    final atividadeCub = todasAtividadesDoProjeto
        .firstWhereOrNull((a) => a.tipo.toUpperCase().contains('CUB'));

    if (atividadeCub != null) {
      // Se achou a atividade de cubagem, busca a fazenda CORRESPONDENTE (pelo nome)
      final fazendasDaAtividadeCub = await _fazendaRepository.getFazendasDaAtividade(atividadeCub.id!);
      
      final fazendaCub = fazendasDaAtividadeCub
          .firstWhereOrNull((f) => f.nome == _fazendaSelecionada!.nome);

      if (fazendaCub != null) {
        // Se achou a fazenda na cubagem, pega os talhões dela
        final todosTalhoesDaFazendaCub = await _talhaoRepository.getTalhoesDaFazenda(fazendaCub.id, fazendaCub.atividadeId);
        
        final todasCubagens = await _cubagemRepository.getTodasCubagens();
        
        // Filtra talhões que tenham árvores com altura total > 0 (cubagem feita)
        final talhoesCompletosCubIds = todasCubagens
            .where((c) => c.alturaTotal > 0 && c.talhaoId != null)
            .map((c) => c.talhaoId!)
            .toSet();
            
        talhoesCubagemEncontrados = todosTalhoesDaFazendaCub
            .where((t) => talhoesCompletosCubIds.contains(t.id))
            .toList();
      }
    }

    if (mounted) {
      setState(() {
        if (!preservarInventario) {
          _talhoesComInventarioDisponiveis = talhoesInventarioEncontrados;
        }
        _talhoesComCubagemDisponiveis = talhoesCubagemEncontrados;
      });
    }
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
    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _limparResultados();
    });

    try {
      List<CubagemArvore> arvoresParaRegressao = [];
      for (final talhaoId in _talhoesCubadosSelecionados) {
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
    // CORES BASE (CONTRASTE)
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardColor = isDark ? const Color(0xFF1E293B) : Colors.white; 

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
                // --- CARD DE FILTROS ---
                Card(
                  elevation: 2,
                  color: cardColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        DropdownButtonFormField<Projeto>(
                          value: _projetoSelecionado,
                          hint: const Text('Selecione um Projeto'),
                          isExpanded: true,
                          items: _projetosDisponiveis.map((p) => DropdownMenuItem(value: p, child: Text(p.nome, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: _onProjetoSelecionado,
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<Atividade>(
                          value: _atividadeSelecionada,
                          hint: const Text('Selecione uma Atividade'),
                          disabledHint: const Text('Selecione um projeto primeiro'),
                          isExpanded: true,
                          items: _atividadesDisponiveis.map((a) => DropdownMenuItem(value: a, child: Text(a.tipo, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: _projetoSelecionado == null ? null : _onAtividadeSelecionada,
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<Fazenda>(
                          value: _fazendaSelecionada,
                          hint: const Text('Selecione uma Fazenda'),
                          disabledHint: const Text('Selecione uma atividade primeiro'),
                          isExpanded: true,
                          items: _fazendasDisponiveis.map((f) => DropdownMenuItem(value: f, child: Text(f.nome, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: _atividadeSelecionada == null ? null : _onFazendaSelecionada,
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // CARD 1: CUBAGEM
                _buildTalhaoSelectionCard(
                  title: '1. Selecione os Talhões CUBADOS',
                  subtitle: 'Serão usados para gerar a equação de volume.',
                  talhoesDisponiveis: _talhoesComCubagemDisponiveis,
                  talhoesSelecionadosSet: _talhoesCubadosSelecionados,
                  cardColor: cardColor,
                ),
                const SizedBox(height: 16),
                
                // CARD 2: INVENTÁRIO
                _buildTalhaoSelectionCard(
                  title: '2. Selecione os Talhões de INVENTÁRIO',
                  subtitle: 'A equação será aplicada nestes talhões.',
                  talhoesDisponiveis: _talhoesComInventarioDisponiveis,
                  talhoesSelecionadosSet: _talhoesInventarioSelecionados,
                  cardColor: cardColor,
                ),
                
                // RESULTADOS
                if (_analiseResult != null) ...[
                  const SizedBox(height: 16),
                  _buildResultCard(_analiseResult!.resultadoRegressao, _analiseResult!.diagnosticoRegressao, cardColor),
                  const SizedBox(height: 16),
                  _buildProductionTable(_analiseResult!, cardColor),
                  const SizedBox(height: 16),
                  _buildProducaoComercialCard(_analiseResult!, cardColor),
                  const SizedBox(height: 16),
                  _buildVolumePorCodigoCard(_analiseResult!, cardColor),
                ]
              ],
            ),
            
      // --- BOTÃO FLUTUANTE ---
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isAnalyzing ? null : _gerarAnaliseCompleta,
        icon: _isAnalyzing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: Color(0xFF023853), strokeWidth: 2))
            : const Icon(Icons.functions, color: Color(0xFF023853)),
        label: Text(_isAnalyzing ? 'Analisando...' : 'Gerar Análise Completa', style: const TextStyle(color: Color(0xFF023853), fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFEBE4AB), // Dourado
      ),
    );
  }

  Widget _buildTalhaoSelectionCard({
    required String title,
    required String subtitle,
    required List<Talhao> talhoesDisponiveis,
    required Set<int> talhoesSelecionadosSet,
    required Color cardColor,
  }) {
    return Card(
      elevation: 2,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            Text(subtitle, style: const TextStyle(color: Colors.grey)),
            const Divider(),
            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
            else if (_fazendaSelecionada == null && widget.talhoesPreSelecionados == null)
              const Center(child: Text('Selecione um projeto, atividade e fazenda para ver os talhões.'))
            else if (talhoesDisponiveis.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(8.0), child: Text('Nenhum talhão com dados encontrado.')))
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

  Widget _buildResultCard(Map<String, dynamic> resultados, Map<String, dynamic> diagnostico, Color cardColor) {
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
      elevation: 4,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resultados da Regressão',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(),
            Text('Equação Gerada:',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.withOpacity(0.3))
              ),
              child: SelectableText(
                resultados['equacao'],
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildStatRow('Coeficiente (R²):',
                (resultados['R2'] as double).toStringAsFixed(4)),
            _buildStatRow(
                'Nº de Amostras Usadas:', '${resultados['n_amostras']}'),
            const Divider(height: 24),
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

  Widget _buildProductionTable(AnaliseVolumetricaCompletaResult result, Color cardColor) {
    final totais = result.totaisInventario;
    return Card(
        elevation: 2,
        color: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Totais do Inventário',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
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

  // --- WIDGET DE GRÁFICO (Produção Comercial) ---
  Widget _buildProducaoComercialCard(AnaliseVolumetricaCompletaResult result, Color cardColor) {
    final data = result.producaoPorSortimento;
    if (data.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color corTextoEixo = isDark ? Colors.white70 : const Color(0xFF023853);

    final LinearGradient gradienteBarras = LinearGradient(
      colors: [Colors.cyan.shade300, Colors.blue.shade900],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
    
    double maxY = 0.0;
    if (data.isNotEmpty) {
       maxY = data.map((e) => e.volumeHa).reduce((a, b) => a > b ? a : b);
    }
    if (maxY == 0) maxY = 1.0;

    final barGroups = data.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
              toY: entry.value.volumeHa,
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
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Produção Comercial Estimada',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
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
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: corTextoEixo),
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
                      getTooltipColor: (_) => const Color(0xFF1E293B),
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
              headers: ['Sortimento', 'Volume (m³/ha)', '% Total'],
              rows: data
                  .map((item) => [
                        item.nome,
                        item.volumeHa.toStringAsFixed(2),
                        '${item.porcentagem.toStringAsFixed(1)}%',
                      ])
                  .toList(),
              corTexto: isDark ? Colors.white70 : Colors.black87,
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET DE GRÁFICO (Volume por Código) ---
  Widget _buildVolumePorCodigoCard(AnaliseVolumetricaCompletaResult result, Color cardColor) {
    final data = result.volumePorCodigo;
    if (data.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color corTextoEixo = isDark ? Colors.white70 : const Color(0xFF023853);

    final LinearGradient gradienteBarras = LinearGradient(
      colors: [Colors.teal.shade300, Colors.teal.shade900], 
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    double maxY = 0.0;
    if (data.isNotEmpty) {
      maxY = data.map((e) => e.volumeTotal).reduce((a, b) => a > b ? a : b);
    }
    if (maxY == 0) maxY = 1.0;

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
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Contribuição Volumétrica por Código',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
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
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: corTextoEixo)
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
              corTexto: isDark ? Colors.white70 : Colors.black87,
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET DE TABELA DETALHADA ---
  Widget _buildDetailedTable({
    required List<String> headers,
    required List<List<String>> rows,
    required Color corTexto,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color headerBg = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final Color headerText = isDark ? Colors.white : Colors.black;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 24,
        headingRowHeight: 32,
        headingRowColor: WidgetStateProperty.all(headerBg),
        columns: headers
            .map((h) => DataColumn(
                label: Text(h, style: TextStyle(fontWeight: FontWeight.bold, color: headerText))))
            .toList(),
        rows: rows
            .map((row) =>
                DataRow(cells: row.map((cell) => DataCell(Text(cell, style: TextStyle(color: corTexto)))).toList()))
            .toList(),
      ),
    );
  }

  // --- LINHA DE ESTATÍSTICA SIMPLES ---
  Widget _buildStatRow(String label, String value, {Color? valueColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color labelColor = isDark ? Colors.white70 : Colors.black54;
    final Color valColor = valueColor ?? (isDark ? Colors.white : Colors.black);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
              child: Text(label, style: TextStyle(color: labelColor))),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15, color: valColor)),
        ],
      ),
    );
  }
}
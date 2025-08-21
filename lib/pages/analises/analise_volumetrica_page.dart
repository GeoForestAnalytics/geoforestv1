// lib/pages/analises/analise_volumetrica_page.dart (VERSÃO CORRIGIDA COM FILTRO UNIFICADO)

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/services/analysis_service.dart';
import 'package:geoforestv1/services/pdf_service.dart';
// Repositórios
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/data/repositories/analise_repository.dart';
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
  final _analiseRepository = AnaliseRepository();
  final _analysisService = AnalysisService();
  final _pdfService = PdfService();

  // --- ESTADO DOS FILTROS (ATIVIDADE REMOVIDA) ---
  List<Projeto> _projetosDisponiveis = [];
  Projeto? _projetoSelecionado;
  List<Fazenda> _fazendasDisponiveis = [];
  Fazenda? _fazendaSelecionada;

  // --- LISTAS DE TALHÕES PARA SELEÇÃO ---
  List<Talhao> _talhoesComCubagemDisponiveis = [];
  List<Talhao> _talhoesComInventarioDisponiveis = [];

  // --- SELEÇÕES FINAIS ---
  final Set<int> _talhoesCubadosSelecionados = {};
  final Set<int> _talhoesInventarioSelecionados = {};

  // Estados para resultados e controle de UI
  Map<String, dynamic>? _resultadoRegressao;
  Map<String, dynamic>? _tabelaProducaoInventario;
  Map<String, dynamic>? _tabelaProducaoSortimento;
  bool _isLoading = true;
  bool _isAnalyzing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _carregarProjetosIniciais();
  }
  
  // --- LÓGICA DE CARREGAMENTO EM CASCATA (MODIFICADA) ---

  Future<void> _carregarProjetosIniciais() async {
    setState(() => _isLoading = true);
    _projetosDisponiveis = await _projetoRepository.getTodosOsProjetosParaGerente();
    setState(() => _isLoading = false);
  }

  Future<void> _onProjetoSelecionado(Projeto? projeto) async {
    setState(() {
      _projetoSelecionado = projeto;
      _fazendaSelecionada = null;
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

    // Lógica para buscar todas as fazendas únicas do projeto, independente da atividade
    final todasAtividades = await _atividadeRepository.getAtividadesDoProjeto(projeto!.id!);
    final Map<String, Fazenda> fazendasUnicas = {};
    for (final atividade in todasAtividades) {
      final fazendasDaAtividade = await _fazendaRepository.getFazendasDaAtividade(atividade.id!);
      for (final fazenda in fazendasDaAtividade) {
        fazendasUnicas.putIfAbsent(fazenda.nome, () => fazenda);
      }
    }
    
    _fazendasDisponiveis = fazendasUnicas.values.toList();
    _fazendasDisponiveis.sort((a, b) => a.nome.compareTo(b.nome));

    setState(() => _isLoading = false);
  }

  // A função _onAtividadeSelecionada foi REMOVIDA

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
    
    // Passamos o projeto e a fazenda para carregar os talhões de ambas as atividades
    await _carregarTalhoesParaSelecao(_projetoSelecionado!, fazenda!);
    setState(() => _isLoading = false);
  }

  Future<void> _carregarTalhoesParaSelecao(Projeto projeto, Fazenda fazendaSelecionada) async {
      // 1. Identifica as atividades de Cubagem e Inventário no projeto
      final todasAtividades = await _atividadeRepository.getAtividadesDoProjeto(projeto.id!);
      // ATENÇÃO: Confirme se os tipos de atividade são exatamente 'CUB' e 'IPC' no seu banco de dados
      final atividadeCub = todasAtividades.cast<Atividade?>().firstWhere((a) => a?.tipo == 'CUB', orElse: () => null);
      final atividadeIpc = todasAtividades.cast<Atividade?>().firstWhere((a) => a?.tipo == 'IPC', orElse: () => null);

      List<Talhao> talhoesCubagemEncontrados = [];
      List<Talhao> talhoesInventarioEncontrados = [];
      
      final talhoesCompletosInvIds = (await _talhaoRepository.getTalhoesComParcelasConcluidas()).map((t) => t.id).toSet();
      final todasCubagens = await _cubagemRepository.getTodasCubagens();
      final talhoesCompletosCubIds = todasCubagens.where((c) => c.alturaTotal > 0 && c.talhaoId != null).map((c) => c.talhaoId!).toSet();
      
      // 2. Busca talhões para a atividade de CUBAGEM
      if (atividadeCub != null) {
          final fazendasDaAtividade = await _fazendaRepository.getFazendasDaAtividade(atividadeCub.id!);
          final fazendaCub = fazendasDaAtividade.cast<Fazenda?>().firstWhere((f) => f?.nome == fazendaSelecionada.nome, orElse: () => null);
          if (fazendaCub != null) {
              final todosTalhoesDaFazenda = await _talhaoRepository.getTalhoesDaFazenda(fazendaCub.id, fazendaCub.atividadeId);
              talhoesCubagemEncontrados = todosTalhoesDaFazenda.where((t) => talhoesCompletosCubIds.contains(t.id)).toList();
          }
      }

      // 3. Busca talhões para a atividade de INVENTÁRIO (IPC)
      if (atividadeIpc != null) {
          final fazendasDaAtividade = await _fazendaRepository.getFazendasDaAtividade(atividadeIpc.id!);
          final fazendaIpc = fazendasDaAtividade.cast<Fazenda?>().firstWhere((f) => f?.nome == fazendaSelecionada.nome, orElse: () => null);
           if (fazendaIpc != null) {
              final todosTalhoesDaFazenda = await _talhaoRepository.getTalhoesDaFazenda(fazendaIpc.id, fazendaIpc.atividadeId);
              talhoesInventarioEncontrados = todosTalhoesDaFazenda.where((t) => talhoesCompletosInvIds.contains(t.id)).toList();
          }
      }

      // 4. Atualiza o estado com as listas encontradas
      setState(() {
          _talhoesComCubagemDisponiveis = talhoesCubagemEncontrados;
          _talhoesComInventarioDisponiveis = talhoesInventarioEncontrados;
      });
  }
  
  void _limparResultados() {
    setState(() {
        _resultadoRegressao = null;
        _tabelaProducaoInventario = null;
        _tabelaProducaoSortimento = null;
    });
  }

  // --- LÓGICA PRINCIPAL (sem alterações) ---
  Future<void> _gerarAnaliseCompleta() async {
    if (_talhoesCubadosSelecionados.isEmpty || _talhoesInventarioSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Selecione ao menos um talhão de cubagem E um de inventário.'),
          backgroundColor: Colors.orange));
      return;
    }
    setState(() { _isAnalyzing = true; _errorMessage = null; });
    try {
      List<CubagemArvore> arvoresParaRegressao = [];
      for(final talhaoId in _talhoesCubadosSelecionados) {
        final cubagensDoTalhao = await _cubagemRepository.getTodasCubagensDoTalhao(talhaoId);
        arvoresParaRegressao.addAll(cubagensDoTalhao);
      }
      final resultadoRegressao = await _analysisService.gerarEquacaoSchumacherHall(arvoresParaRegressao);
      if (resultadoRegressao.containsKey('error')) {
        throw Exception(resultadoRegressao['error']);
      }
      double volumeTotalLote = 0;
      double areaTotalLote = 0;
      double areaBasalMediaPonderada = 0;
      int arvoresHaMediaPonderada = 0;
      List<Talhao> talhoesInventarioAnalisados = [];
      for (final talhaoId in _talhoesInventarioSelecionados) {
          final talhao = await _talhaoRepository.getTalhaoById(talhaoId);
          if (talhao == null) continue;
          talhoesInventarioAnalisados.add(talhao);
          final dadosAgregados = await _analiseRepository.getDadosAgregadosDoTalhao(talhaoId); 
          final List<Parcela> parcelas = dadosAgregados['parcelas'];
          final List<Arvore> arvores = dadosAgregados['arvores'];
          if (parcelas.isEmpty || arvores.isEmpty) continue;
          final arvoresComVolume = _analysisService.aplicarEquacaoDeVolume(
            arvoresDoInventario: arvores,
            b0: resultadoRegressao['b0'], b1: resultadoRegressao['b1'], b2: resultadoRegressao['b2'],
          );
          final analiseTalhao = _analysisService.getTalhaoInsights(parcelas, arvoresComVolume);
          if (talhao.areaHa != null && talhao.areaHa! > 0) {
              volumeTotalLote += (analiseTalhao.volumePorHectare * talhao.areaHa!);
              areaTotalLote += talhao.areaHa!;
              areaBasalMediaPonderada += (analiseTalhao.areaBasalPorHectare * talhao.areaHa!);
              arvoresHaMediaPonderada += (analiseTalhao.arvoresPorHectare * talhao.areaHa!).round();
          }
      }
      final Map<String, double> volumesAcumuladosSortimento = {};
      for (final arvoreCubada in arvoresParaRegressao) {
        if (arvoreCubada.id == null) continue;
        final secoes = await _cubagemRepository.getSecoesPorArvoreId(arvoreCubada.id!);
        final volumePorSortimento = _analysisService.classificarSortimentos(secoes);
        volumePorSortimento.forEach((sortimento, volume) {
          volumesAcumuladosSortimento.update(sortimento, (value) => value + volume, ifAbsent: () => volume);
        });
      }
      double volumeTotalCubado = volumesAcumuladosSortimento.values.fold(0.0, (a, b) => a + b);
      final Map<String, double> porcentagensSortimento = {};
      if(volumeTotalCubado > 0) {
        volumesAcumuladosSortimento.forEach((sortimento, volume) {
          porcentagensSortimento[sortimento] = (volume / volumeTotalCubado) * 100;
        });
      }
      if (mounted) {
        setState(() {
          _resultadoRegressao = resultadoRegressao;
          _tabelaProducaoInventario = {
            'talhoes': talhoesInventarioAnalisados.map((t) => t.nome).join(', '),
            'volume_ha': areaTotalLote > 0 ? volumeTotalLote / areaTotalLote : 0.0,
            'arvores_ha': areaTotalLote > 0 ? (arvoresHaMediaPonderada / areaTotalLote).round() : 0,
            'area_basal_ha': areaTotalLote > 0 ? areaBasalMediaPonderada / areaTotalLote : 0.0,
            'volume_total_lote': volumeTotalLote,
            'area_total_lote': areaTotalLote,
          };
          _tabelaProducaoSortimento = { 'porcentagens': porcentagensSortimento };
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Erro na análise: ${e.toString()}";
          _isAnalyzing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Análise Volumétrica'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: (_resultadoRegressao == null || _isAnalyzing) ? null : () {
              _pdfService.gerarRelatorioVolumetricoPdf(
                context: context,
                resultadoRegressao: _resultadoRegressao!,
                producaoInventario: _tabelaProducaoInventario!,
                producaoSortimento: _tabelaProducaoSortimento!,
              );
            },
            tooltip: 'Exportar Relatório (PDF)',
          ),
        ],
      ),
      body: _errorMessage != null
          ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
              children: [
                // <<< FILTROS UNIFICADOS: PROJETO E FAZENDA >>>
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
                          items: _projetosDisponiveis.map((p) => DropdownMenuItem(value: p, child: Text(p.nome, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: _onProjetoSelecionado,
                          decoration: const InputDecoration(border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 10),
                        // O DROPDOWN DE ATIVIDADE FOI REMOVIDO
                        DropdownButtonFormField<Fazenda>(
                          value: _fazendaSelecionada,
                          hint: const Text('Selecione uma Fazenda'),
                          isExpanded: true,
                          items: _fazendasDisponiveis.map((f) => DropdownMenuItem(value: f, child: Text(f.nome, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: _projetoSelecionado == null ? null : _onFazendaSelecionada,
                          decoration: const InputDecoration(border: OutlineInputBorder()),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Seção de Talhões de Cubagem
                _buildTalhaoSelectionCard(
                  title: '1. Selecione os Talhões CUBADOS',
                  subtitle: 'Serão usados para gerar a equação de volume.',
                  talhoesDisponiveis: _talhoesComCubagemDisponiveis,
                  talhoesSelecionadosSet: _talhoesCubadosSelecionados,
                ),
                const SizedBox(height: 16),

                // Seção de Talhões de Inventário
                _buildTalhaoSelectionCard(
                  title: '2. Selecione os Talhões de INVENTÁRIO',
                  subtitle: 'A equação será aplicada nestes talhões.',
                  talhoesDisponiveis: _talhoesComInventarioDisponiveis,
                  talhoesSelecionadosSet: _talhoesInventarioSelecionados,
                ),

                // Cards de Resultado (sem alteração)
                if (_resultadoRegressao != null) _buildResultCard(),
                if (_tabelaProducaoInventario != null) _buildProductionTable(),
                if (_tabelaProducaoSortimento != null) _buildSortmentTable(),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isAnalyzing ? null : _gerarAnaliseCompleta,
        icon: _isAnalyzing
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.functions),
        label: Text(_isAnalyzing ? 'Analisando...' : 'Gerar Análise Completa'),
      ),
    );
  }

  // <<< WIDGET PARA A LISTA DE SELEÇÃO DE TALHÕES (sem alteração) >>>
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
              const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
            else if (_fazendaSelecionada == null)
              const Center(child: Text('Selecione uma fazenda para ver os talhões.'))
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
  
  // --- Widgets de Resultado (sem alteração) ---
  Widget _buildResultCard() {
    if (_resultadoRegressao == null) return const SizedBox.shrink();
    return Card( elevation: 2, color: Colors.blueGrey.shade50, child: Padding( padding: const EdgeInsets.all(16.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text('Resultados da Regressão', style: Theme.of(context).textTheme.titleLarge), const Divider(), Text('Equação Gerada:', style: Theme.of(context).textTheme.titleMedium), SelectableText( _resultadoRegressao!['equacao'], style: const TextStyle(fontFamily: 'monospace', fontSize: 12, backgroundColor: Colors.black12), ), const SizedBox(height: 8), _buildStatRow('Coeficiente (R²):', (_resultadoRegressao!['R2'] as double).toStringAsFixed(4)), _buildStatRow('Nº de Amostras Usadas:', '${_resultadoRegressao!['n_amostras']}'), ], ), ), );
  }
  Widget _buildProductionTable() {
    if (_tabelaProducaoInventario == null) return const SizedBox.shrink();
    return Card( elevation: 2, child: Padding( padding: const EdgeInsets.all(16.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text('Totais do Inventário', style: Theme.of(context).textTheme.titleLarge), const Divider(), _buildStatRow('Talhões Aplicados:', '${_tabelaProducaoInventario!['talhoes']}'), _buildStatRow('Volume por Hectare:', '${(_tabelaProducaoInventario!['volume_ha'] as double).toStringAsFixed(2)} m³/ha'), _buildStatRow('Árvores por Hectare:', '${_tabelaProducaoInventario!['arvores_ha']}'), _buildStatRow('Área Basal por Hectare:', '${(_tabelaProducaoInventario!['area_basal_ha'] as double).toStringAsFixed(2)} m²/ha'), const Divider(height: 15), _buildStatRow('Volume Total para ${(_tabelaProducaoInventario!['area_total_lote'] as double).toStringAsFixed(2)} ha:', '${(_tabelaProducaoInventario!['volume_total_lote'] as double).toStringAsFixed(2)} m³'), ], ), ), );
  }
  Widget _buildSortmentTable() {
    if (_tabelaProducaoSortimento == null) return const SizedBox.shrink();
    final Map<String, double> porcentagens = _tabelaProducaoSortimento!['porcentagens'];
    return Card( elevation: 2, child: Padding( padding: const EdgeInsets.all(16.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text('Produção por Sortimento (Média)', style: Theme.of(context).textTheme.titleLarge), const Divider(), ...porcentagens.entries.map((entry) => _buildStatRow('${entry.key}:', '${entry.value.toStringAsFixed(1)}%')), ], ), ), );
  }
  Widget _buildStatRow(String label, String value) {
    return Padding( padding: const EdgeInsets.symmetric(vertical: 4.0), child: Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Expanded(child: Text(label, style: const TextStyle(color: Colors.black54))), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), ], ), );
  }
}
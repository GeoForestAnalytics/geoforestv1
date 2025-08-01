// lib/pages/analises/analise_volumetrica_page.dart (VERSÃO ESTRUTURALMENTE CORRETA)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Imports do projeto
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:geoforestv1/services/analysis_service.dart';
import 'package:geoforestv1/services/pdf_service.dart';

// Repositórios
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/data/repositories/analise_repository.dart';

class AnaliseVolumetricaPage extends StatefulWidget {
  const AnaliseVolumetricaPage({super.key});

  @override
  State<AnaliseVolumetricaPage> createState() => _AnaliseVolumetricaPageState();
}

class _AnaliseVolumetricaPageState extends State<AnaliseVolumetricaPage> {
  // Repositórios e Serviços
  final _projetoRepository = ProjetoRepository();
  final _talhaoRepository = TalhaoRepository();
  final _cubagemRepository = CubagemRepository();
  final _analysisService = AnalysisService();
  final _pdfService = PdfService();
  final _analiseRepository = AnaliseRepository(); // << REPOSITÓRIO FALTANDO

  // Estados para o Filtro
  List<Projeto> _projetosDisponiveis = [];
  Projeto? _projetoSelecionado;

  // Estados para as listas de dados
  List<Talhao> _talhoesComCubagem = [];
  List<Talhao> _talhoesComInventario = [];
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _carregarDadosIniciais();
    });
  }

  Future<void> _carregarDadosIniciais() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final licenseProvider = context.read<LicenseProvider>();
      if (licenseProvider.licenseData == null) throw Exception("Dados da licença não encontrados.");
      
      final licenseId = licenseProvider.licenseData!.id;
      final isGerente = licenseProvider.licenseData!.cargo == 'gerente';

      final projetos = isGerente
          ? await _projetoRepository.getTodosOsProjetosParaGerente()
          : await _projetoRepository.getTodosProjetos(licenseId);
      final projetosAtivos = projetos.where((p) => p.status == 'ativo').toList();

      final todosOsTalhoes = await _talhaoRepository.getTodosOsTalhoes();
      final todasCubagens = await _cubagemRepository.getTodasCubagens();
      final idsTalhoesComCubagem = todasCubagens.map((a) => a.talhaoId).where((id) => id != null).toSet();
      
      final talhoesComInventarioConcluido = await _talhaoRepository.getTalhoesComParcelasConcluidas();
      final idsTalhoesComInventario = talhoesComInventarioConcluido.map((t) => t.id).toSet();

      final talhoesFiltradosComCubagem = todosOsTalhoes.where((t) => idsTalhoesComCubagem.contains(t.id)).toList();
      final talhoesFiltradosComInventario = todosOsTalhoes.where((t) => idsTalhoesComInventario.contains(t.id)).toList();

      if (mounted) {
        setState(() {
          _projetosDisponiveis = projetosAtivos;
          _talhoesComCubagem = talhoesFiltradosComCubagem;
          _talhoesComInventario = talhoesFiltradosComInventario;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = "Erro ao carregar dados: $e");
    } finally {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    }
  }

  void _onFilterChanged(Projeto? novoProjeto) {
    setState(() {
      _projetoSelecionado = novoProjeto;
      _talhoesCubadosSelecionados.clear();
      _talhoesInventarioSelecionados.clear();
      _resultadoRegressao = null;
      _tabelaProducaoInventario = null;
      _tabelaProducaoSortimento = null;
    });
  }

  Future<void> _gerarAnaliseCompleta() async {
    if (_talhoesCubadosSelecionados.isEmpty || _talhoesInventarioSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Selecione ao menos um talhão de cubagem E um de inventário.'),
          backgroundColor: Colors.orange));
      return;
    }

    setState(() { _isAnalyzing = true; _errorMessage = null; });

    try {
      // ETAPA 1: GERAR A EQUAÇÃO DE VOLUME
      List<CubagemArvore> arvoresParaRegressao = [];
      for(final talhaoId in _talhoesCubadosSelecionados) {
        final cubagensDoTalhao = await _cubagemRepository.getTodasCubagensDoTalhao(talhaoId);
        arvoresParaRegressao.addAll(cubagensDoTalhao);
      }
      
      final resultadoRegressao = await _analysisService.gerarEquacaoSchumacherHall(arvoresParaRegressao);
      if (resultadoRegressao.containsKey('error')) {
        throw Exception(resultadoRegressao['error']);
      }
      
      // ETAPA 2: APLICAR A EQUAÇÃO E CALCULAR TOTAIS DO INVENTÁRIO
      double volumeTotalLote = 0;
      double areaTotalLote = 0;
      double areaBasalMediaPonderada = 0;
      int arvoresHaMediaPonderada = 0;
      List<Talhao> talhoesInventarioAnalisados = [];

      for (final talhaoId in _talhoesInventarioSelecionados) {
          final talhao = _talhoesComInventario.firstWhere((t) => t.id == talhaoId);
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
              volumeTotalLote += (analiseTalhao.volumePorHectare * talhao.areaHa!); // Corrigido de .volumePorHectar
              areaTotalLote += talhao.areaHa!;
              areaBasalMediaPonderada += (analiseTalhao.areaBasalPorHectare * talhao.areaHa!);
              arvoresHaMediaPonderada += (analiseTalhao.arvoresPorHectare * talhao.areaHa!).round();
          }
      }
      
      // ETAPA 3: CALCULAR O SORTIMENTO MÉDIO
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

      // ETAPA 4: ATUALIZAR O ESTADO DA UI
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
  
  // <<< TODOS OS MÉTODOS DE BUILD AGORA ESTÃO DENTRO DA CLASSE >>>
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
                producaoSortimento: _tabelaProducaoSortimento!
              );
            },
            tooltip: 'Exportar Relatório (PDF)',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
              : _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isAnalyzing ? null : _gerarAnaliseCompleta,
        icon: _isAnalyzing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.functions),
        label: Text(_isAnalyzing ? 'Analisando...' : 'Gerar Análise Completa'),
      ),
    );
  }

  Widget _buildBody() {
    final List<Talhao> talhoesCubadosParaExibir = _projetoSelecionado == null
        ? _talhoesComCubagem
        : _talhoesComCubagem.where((t) => t.projetoId == _projetoSelecionado!.id).toList();

    final List<Talhao> talhoesInventarioParaExibir = _projetoSelecionado == null
        ? _talhoesComInventario
        : _talhoesComInventario.where((t) => t.projetoId == _projetoSelecionado!.id).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: DropdownButtonFormField<Projeto?>(
            value: _projetoSelecionado,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Filtrar por Projeto',
              border: const OutlineInputBorder(),
              suffixIcon: _projetoSelecionado != null ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _onFilterChanged(null)) : null,
            ),
            hint: const Text('Mostrar todos os projetos'),
            items: [
              const DropdownMenuItem<Projeto?>( value: null, child: Text('Mostrar todos os projetos')),
              ..._projetosDisponiveis.map((projeto) {
                return DropdownMenuItem(value: projeto, child: Text(projeto.nome, overflow: TextOverflow.ellipsis));
              }).toList(),
            ],
            onChanged: _onFilterChanged,
          ),
        ),
        _buildSelectionCard(
            '1. Selecione os Talhões CUBADOS',
            'Serão usados para gerar a equação de volume.',
            talhoesCubadosParaExibir,
            _talhoesCubadosSelecionados,
            (id, selected) => setState(() => selected ? _talhoesCubadosSelecionados.add(id) : _talhoesCubadosSelecionados.remove(id)) 
        ),
        const SizedBox(height: 16),
        _buildSelectionCard(
            '2. Selecione os Talhões de INVENTÁRIO',
            'A equação será aplicada nestes talhões.',
            talhoesInventarioParaExibir,
            _talhoesInventarioSelecionados,
            (id, selected) => setState(() => selected ? _talhoesInventarioSelecionados.add(id) : _talhoesInventarioSelecionados.remove(id))) ,
        
        if (_resultadoRegressao != null) _buildResultCard(),
        if (_tabelaProducaoInventario != null) _buildProductionTable(),
        if (_tabelaProducaoSortimento != null) _buildSortmentTable(),
      ],
    );
  }
  
  Widget _buildSelectionCard(String title, String subtitle, List<Talhao> talhoes, Set<int> selectionSet, Function(int, bool) onSelect) {
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
            if (talhoes.isEmpty) const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Nenhum talhão disponível para este filtro.'),
            ),
            ...talhoes.map((talhao) {
              return CheckboxListTile(
                title: Text(talhao.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(talhao.fazendaNome ?? 'Fazenda desc.'),
                value: selectionSet.contains(talhao.id!),
                onChanged: (val) => onSelect(talhao.id!, val ?? false),
              );
            }),
          ],
        ),
      ),
    );
  }
  
  Widget _buildResultCard() {
    if (_resultadoRegressao == null) return const SizedBox.shrink();
    return Card(
      elevation: 2,
      color: Colors.blueGrey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resultados da Regressão', style: Theme.of(context).textTheme.titleLarge),
            const Divider(),
            Text('Equação Gerada:', style: Theme.of(context).textTheme.titleMedium),
            SelectableText(
              _resultadoRegressao!['equacao'],
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, backgroundColor: Colors.black12),
            ),
            const SizedBox(height: 8),
            _buildStatRow('Coeficiente (R²):', (_resultadoRegressao!['R2'] as double).toStringAsFixed(4)),
            _buildStatRow('Nº de Amostras Usadas:', '${_resultadoRegressao!['n_amostras']}'),
          ],
        ),
      ),
    );
  }

  Widget _buildProductionTable() {
    if (_tabelaProducaoInventario == null) return const SizedBox.shrink();
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Totais do Inventário', style: Theme.of(context).textTheme.titleLarge),
            const Divider(),
            _buildStatRow('Talhões Aplicados:', '${_tabelaProducaoInventario!['talhoes']}'),
            _buildStatRow('Volume por Hectare:', '${(_tabelaProducaoInventario!['volume_ha'] as double).toStringAsFixed(2)} m³/ha'),
            _buildStatRow('Árvores por Hectare:', '${_tabelaProducaoInventario!['arvores_ha']}'),
            _buildStatRow('Área Basal por Hectare:', '${(_tabelaProducaoInventario!['area_basal_ha'] as double).toStringAsFixed(2)} m²/ha'),
            const Divider(height: 15),
            _buildStatRow('Volume Total para ${(_tabelaProducaoInventario!['area_total_lote'] as double).toStringAsFixed(2)} ha:', '${(_tabelaProducaoInventario!['volume_total_lote'] as double).toStringAsFixed(2)} m³'),
          ],
        ),
      ),
    );
  }

  Widget _buildSortmentTable() {
    if (_tabelaProducaoSortimento == null) return const SizedBox.shrink();
    final Map<String, double> porcentagens = _tabelaProducaoSortimento!['porcentagens'];
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Produção por Sortimento (Média)', style: Theme.of(context).textTheme.titleLarge),
            const Divider(),
            ...porcentagens.entries.map((entry) => _buildStatRow('${entry.key}:', '${entry.value.toStringAsFixed(1)}%')),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.black54))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }
}
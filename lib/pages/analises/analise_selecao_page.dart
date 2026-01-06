// lib/pages/analises/analise_selecao_page.dart

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/models/enums.dart'; 
import 'package:geoforestv1/pages/dashboard/relatorio_comparativo_page.dart'; 
import 'package:geoforestv1/pages/analises/analise_volumetrica_page.dart';
import 'package:geoforestv1/pages/dashboard/estrato_dashboard_page.dart';

// Repositórios e Serviços
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/data/repositories/fazenda_repository.dart';
import 'package:geoforestv1/data/repositories/analise_repository.dart';
import 'package:geoforestv1/services/ai_validation_service.dart'; 
import 'package:geoforestv1/services/analysis_service.dart';
import 'package:geoforestv1/services/pdf_service.dart'; 
import 'package:geoforestv1/widgets/progress_dialog.dart';
import 'package:geoforestv1/widgets/chat_ia_dialog.dart'; 

class AnaliseSelecaoPage extends StatefulWidget {
  const AnaliseSelecaoPage({super.key});

  @override
  State<AnaliseSelecaoPage> createState() => _AnaliseSelecaoPageState();
}

class _AnaliseSelecaoPageState extends State<AnaliseSelecaoPage> {
  final _projetoRepository = ProjetoRepository();
  final _atividadeRepository = AtividadeRepository();
  final _fazendaRepository = FazendaRepository();
  final _talhaoRepository = TalhaoRepository();
  final _analiseRepository = AnaliseRepository();
  final _analysisService = AnalysisService();
  final _pdfService = PdfService();

  List<Projeto> _projetosDisponiveis = [];
  List<Atividade> _atividadesDisponiveis = [];
  List<Fazenda> _fazendasDisponiveis = [];
  List<Talhao> _talhoesDisponiveis = [];

  Projeto? _projetoSelecionado;
  Atividade? _atividadeSelecionada;
  Fazenda? _fazendaSelecionada;

  final Set<int> _talhoesSelecionados = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarProjetos();
  }

  // --- LÓGICA DE DADOS ---

  Future<void> _carregarProjetos() async {
    setState(() => _isLoading = true);
    final talhoesCompletos = await _talhaoRepository.getTalhoesComParcelasConcluidas();
    if (talhoesCompletos.isEmpty) {
       if(mounted) setState(() { _projetosDisponiveis = []; _isLoading = false; });
       return;
    }
    final todosProjetos = await _projetoRepository.getTodosOsProjetosParaGerente();
    final projetosIdsComDados = talhoesCompletos.map((t) => t.projetoId).toSet();
    
    if (mounted) {
      setState(() {
        _projetosDisponiveis = todosProjetos.where((p) => projetosIdsComDados.contains(p.id)).toList();
        _isLoading = false;
      });
    }
  }

  Future<void> _onProjetoSelecionado(dynamic projeto) async {
    final p = projeto as Projeto?;
    setState(() {
      _projetoSelecionado = p;
      _atividadeSelecionada = null;
      _fazendaSelecionada = null;
      _atividadesDisponiveis = [];
      _fazendasDisponiveis = [];
      _talhoesDisponiveis = [];
      _talhoesSelecionados.clear();
    });
    if (p == null) return;
    setState(() => _isLoading = true);
    final atividades = await _atividadeRepository.getAtividadesDoProjeto(p.id!);
    final tiposInventario = ["IPC", "IFC", "IFS", "BIO", "IFQ"];
    _atividadesDisponiveis = atividades.where((a) => tiposInventario.any((tipo) => a.tipo.toUpperCase().contains(tipo))).toList();
    setState(() => _isLoading = false);
  }

  Future<void> _onAtividadeSelecionada(dynamic atividade) async {
    final a = atividade as Atividade?;
    setState(() {
      _atividadeSelecionada = a;
      _fazendaSelecionada = null;
      _fazendasDisponiveis = [];
      _talhoesDisponiveis = [];
      _talhoesSelecionados.clear();
    });
    if (a == null) return;
    setState(() => _isLoading = true);
    _fazendasDisponiveis = await _fazendaRepository.getFazendasDaAtividade(a.id!);
    setState(() => _isLoading = false);
  }

  Future<void> _onFazendaSelecionada(dynamic fazenda) async {
    final f = fazenda as Fazenda?;
    setState(() {
      _fazendaSelecionada = f;
      _talhoesDisponiveis = [];
      _talhoesSelecionados.clear();
    });
    if (f == null) return;
    setState(() => _isLoading = true);
    final todosTalhoes = await _talhaoRepository.getTalhoesDaFazenda(f.id, f.atividadeId);
    final concluidosIds = (await _talhaoRepository.getTalhoesComParcelasConcluidas()).map((t) => t.id).toSet();
    _talhoesDisponiveis = todosTalhoes.where((t) => concluidosIds.contains(t.id)).toList();
    setState(() => _isLoading = false);
  }

  void _toggleTalhao(int talhaoId, bool? isSelected) {
    if (isSelected == null) return;
    setState(() => isSelected ? _talhoesSelecionados.add(talhaoId) : _talhoesSelecionados.remove(talhaoId));
  }

  // --- MÉTODOS DE NAVEGAÇÃO ---

  void _gerarAnaliseEstrato() {
    if (_talhoesSelecionados.isEmpty) return;
    final selecionados = _talhoesDisponiveis.where((t) => _talhoesSelecionados.contains(t.id)).toList();
    Navigator.push(context, MaterialPageRoute(builder: (ctx) => EstratoDashboardPage(talhoesSelecionados: selecionados)));
  }

  void _gerarRelatorioComparativo() {
    if (_talhoesSelecionados.isEmpty) return;
    final selecionados = _talhoesDisponiveis.where((t) => _talhoesSelecionados.contains(t.id)).toList();
    Navigator.push(context, MaterialPageRoute(builder: (ctx) => RelatorioComparativoPage(talhoesSelecionados: selecionados)));
  }

  void _navegarParaAnaliseVolumetrica() {
    if (_talhoesSelecionados.isEmpty) {
       Navigator.push(context, MaterialPageRoute(builder: (ctx) => const AnaliseVolumetricaPage()));
    } else {
       final selecionados = _talhoesDisponiveis.where((t) => _talhoesSelecionados.contains(t.id)).toList();
       Navigator.push(context, MaterialPageRoute(builder: (ctx) => AnaliseVolumetricaPage(talhoesPreSelecionados: selecionados)));
    }
  }

  // --- GERAÇÃO DE PLANOS DE CUBAGEM (ESTRATO) ---

  Future<void> _gerarPlanosDeCubagemParaEstrato() async {
    if (_talhoesSelecionados.isEmpty) return;

    final selecionados = _talhoesDisponiveis.where((t) => _talhoesSelecionados.contains(t.id)).toList();
    
    final config = await _mostrarDialogoConfiguracaoLote();
    if (config == null) return;

    if (!mounted) return;
    ProgressDialog.show(context, 'Gerando Atividades e Planos de Cubagem...');

    try {
      final planosGerados = await _analysisService.criarMultiplasAtividadesDeCubagem(
        talhoes: selecionados,
        metodo: config.metodoDistribuicao,
        quantidade: config.quantidade,
        metodoCubagem: config.metodoCubagem,
        metrica: config.metricaDistribuicao,
        isIntervaloManual: config.isIntervaloManual,
        intervaloManual: config.intervaloManual,
      );

      if (!mounted) return;
      ProgressDialog.hide(context);

      if (planosGerados.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nenhum plano foi gerado. Verifique os dados dos talhões.'),
          backgroundColor: Colors.orange,
        ));
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Atividades criadas com sucesso! Gerando PDF...'),
        backgroundColor: Colors.green,
      ));

      await _pdfService.gerarPdfUnificadoDePlanosDeCubagem(
        context: context, 
        planosPorTalhao: planosGerados,
        metrica: config.metricaDistribuicao,
      );

    } catch (e) {
      if (mounted) {
        ProgressDialog.hide(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao gerar cubagem: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<PlanoConfig?> _mostrarDialogoConfiguracaoLote() async {
    final quantidadeController = TextEditingController(text: "20");
    final intervaloController = TextEditingController(); 
    final formKey = GlobalKey<FormState>();
    
    MetodoDistribuicaoCubagem metodoDistribuicao = MetodoDistribuicaoCubagem.fixoPorTalhao;
    String metodoCubagem = 'Fixas';
    MetricaDistribuicao metricaSelecionada = MetricaDistribuicao.dap; 
    bool isIntervaloManual = false;

    return showDialog<PlanoConfig>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Configurar Cubagem do Estrato'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('1. Métrica Base', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SegmentedButton<MetricaDistribuicao>(
                        segments: const [
                          ButtonSegment(value: MetricaDistribuicao.dap, label: Text('DAP')),
                          ButtonSegment(value: MetricaDistribuicao.cap, label: Text('CAP')),
                        ],
                        selected: {metricaSelecionada},
                        onSelectionChanged: (newSelection) {
                          setDialogState(() => metricaSelecionada = newSelection.first);
                        },
                      ),
                      const Divider(height: 24),
                      const Text('2. Distribuição', style: TextStyle(fontWeight: FontWeight.bold)),
                      RadioListTile<MetodoDistribuicaoCubagem>(
                        title: const Text('Qtd Fixa por Talhão'),
                        value: MetodoDistribuicaoCubagem.fixoPorTalhao,
                        groupValue: metodoDistribuicao,
                        onChanged: (v) => setDialogState(() => metodoDistribuicao = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<MetodoDistribuicaoCubagem>(
                        title: const Text('Proporcional à Área'),
                        value: MetodoDistribuicaoCubagem.proporcionalPorArea,
                        groupValue: metodoDistribuicao,
                        onChanged: (v) => setDialogState(() => metodoDistribuicao = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                      TextFormField(
                        controller: quantidadeController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: metodoDistribuicao == MetodoDistribuicaoCubagem.fixoPorTalhao ? 'Árvores por talhão' : 'Total para o estrato',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Campo obrigatório';
                          final parsed = int.tryParse(v);
                          if (parsed == null || parsed <= 0) return 'Digite um número válido maior que zero';
                          return null;
                        },
                      ),
                      const Divider(height: 24),
                      const Text('3. Método de Medição', style: TextStyle(fontWeight: FontWeight.bold)),
                      DropdownButtonFormField<String>(
                        value: metodoCubagem,
                        items: const [
                          DropdownMenuItem(value: 'Fixas', child: Text('Seções Fixas')),
                          DropdownMenuItem(value: 'Relativas', child: Text('Seções Relativas')),
                        ],
                        onChanged: (value) => setDialogState(() => metodoCubagem = value!),
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                      ),
                      const Divider(height: 24),
                      const Text('4. Intervalo das Classes', style: TextStyle(fontWeight: FontWeight.bold)),
                      RadioListTile<bool>(
                        title: const Text('Automático (Padrão)'),
                        subtitle: Text(metricaSelecionada == MetricaDistribuicao.dap ? 'Classes de 5 em 5 cm' : 'Classes de 15 em 15 cm'),
                        value: false,
                        groupValue: isIntervaloManual,
                        onChanged: (v) => setDialogState(() => isIntervaloManual = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<bool>(
                        title: const Text('Manual'),
                        value: true,
                        groupValue: isIntervaloManual,
                        onChanged: (v) => setDialogState(() => isIntervaloManual = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (isIntervaloManual)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: TextFormField(
                            controller: intervaloController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Largura da classe (cm)',
                              border: const OutlineInputBorder(),
                              hintText: metricaSelecionada == MetricaDistribuicao.dap ? 'Ex: 2.5' : 'Ex: 10',
                            ),
                            validator: (v) {
                              if (!isIntervaloManual) return null;
                              if (v == null || v.isEmpty) return 'Obrigatório';
                              return null;
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      // Valida novamente antes de parse (segurança extra)
                      final quantidadeParsed = int.tryParse(quantidadeController.text);
                      if (quantidadeParsed == null || quantidadeParsed <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('Quantidade inválida'),
                          backgroundColor: Colors.red,
                        ));
                        return;
                      }
                      
                      Navigator.of(ctx).pop(PlanoConfig(
                        metodoDistribuicao: metodoDistribuicao,
                        quantidade: quantidadeParsed,
                        metodoCubagem: metodoCubagem,
                        metricaDistribuicao: metricaSelecionada,
                        isIntervaloManual: isIntervaloManual,
                        intervaloManual: isIntervaloManual 
                            ? double.tryParse(intervaloController.text.replaceAll(',', '.')) 
                            : null,
                      ));
                    }
                  },
                  child: const Text('Gerar Planos'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- AÇÕES IA UNIFICADAS ---

  Future<void> _executarAuditoriaInteligente() async {
    if (_talhoesSelecionados.isEmpty) return;
    ProgressDialog.show(context, 'IA analisando o estrato...');

    final aiService = AiValidationService();
    List<Map<String, dynamic>> resumosParaIA = [];

    try {
      for (int id in _talhoesSelecionados) {
        final t = _talhoesDisponiveis.firstWhere((element) => element.id == id);
        final dados = await _analiseRepository.getDadosAgregadosDoTalhao(id);
        final analise = _analysisService.getTalhaoInsights(t, dados['parcelas'], dados['arvores']);
        
        resumosParaIA.add({
          "talhao": t.nome,
          "especie": t.especie,
          "idade": t.idadeAnos ?? 0.0, // Envia 0.0 em vez de texto se estiver nulo
          "vol_ha": analise.volumePorHectare.toStringAsFixed(1),
          "cap_medio": analise.mediaCap.toStringAsFixed(1),
          "arv_ha": analise.arvoresPorHectare
        });
      }

      final alertas = await aiService.validarEstrato(resumosParaIA);
      if (!mounted) return;
      ProgressDialog.hide(context);

      _mostrarResultadoIA(alertas);

    } catch (e) {
      if (mounted) {
        ProgressDialog.hide(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro na IA: $e")));
      }
    }
  }

  void _mostrarResultadoIA(List<String> alertas) {
    showModalBottomSheet(
      context: context,
      // 1. Permite que o modal cresça além do tamanho padrão e gerencie melhor o scroll
      isScrollControlled: true, 
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        // 2. Opcional: Faz o modal abrir em 60% da tela e poder ser arrastado até 90%
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Barra de arraste visual (opcional)
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 15),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text("🌲 Auditoria do Estrato", 
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Divider(),
              
              // 3. O segredo da rolagem: Usar Expanded + ListView ou SingleChildScrollView
              Expanded(
                child: ListView(
                  controller: scrollController, // Vincula o scroll do modal ao conteúdo
                  children: [
                    if (alertas.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: Text("✅ Nenhuma inconsistência biológica detectada.")),
                      )
                    else
                      ...alertas.map((a) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start, // Alinha ícone no topo do parágrafo
                          children: [
                            const Icon(Icons.info_outline, color: Colors.deepPurple, size: 20),
                            const SizedBox(width: 10),
                            Expanded(child: Text(a, style: const TextStyle(fontSize: 15, height: 1.4))),
                          ],
                        ),
                      )),
                    
                    const SizedBox(height: 20),
                    
                    ListTile(
                      tileColor: Colors.deepPurple.withOpacity(0.05),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      leading: const Icon(Icons.chat_bubble_outline, color: Colors.deepPurple),
                      title: const Text("Conversar com os dados deste estrato"),
                      onTap: () {
                        Navigator.pop(ctx);
                        _abrirChatUnificado();
                      },
                    ),
                    const SizedBox(height: 20), // Espaço extra no fim para não colar na borda
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _abrirChatUnificado() async {
    final dados = await _analiseRepository.getDadosAgregadosDoTalhao(_talhoesSelecionados.first);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => ChatIaDialog(parcela: dados['parcelas'].first, arvores: dados['arvores']),
    );
  }

  // --- CONSTRUÇÃO DA INTERFACE ---

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Analista de Estrato')),
      body: Column(
        children: [
          _buildFiltrosCard(isDark),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Selecione os Talhões', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('${_talhoesSelecionados.length} selecionados', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _talhoesDisponiveis.isEmpty
                    ? const Center(child: Text("Selecione os filtros acima", style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _talhoesDisponiveis.length,
                        itemBuilder: (ctx, i) {
                          final t = _talhoesDisponiveis[i];
                          return CheckboxListTile(
                            secondary: const Icon(Icons.park_outlined, color: Colors.green),
                            title: Text(t.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text("${t.areaHa?.toStringAsFixed(2) ?? '0'} ha • ${t.especie}"),
                            value: _talhoesSelecionados.contains(t.id),
                            onChanged: (val) => _toggleTalhao(t.id!, val),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomActionArea(),
    );
  }

  Widget _buildFiltrosCard(bool isDark) {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildDropdown("Projeto", _projetoSelecionado, _projetosDisponiveis, _onProjetoSelecionado),
            const SizedBox(height: 12),
            _buildDropdown("Atividade", _atividadeSelecionada, _atividadesDisponiveis, _onAtividadeSelecionada),
            const SizedBox(height: 12),
            _buildDropdown("Fazenda", _fazendaSelecionada, _fazendasDisponiveis, _onFazendaSelecionada),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, dynamic value, List<dynamic> items, void Function(dynamic) onChanged) {
    return DropdownButtonFormField<dynamic>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      items: items.map((i) {
        String texto = (i is Projeto) ? i.nome : (i is Atividade ? i.tipo : i.nome);
        return DropdownMenuItem(value: i, child: Text(texto, overflow: TextOverflow.ellipsis));
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildBottomActionArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _talhoesSelecionados.isEmpty ? null : _gerarAnaliseEstrato,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
              icon: const Icon(Icons.dashboard_customize_outlined),
              label: const Text("GERAR DASHBOARD"),
            ),
          ),
          const SizedBox(width: 12),
          PopupMenuButton<int>(
            icon: const Icon(Icons.more_vert, size: 30),
            onSelected: (val) {
              if (val == 1) _gerarRelatorioComparativo();
              if (val == 2) _navegarParaAnaliseVolumetrica();
              if (val == 3) _executarAuditoriaInteligente();
              if (val == 4) _gerarPlanosDeCubagemParaEstrato();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 1, child: Row(children: [Icon(Icons.table_chart), SizedBox(width: 8), Text("Tabela Comparativa")])),
              const PopupMenuItem(value: 2, child: Row(children: [Icon(Icons.calculate), SizedBox(width: 8), Text("Equação de Volume")])),
              const PopupMenuItem(value: 4, child: Row(children: [Icon(Icons.playlist_add_check_outlined, color: Colors.blue), SizedBox(width: 8), Text("Gerar Planos de Cubagem", style: TextStyle(color: Colors.blue))])),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 3, child: Row(children: [Icon(Icons.auto_awesome, color: Colors.deepPurple), SizedBox(width: 8), Text("Auditoria IA", style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold))])),
            ],
          ),
        ],
      ),
    );
  }
}
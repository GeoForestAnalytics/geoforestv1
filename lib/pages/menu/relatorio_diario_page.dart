// lib/pages/menu/relatorio_diario_page.dart (VERSÃO FINAL COM NAVEGAÇÃO COMPLETA)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Imports do projeto
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/providers/team_provider.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/data/repositories/fazenda_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/data/repositories/diario_de_campo_repository.dart';
// <<< PASSO 1: IMPORT DA NOVA TELA DE VISUALIZAÇÃO >>>
import 'visualizador_relatorio_page.dart';

/// Enum para controlar qual etapa do relatório está sendo exibida.
enum RelatorioStep {
  selecionarFiltros,
  consolidarEPreencher,
}

/// Página para geração de relatórios diários de atividades de campo.
class RelatorioDiarioPage extends StatefulWidget {
  const RelatorioDiarioPage({super.key});

  @override
  State<RelatorioDiarioPage> createState() => _RelatorioDiarioPageState();
}

class _RelatorioDiarioPageState extends State<RelatorioDiarioPage> {
  RelatorioStep _currentStep = RelatorioStep.selecionarFiltros;

  // Controladores do formulário do diário
  final _liderController = TextEditingController();
  final _ajudantesController = TextEditingController();
  final _kmInicialController = TextEditingController();
  final _kmFinalController = TextEditingController();
  final _destinoController = TextEditingController();
  final _pedagioController = TextEditingController();
  final _abastecimentoController = TextEditingController();
  final _marmitasController = TextEditingController();
  final _refeicaoValorController = TextEditingController();
  final _refeicaoDescricaoController = TextEditingController();
  final _placaController = TextEditingController();
  final _modeloController = TextEditingController();

  // Repositórios
  final _projetoRepo = ProjetoRepository();
  final _atividadeRepo = AtividadeRepository();
  final _fazendaRepo = FazendaRepository();
  final _talhaoRepo = TalhaoRepository();
  final _parcelaRepo = ParcelaRepository();
  final _cubagemRepo = CubagemRepository();
  final _diarioRepo = DiarioDeCampoRepository();

  // Estado dos filtros
  DateTime _dataSelecionada = DateTime.now();
  List<Talhao> _locaisTrabalhados = [];

  // Estado dos resultados consolidados
  DiarioDeCampo? _diarioAtual;
  List<Parcela> _parcelasDoRelatorio = [];
  List<CubagemArvore> _cubagensDoRelatorio = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preencherNomesEquipe();
    });
  }

  @override
  void dispose() {
    _liderController.dispose();
    _ajudantesController.dispose();
    _kmInicialController.dispose();
    _kmFinalController.dispose();
    _destinoController.dispose();
    _pedagioController.dispose();
    _abastecimentoController.dispose();
    _marmitasController.dispose();
    _refeicaoValorController.dispose();
    _refeicaoDescricaoController.dispose();
    _placaController.dispose();
    _modeloController.dispose();
    super.dispose();
  }

  /// Preenche os nomes da equipe, tratando o caso do gerente.
  void _preencherNomesEquipe() {
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);
    _liderController.text = teamProvider.lider ?? '';
    _ajudantesController.text = teamProvider.ajudantes ?? '';

    if (_liderController.text.trim().isEmpty) {
      final licenseProvider = Provider.of<LicenseProvider>(context, listen: false);
      if (licenseProvider.licenseData?.cargo == 'gerente') {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          _liderController.text = currentUser.displayName ?? '';
        }
      }
    }
  }

  /// Exibe o seletor de data.
  Future<void> _selecionarData(BuildContext context) async {
    final DateTime? dataEscolhida = await showDatePicker(
      context: context,
      initialDate: _dataSelecionada,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (dataEscolhida != null) setState(() => _dataSelecionada = dataEscolhida);
  }

  /// Abre o diálogo para o usuário selecionar um local de trabalho.
  Future<void> _adicionarLocalTrabalho() async {
    final Talhao? talhaoSelecionado = await showDialog<Talhao>(
      context: context,
      builder: (_) => _SelecaoLocalTrabalhoDialog(
        projetoRepo: _projetoRepo,
        atividadeRepo: _atividadeRepo,
        fazendaRepo: _fazendaRepo,
        talhaoRepo: _talhaoRepo,
      ),
    );

    if (talhaoSelecionado != null) {
      setState(() {
        if (!_locaisTrabalhados.any((t) => t.id == talhaoSelecionado.id)) {
          _locaisTrabalhados.add(talhaoSelecionado);
        }
      });
    }
  }
  
  /// Busca todas as coletas (parcelas e cubagens) dos locais selecionados na data escolhida.
  Future<void> _gerarRelatorioConsolidado() async {
    if (_locaisTrabalhados.isEmpty || _liderController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Adicione pelo menos um local de trabalho e informe o líder.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    setState(() => _isLoading = true);

    final lider = _liderController.text.trim();
    final List<Parcela> parcelasEncontradas = [];
    final List<CubagemArvore> cubagensEncontradas = [];

    for (final talhao in _locaisTrabalhados) {
      final parcelas = await _parcelaRepo.getParcelasDoDiaPorEquipeEFiltros(
        nomeLider: lider,
        dataSelecionada: _dataSelecionada,
        talhaoId: talhao.id!,
      );
      parcelasEncontradas.addAll(parcelas);

      final cubagens = await _cubagemRepo.getCubagensDoDiaPorEquipe(
        nomeLider: lider,
        dataSelecionada: _dataSelecionada,
        talhaoId: talhao.id!,
      );
      cubagensEncontradas.addAll(cubagens);
    }
    
    final dataFormatada = DateFormat('yyyy-MM-dd').format(_dataSelecionada);
    final diarioEncontrado = await _diarioRepo.getDiario(dataFormatada, lider);

    _diarioAtual = diarioEncontrado;
    _parcelasDoRelatorio = parcelasEncontradas;
    _cubagensDoRelatorio = cubagensEncontradas;

    _preencherControladoresDiario();

    setState(() {
      _isLoading = false;
      _currentStep = RelatorioStep.consolidarEPreencher;
    });
  }
  
  /// Preenche o formulário do diário com dados existentes.
  void _preencherControladoresDiario() {
    _kmInicialController.text = _diarioAtual?.kmInicial?.toString().replaceAll('.', ',') ?? '';
    _kmFinalController.text = _diarioAtual?.kmFinal?.toString().replaceAll('.', ',') ?? '';
    _destinoController.text = _diarioAtual?.localizacaoDestino ?? '';
    _pedagioController.text = _diarioAtual?.pedagioValor?.toString().replaceAll('.', ',') ?? '';
    _abastecimentoController.text = _diarioAtual?.abastecimentoValor?.toString().replaceAll('.', ',') ?? '';
    _marmitasController.text = _diarioAtual?.alimentacaoMarmitasQtd?.toString() ?? '';
    _refeicaoValorController.text = _diarioAtual?.alimentacaoRefeicaoValor?.toString().replaceAll('.', ',') ?? '';
    _refeicaoDescricaoController.text = _diarioAtual?.alimentacaoDescricao ?? '';
    _placaController.text = _diarioAtual?.veiculoPlaca ?? '';
    _modeloController.text = _diarioAtual?.veiculoModelo ?? '';
  }
  
  // <<< PASSO 2: AJUSTE FINAL NA NAVEGAÇÃO >>>
  /// Salva o diário e navega para a tela de visualização e ações finais.
  Future<void> _navegarParaVisualizacao() async {
    if (mounted) setState(() => _isLoading = true);

    final diarioParaSalvar = DiarioDeCampo(
      id: _diarioAtual?.id,
      dataRelatorio: DateFormat('yyyy-MM-dd').format(_dataSelecionada),
      nomeLider: _liderController.text.trim(),
      projetoId: _locaisTrabalhados.first.projetoId!, 
      kmInicial: double.tryParse(_kmInicialController.text.replaceAll(',', '.')),
      kmFinal: double.tryParse(_kmFinalController.text.replaceAll(',', '.')),
      localizacaoDestino: _destinoController.text.trim(),
      pedagioValor: double.tryParse(_pedagioController.text.replaceAll(',', '.')),
      abastecimentoValor: double.tryParse(_abastecimentoController.text.replaceAll(',', '.')),
      alimentacaoMarmitasQtd: int.tryParse(_marmitasController.text),
      alimentacaoRefeicaoValor: double.tryParse(_refeicaoValorController.text.replaceAll(',', '.')),
      alimentacaoDescricao: _refeicaoDescricaoController.text.trim(),
      veiculoPlaca: _placaController.text.trim().toUpperCase(),
      veiculoModelo: _modeloController.text.trim(),
      equipeNoCarro: '${_liderController.text.trim()}, ${_ajudantesController.text.trim()}',
      lastModified: DateTime.now().toIso8601String(),
    );
    
    await _diarioRepo.insertOrUpdateDiario(diarioParaSalvar);
    
    if (mounted) setState(() => _isLoading = false);
    
    if (mounted) {
      // Navega para a nova tela, passando todos os dados consolidados.
      final bool? precisaEditar = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (context) => VisualizadorRelatorioPage(
          diario: diarioParaSalvar,
          parcelas: _parcelasDoRelatorio,
          cubagens: _cubagensDoRelatorio,
        ),
      ));

      // Se o usuário NÃO clicou em "Editar" (retorno foi nulo ou false),
      // significa que o fluxo terminou, então voltamos para a tela de filtros.
      if (precisaEditar != true) {
        setState(() {
          _currentStep = RelatorioStep.selecionarFiltros;
          _locaisTrabalhados.clear();
          _parcelasDoRelatorio.clear();
          _cubagensDoRelatorio.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ... (O resto do build permanece o mesmo, pois já está refatorado)
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatório Diário Consolidado'),
        leading: _currentStep != RelatorioStep.selecionarFiltros
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _currentStep = RelatorioStep.selecionarFiltros;
                  // Limpa os resultados ao voltar para os filtros
                   _locaisTrabalhados.clear();
                  _parcelasDoRelatorio.clear();
                  _cubagensDoRelatorio.clear();
                }),
              )
            : null,
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _currentStep.index,
              children: [
                _buildFiltros(),
                _buildConsolidacaoEFormulario(),
              ],
      ),
    );
  }

  /// Constrói a UI da primeira etapa (filtros).
  Widget _buildFiltros() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text("1. Informações Gerais", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Data do Relatório"),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(_dataSelecionada), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () => _selecionarData(context),
                ),
                const SizedBox(height: 16),
                TextFormField(controller: _liderController, decoration: const InputDecoration(labelText: 'Líder da Equipe *', border: OutlineInputBorder())),
                const SizedBox(height: 16),
                TextFormField(controller: _ajudantesController, decoration: const InputDecoration(labelText: 'Ajudantes', border: OutlineInputBorder())),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text("2. Locais Trabalhados", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (_locaisTrabalhados.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Text("Nenhum local adicionado.", style: TextStyle(color: Colors.grey)),
                  )
                else
                  ..._locaisTrabalhados.map((talhao) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: const Icon(Icons.park_outlined),
                      title: Text(talhao.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("${talhao.fazendaNome ?? 'N/A'}"),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () => setState(() => _locaisTrabalhados.remove(talhao)),
                      ),
                    ),
                  )),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Adicionar Local de Trabalho'),
                  onPressed: _adicionarLocalTrabalho,
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                )
              ],
            ),
          )
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          icon: const Icon(Icons.receipt_long),
          onPressed: _gerarRelatorioConsolidado,
          label: const Text('Gerar Relatório Consolidado'),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        )
      ],
    );
  }

  /// Constrói a UI da segunda etapa (visualização e preenchimento).
  Widget _buildConsolidacaoEFormulario() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 90.0),
      children: [
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Resumo das Coletas do Dia", style: Theme.of(context).textTheme.titleLarge),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.list_alt, color: Colors.blue),
                  title: const Text("Parcelas de Inventário"),
                  trailing: Text(_parcelasDoRelatorio.length.toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  leading: const Icon(Icons.architecture, color: Colors.green),
                  title: const Text("Árvores de Cubagem"),
                  trailing: Text(_cubagensDoRelatorio.length.toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Diário de Campo", style: Theme.of(context).textTheme.titleLarge),
                  const Divider(),
                  Text("Veículo", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextFormField(controller: _placaController, decoration: const InputDecoration(labelText: 'Placa', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextFormField(controller: _modeloController, decoration: const InputDecoration(labelText: 'Modelo', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextFormField(controller: _kmInicialController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'KM Inicial', border: OutlineInputBorder()))),
                    const SizedBox(width: 12),
                    Expanded(child: TextFormField(controller: _kmFinalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'KM Final', border: OutlineInputBorder()))),
                  ]),
                  const SizedBox(height: 12),
                  TextFormField(controller: _destinoController, decoration: const InputDecoration(labelText: 'Localização/Destino', border: OutlineInputBorder())),
                  const Divider(height: 24),
                  Text("Despesas", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextFormField(controller: _pedagioController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pedágio (R\$)', border: OutlineInputBorder()))),
                    const SizedBox(width: 12),
                    Expanded(child: TextFormField(controller: _abastecimentoController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Abastecimento (R\$)', border: OutlineInputBorder()))),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextFormField(controller: _marmitasController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qtd. Marmitas', border: OutlineInputBorder()))),
                    const SizedBox(width: 12),
                    Expanded(child: TextFormField(controller: _refeicaoValorController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Outras Refeições (R\$)', border: OutlineInputBorder()))),
                  ]),
                  const SizedBox(height: 12),
                  TextFormField(controller: _refeicaoDescricaoController, decoration: const InputDecoration(labelText: 'Descrição da Alimentação', border: OutlineInputBorder())),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          icon: const Icon(Icons.arrow_forward),
          onPressed: _navegarParaVisualizacao,
          label: const Text('Visualizar Relatório e Finalizar'),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        )
      ],
    );
  }
}

/// Um widget de diálogo para selecionar a hierarquia: Projeto -> Atividade -> Fazenda -> Talhão.
class _SelecaoLocalTrabalhoDialog extends StatefulWidget {
  final ProjetoRepository projetoRepo;
  final AtividadeRepository atividadeRepo;
  final FazendaRepository fazendaRepo;
  final TalhaoRepository talhaoRepo;

  const _SelecaoLocalTrabalhoDialog({
    required this.projetoRepo,
    required this.atividadeRepo,
    required this.fazendaRepo,
    required this.talhaoRepo,
  });

  @override
  State<_SelecaoLocalTrabalhoDialog> createState() => __SelecaoLocalTrabalhoDialogState();
}

class __SelecaoLocalTrabalhoDialogState extends State<_SelecaoLocalTrabalhoDialog> {
  // Listas para popular os dropdowns
  List<Projeto> _projetosDisponiveis = [];
  Projeto? _projetoSelecionado;
  List<Atividade> _atividadesDisponiveis = [];
  Atividade? _atividadeSelecionada;
  List<Fazenda> _fazendasDisponiveis = [];
  Fazenda? _fazendaSelecionada;
  List<Talhao> _talhoesDisponiveis = [];
  Talhao? _talhaoSelecionado;

  @override
  void initState() {
    super.initState();
    _carregarProjetos();
  }

  Future<void> _carregarProjetos() async {
    _projetosDisponiveis = await widget.projetoRepo.getTodosOsProjetosParaGerente();
    if (mounted) setState(() {});
  }
  
  Future<void> _onProjetoSelecionado(Projeto? projeto) async {
    setState(() {
      _projetoSelecionado = projeto;
      _atividadeSelecionada = null; _atividadesDisponiveis = [];
      _fazendaSelecionada = null; _fazendasDisponiveis = [];
      _talhaoSelecionado = null; _talhoesDisponiveis = [];
    });
    if (projeto != null) {
      _atividadesDisponiveis = await widget.atividadeRepo.getAtividadesDoProjeto(projeto.id!);
      if (mounted) setState(() {});
    }
  }

  Future<void> _onAtividadeSelecionada(Atividade? atividade) async {
    setState(() {
      _atividadeSelecionada = atividade;
      _fazendaSelecionada = null; _fazendasDisponiveis = [];
      _talhaoSelecionado = null; _talhoesDisponiveis = [];
    });
    if (atividade != null) {
      _fazendasDisponiveis = await widget.fazendaRepo.getFazendasDaAtividade(atividade.id!);
      if (mounted) setState(() {});
    }
  }

  Future<void> _onFazendaSelecionada(Fazenda? fazenda) async {
    setState(() {
      _fazendaSelecionada = fazenda;
      _talhaoSelecionado = null; _talhoesDisponiveis = [];
    });
    if (fazenda != null) {
      _talhoesDisponiveis = await widget.talhaoRepo.getTalhoesDaFazenda(fazenda.id, fazenda.atividadeId);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adicionar Local de Trabalho'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<Projeto>(
              value: _projetoSelecionado,
              hint: const Text('Selecione o Projeto'),
              items: _projetosDisponiveis.map((p) => DropdownMenuItem(value: p, child: Text(p.nome))).toList(),
              onChanged: _onProjetoSelecionado,
              isExpanded: true,
            ),
            const SizedBox(height: 16),
            if (_projetoSelecionado != null)
              DropdownButtonFormField<Atividade>(
                value: _atividadeSelecionada,
                hint: const Text('Selecione a Atividade'),
                items: _atividadesDisponiveis.map((a) => DropdownMenuItem(value: a, child: Text(a.tipo))).toList(),
                onChanged: _onAtividadeSelecionada,
                isExpanded: true,
              ),
            const SizedBox(height: 16),
            if (_atividadeSelecionada != null)
              DropdownButtonFormField<Fazenda>(
                value: _fazendaSelecionada,
                hint: const Text('Selecione a Fazenda'),
                items: _fazendasDisponiveis.map((f) => DropdownMenuItem(value: f, child: Text(f.nome))).toList(),
                onChanged: _onFazendaSelecionada,
                isExpanded: true,
              ),
            const SizedBox(height: 16),
            if (_fazendaSelecionada != null)
              DropdownButtonFormField<Talhao>(
                value: _talhaoSelecionado,
                hint: const Text('Selecione o Talhão'),
                items: _talhoesDisponiveis.map((t) => DropdownMenuItem(value: t, child: Text(t.nome))).toList(),
                onChanged: (t) => setState(() => _talhaoSelecionado = t),
                isExpanded: true,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _talhaoSelecionado != null ? () => Navigator.of(context).pop(_talhaoSelecionado) : null,
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}
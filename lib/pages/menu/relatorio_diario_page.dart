import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/pilha_madeira_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/silvi_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/providers/team_provider.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/data/repositories/fazenda_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/data/repositories/pilha_repository.dart';
import 'package:geoforestv1/data/repositories/silvi_repository.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/data/repositories/diario_de_campo_repository.dart';

enum RelatorioStep {
  selecionarFiltros,
  consolidarEPreencher,
}

class RelatorioDiarioPage extends StatefulWidget {
  const RelatorioDiarioPage({super.key});

  @override
  State<RelatorioDiarioPage> createState() => _RelatorioDiarioPageState();
}

class _RelatorioDiarioPageState extends State<RelatorioDiarioPage> {
  RelatorioStep _currentStep = RelatorioStep.selecionarFiltros;

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
  final _outrasDespesasValorController = TextEditingController();
  final _outrasDespesasDescricaoController = TextEditingController();
  final _placaController = TextEditingController();
  final _modeloController = TextEditingController();

  final _projetoRepo = ProjetoRepository();
  final _atividadeRepo = AtividadeRepository();
  final _fazendaRepo = FazendaRepository();
  final _talhaoRepo = TalhaoRepository();
  final _parcelaRepo = ParcelaRepository();
  final _cubagemRepo = CubagemRepository();
  final _pilhaRepo = PilhaRepository();
  final _silviRepo = SilviRepository();
  final _diarioRepo = DiarioDeCampoRepository();

  DateTime _dataSelecionada = DateTime.now();
  List<Talhao> _locaisTrabalhados = [];

  DiarioDeCampo? _diarioAtual;
  List<Parcela> _parcelasDoRelatorio = [];
  List<CubagemArvore> _cubagensDoRelatorio = [];
  List<PilhaMadeira> _pilhasDoRelatorio = [];
  List<OperacaoSilvi> _silvisDoRelatorio = [];
  List<String> _sugestoesLider = [];
  bool _buscaRealizada = false;
  bool _isLoading = false;

  // Auto-busca
  bool _buscandoLocais = false;
  Timer? _debounce;
  bool _isGerente = false;

  double get _volumeTotalM3 => _pilhasDoRelatorio.fold(0.0, (s, p) => s + (p.volumeBruto ?? 0));
  double get _areaTotalHa => _silvisDoRelatorio.fold(0.0, (s, o) => s + (o.areaAplicadaHa ?? 0));

  String get _modulo {
    final lp = Provider.of<LicenseProvider>(context, listen: false);
    return lp.licenseData?.modulo ?? 'inventario';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inicializar();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
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
    _outrasDespesasValorController.dispose();
    _outrasDespesasDescricaoController.dispose();
    _placaController.dispose();
    _modeloController.dispose();
    super.dispose();
  }

  void _inicializar() {
    final licenseProvider = Provider.of<LicenseProvider>(context, listen: false);
    _isGerente = licenseProvider.licenseData?.cargo == 'gerente';

    final teamProvider = Provider.of<TeamProvider>(context, listen: false);
    _liderController.text = teamProvider.lider ?? '';
    _ajudantesController.text = teamProvider.ajudantes ?? '';

    if (_liderController.text.trim().isEmpty && _isGerente) {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        _liderController.text = currentUser.displayName ?? '';
      }
    }

    // Gerente pode alterar o nome para buscar por outro coletor
    if (_isGerente) {
      _liderController.addListener(_onLiderChanged);
    }

    _buscarLocaisAutomaticamente();
  }

  void _onLiderChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (_liderController.text.trim().isNotEmpty) {
        _buscarLocaisAutomaticamente();
      }
    });
  }

  Future<void> _buscarLocaisAutomaticamente() async {
    final lider = _liderController.text.trim();
    if (lider.isEmpty) return;

    setState(() {
      _buscandoLocais = true;
      _locaisTrabalhados.clear();
    });

    try {
      final results = await Future.wait([
        _parcelaRepo.getTalhaoIdsNaData(lider, _dataSelecionada),
        _cubagemRepo.getTalhaoIdsNaData(lider, _dataSelecionada),
        _pilhaRepo.getTalhaoIdsNaData(lider, _dataSelecionada),
        _silviRepo.getTalhaoIdsNaData(lider, _dataSelecionada),
      ]);

      final ids = <int>{};
      for (final list in results) {
        ids.addAll(list);
      }

      if (ids.isNotEmpty) {
        final talhoes = await _talhaoRepo.getTalhoesPorIds(ids.toList());
        if (mounted) {
          setState(() => _locaisTrabalhados = talhoes);
        }
      }
    } finally {
      if (mounted) setState(() => _buscandoLocais = false);
    }
  }

  Future<void> _selecionarData(BuildContext context) async {
    final DateTime? dataEscolhida = await showDatePicker(
      context: context,
      initialDate: _dataSelecionada,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (dataEscolhida != null) {
      setState(() => _dataSelecionada = dataEscolhida);
      _buscarLocaisAutomaticamente();
    }
  }

  Future<void> _adicionarLocalTrabalho() async {
    final List<Talhao>? talhoesSelecionados = await showDialog<List<Talhao>>(
      context: context,
      builder: (_) => _SelecaoLocalTrabalhoDialog(
        projetoRepo: _projetoRepo,
        atividadeRepo: _atividadeRepo,
        fazendaRepo: _fazendaRepo,
        talhaoRepo: _talhaoRepo,
      ),
    );

    if (talhoesSelecionados != null && talhoesSelecionados.isNotEmpty) {
      setState(() {
        for (final talhao in talhoesSelecionados) {
          if (!_locaisTrabalhados.any((t) => t.id == talhao.id)) {
            _locaisTrabalhados.add(talhao);
          }
        }
      });
    }
  }

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
    final modulo = _modulo;
    final List<Parcela> parcelasEncontradas = [];
    final List<CubagemArvore> cubagensEncontradas = [];
    final List<PilhaMadeira> pilhasEncontradas = [];
    final List<OperacaoSilvi> silvisEncontrados = [];

    for (final talhao in _locaisTrabalhados) {
      if (modulo == 'inventario' || modulo == 'todos') {
        parcelasEncontradas.addAll(await _parcelaRepo.getParcelasDoDiaPorEquipeEFiltros(
          nomeLider: lider, dataSelecionada: _dataSelecionada, talhaoId: talhao.id!,
        ));
        cubagensEncontradas.addAll(await _cubagemRepo.getCubagensDoDiaPorEquipe(
          nomeLider: lider, dataSelecionada: _dataSelecionada, talhaoId: talhao.id!,
        ));
      }
      if (modulo == 'colheita' || modulo == 'todos') {
        pilhasEncontradas.addAll(await _pilhaRepo.getPilhasDoDiaPorTalhao(
          nomeLider: lider, dataSelecionada: _dataSelecionada, talhaoId: talhao.id!,
        ));
      }
      if (modulo == 'silvicultura' || modulo == 'todos') {
        silvisEncontrados.addAll(await _silviRepo.getOperacoesDoDiaPorTalhao(
          nomeLider: lider, dataSelecionada: _dataSelecionada, talhaoId: talhao.id!,
        ));
      }
    }

    final dataFormatada = DateFormat('yyyy-MM-dd').format(_dataSelecionada);
    final diarioEncontrado = await _diarioRepo.getDiario(dataFormatada, lider);

    final Set<String> sugestoes = {};
    for (final talhao in _locaisTrabalhados) {
      if ((modulo == 'inventario' || modulo == 'todos') && parcelasEncontradas.isEmpty) {
        sugestoes.addAll(await _parcelaRepo.getLideresNoDia(data: _dataSelecionada, talhaoId: talhao.id!));
      }
      if ((modulo == 'inventario' || modulo == 'todos') && cubagensEncontradas.isEmpty) {
        sugestoes.addAll(await _cubagemRepo.getLideresNoDia(data: _dataSelecionada, talhaoId: talhao.id!));
      }
      if ((modulo == 'silvicultura' || modulo == 'todos') && silvisEncontrados.isEmpty) {
        sugestoes.addAll(await _silviRepo.getLideresNoDia(data: _dataSelecionada, talhaoId: talhao.id!));
      }
      if ((modulo == 'colheita' || modulo == 'todos') && pilhasEncontradas.isEmpty) {
        sugestoes.addAll(await _pilhaRepo.getLideresNoDia(data: _dataSelecionada, talhaoId: talhao.id!));
      }
    }
    sugestoes.removeWhere((n) => n.toLowerCase() == lider.toLowerCase());

    _diarioAtual = diarioEncontrado;
    _parcelasDoRelatorio = parcelasEncontradas;
    _cubagensDoRelatorio = cubagensEncontradas;
    _pilhasDoRelatorio = pilhasEncontradas;
    _silvisDoRelatorio = silvisEncontrados;
    _sugestoesLider = sugestoes.toList()..sort();
    _buscaRealizada = true;

    _preencherControladoresDiario();

    setState(() {
      _isLoading = false;
      _currentStep = RelatorioStep.consolidarEPreencher;
    });
  }

  void _preencherControladoresDiario() {
    _kmInicialController.text = _diarioAtual?.kmInicial?.toString().replaceAll('.', ',') ?? '';
    _kmFinalController.text = _diarioAtual?.kmFinal?.toString().replaceAll('.', ',') ?? '';
    _destinoController.text = _diarioAtual?.localizacaoDestino ?? '';
    _pedagioController.text = _diarioAtual?.pedagioValor?.toString().replaceAll('.', ',') ?? '';
    _abastecimentoController.text = _diarioAtual?.abastecimentoValor?.toString().replaceAll('.', ',') ?? '';
    _marmitasController.text = _diarioAtual?.alimentacaoMarmitasQtd?.toString() ?? '';
    _refeicaoValorController.text = _diarioAtual?.alimentacaoRefeicaoValor?.toString().replaceAll('.', ',') ?? '';
    _refeicaoDescricaoController.text = _diarioAtual?.alimentacaoDescricao ?? '';
    _outrasDespesasValorController.text = _diarioAtual?.outrasDespesasValor?.toString().replaceAll('.', ',') ?? '';
    _outrasDespesasDescricaoController.text = _diarioAtual?.outrasDespesasDescricao ?? '';
    _placaController.text = _diarioAtual?.veiculoPlaca ?? '';
    _modeloController.text = _diarioAtual?.veiculoModelo ?? '';
  }

  Future<void> _navegarParaVisualizacao() async {
    if (mounted) setState(() => _isLoading = true);

    final modulo = _modulo;

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
      outrasDespesasValor: double.tryParse(_outrasDespesasValorController.text.replaceAll(',', '.')),
      outrasDespesasDescricao: _outrasDespesasDescricaoController.text.trim(),
      veiculoPlaca: _placaController.text.trim().toUpperCase(),
      veiculoModelo: _modeloController.text.trim(),
      equipeNoCarro: '${_liderController.text.trim()}, ${_ajudantesController.text.trim()}',
      lastModified: DateTime.now().toIso8601String(),
      modulo: modulo,
    );

    await _diarioRepo.insertOrUpdateDiario(diarioParaSalvar);

    if (mounted) setState(() => _isLoading = false);

    if (mounted) {
      final bool? precisaEditar = await context.push<bool>(
        '/visualizar-relatorio',
        extra: {
          'diario': diarioParaSalvar,
          'parcelas': _parcelasDoRelatorio,
          'cubagens': _cubagensDoRelatorio,
          'pilhas': _pilhasDoRelatorio,
          'silvis': _silvisDoRelatorio,
        },
      );

      if (precisaEditar != true) {
        setState(() {
          _currentStep = RelatorioStep.selecionarFiltros;
          _locaisTrabalhados.clear();
          _parcelasDoRelatorio.clear();
          _cubagensDoRelatorio.clear();
          _pilhasDoRelatorio.clear();
          _silvisDoRelatorio.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatório Diário'),
        leading: _currentStep != RelatorioStep.selecionarFiltros
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _currentStep = RelatorioStep.selecionarFiltros;
                  _parcelasDoRelatorio.clear();
                  _cubagensDoRelatorio.clear();
                  _pilhasDoRelatorio.clear();
                  _silvisDoRelatorio.clear();
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

  Widget _buildFiltros() {
    final temLocais = _locaisTrabalhados.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // ── Card 1: Data + Líder ─────────────────────────────────────────────
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Informações Gerais", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Data do Relatório"),
                  subtitle: Text(
                    DateFormat('dd/MM/yyyy').format(_dataSelecionada),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () => _selecionarData(context),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _liderController,
                  readOnly: !_isGerente,
                  decoration: InputDecoration(
                    labelText: 'Líder da Equipe',
                    border: const OutlineInputBorder(),
                    suffixIcon: _isGerente
                        ? const Icon(Icons.edit_outlined, size: 18)
                        : const Icon(Icons.lock_outline, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ajudantesController,
                  decoration: const InputDecoration(labelText: 'Ajudantes', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── Card 2: Locais encontrados ───────────────────────────────────────
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text("Locais Trabalhados", style: Theme.of(context).textTheme.titleLarge),
                    ),
                    if (_buscandoLocais)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (!_buscandoLocais)
                  Text(
                    temLocais
                        ? '${_locaisTrabalhados.length} local(is) encontrado(s) automaticamente'
                        : 'Nenhum registro local encontrado para esta data.',
                    style: TextStyle(
                      fontSize: 12,
                      color: temLocais
                          ? Colors.green.shade700
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                const SizedBox(height: 12),
                if (temLocais) ...[
                  ..._locaisTrabalhados.map((talhao) => Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        child: ListTile(
                          leading: Icon(Icons.park_outlined,
                              color: Theme.of(context).colorScheme.primary),
                          title: Text(talhao.nome,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(talhao.fazendaNome ?? ''),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            color: Colors.red.shade400,
                            onPressed: () =>
                                setState(() => _locaisTrabalhados.remove(talhao)),
                          ),
                        ),
                      )),
                  const SizedBox(height: 8),
                ],
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                  label: const Text('Adicionar talhão manualmente'),
                  onPressed: _adicionarLocalTrabalho,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    foregroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        ElevatedButton.icon(
          icon: const Icon(Icons.receipt_long),
          onPressed: _gerarRelatorioConsolidado,
          label: const Text('Gerar Relatório Consolidado'),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
      ],
    );
  }

  Widget _buildConsolidacaoEFormulario() {
    final modulo = _modulo;
    final temResultado = _parcelasDoRelatorio.isNotEmpty ||
        _cubagensDoRelatorio.isNotEmpty ||
        _pilhasDoRelatorio.isNotEmpty ||
        _silvisDoRelatorio.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 90.0),
      children: [
        // ── Sugestões de líder ───────────────────────────────────────────────
        if (_buscaRealizada && !temResultado && _sugestoesLider.isNotEmpty)
          Card(
            color: Colors.orange.shade50,
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.person_search, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text('Verifique o nome do líder',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Buscamos por "${_liderController.text.trim()}" mas não encontramos nada.\n'
                    'Estes nomes têm registros neste talhão/data:',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _sugestoesLider
                        .map((nome) => ActionChip(
                              avatar: const Icon(Icons.person, size: 16),
                              label: Text(nome),
                              backgroundColor: Colors.white,
                              onPressed: () async {
                                setState(() => _liderController.text = nome);
                                await _gerarRelatorioConsolidado();
                              },
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),

        if (_buscaRealizada && !temResultado && _sugestoesLider.isEmpty)
          Card(
            color: Colors.grey.shade50,
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(Icons.inbox_outlined, color: Colors.grey.shade500),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Nenhuma atividade registrada neste talhão para '
                    '${DateFormat("dd/MM/yyyy").format(_dataSelecionada)}.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              ]),
            ),
          ),

        // ── Resumo de produção ───────────────────────────────────────────────
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Resumo da Produção do Dia", style: Theme.of(context).textTheme.titleLarge),
                const Divider(),
                if (modulo == 'inventario' || modulo == 'todos') ...[
                  ListTile(
                    leading: const Icon(Icons.list_alt, color: Colors.blue),
                    title: const Text("Parcelas de Inventário"),
                    trailing: Text(_parcelasDoRelatorio.length.toString(),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.architecture, color: Colors.green),
                    title: const Text("Árvores de Cubagem"),
                    trailing: Text(_cubagensDoRelatorio.length.toString(),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
                if (modulo == 'colheita' || modulo == 'todos') ...[
                  ListTile(
                    leading: const Icon(Icons.layers_outlined, color: Colors.orange),
                    title: const Text("Pilhas Medidas"),
                    trailing: Text(_pilhasDoRelatorio.length.toString(),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.waves_outlined, color: Colors.blue),
                    title: const Text("Volume Total"),
                    trailing: Text("${_volumeTotalM3.toStringAsFixed(2)} m³",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
                if (modulo == 'silvicultura' || modulo == 'todos') ...[
                  ListTile(
                    leading: const Icon(Icons.eco_outlined, color: Colors.green),
                    title: const Text("Operações Silvi."),
                    trailing: Text(_silvisDoRelatorio.length.toString(),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.map_outlined, color: Colors.teal),
                    title: const Text("Área Aplicada"),
                    trailing: Text("${_areaTotalHa.toStringAsFixed(2)} ha",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── Formulário diário ────────────────────────────────────────────────
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
                  TextFormField(
                      controller: _placaController,
                      decoration: const InputDecoration(labelText: 'Placa', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _modeloController,
                      decoration: const InputDecoration(labelText: 'Modelo', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: TextFormField(
                            controller: _kmInicialController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'KM Inicial', border: OutlineInputBorder()))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextFormField(
                            controller: _kmFinalController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'KM Final', border: OutlineInputBorder()))),
                  ]),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _destinoController,
                      decoration: const InputDecoration(
                          labelText: 'Localização/Destino', border: OutlineInputBorder())),
                  const Divider(height: 24),
                  Text("Despesas", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: TextFormField(
                            controller: _pedagioController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Pedágio (R\$)', border: OutlineInputBorder()))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextFormField(
                            controller: _abastecimentoController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Abastecimento (R\$)', border: OutlineInputBorder()))),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: TextFormField(
                            controller: _marmitasController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Qtd. Marmitas', border: OutlineInputBorder()))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextFormField(
                            controller: _refeicaoValorController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Outras Refeições (R\$)', border: OutlineInputBorder()))),
                  ]),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _refeicaoDescricaoController,
                      decoration: const InputDecoration(
                          labelText: 'Descrição da Alimentação', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _outrasDespesasValorController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Outros Gastos (R\$)', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _outrasDespesasDescricaoController,
                      decoration: const InputDecoration(
                          labelText: 'Descrição dos Outros Gastos', border: OutlineInputBorder())),
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
        ),
      ],
    );
  }
}

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
  List<Projeto> _projetosDisponiveis = [];
  Projeto? _projetoSelecionado;
  List<Atividade> _atividadesDisponiveis = [];
  Atividade? _atividadeSelecionada;
  List<Fazenda> _fazendasDisponiveis = [];
  Fazenda? _fazendaSelecionada;
  List<Talhao> _talhoesDisponiveis = [];
  final Set<int> _talhoesSelecionados = {};
  bool _isLoadingTalhoes = false;

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
      _talhoesSelecionados.clear(); _talhoesDisponiveis = [];
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
      _talhoesSelecionados.clear(); _talhoesDisponiveis = [];
    });
    if (atividade != null) {
      _fazendasDisponiveis = await widget.fazendaRepo.getFazendasDaAtividade(atividade.id!);
      if (mounted) setState(() {});
    }
  }

  Future<void> _onFazendaSelecionada(Fazenda? fazenda) async {
    setState(() {
      _fazendaSelecionada = fazenda;
      _talhoesSelecionados.clear();
      _talhoesDisponiveis = [];
      _isLoadingTalhoes = fazenda != null;
    });
    if (fazenda != null) {
      _talhoesDisponiveis =
          await widget.talhaoRepo.getTalhoesDaFazenda(fazenda.id, fazenda.atividadeId);
    }
    if (mounted) setState(() { _isLoadingTalhoes = false; });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adicionar Local Manualmente'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<Projeto>(
                value: _projetoSelecionado,
                hint: const Text('Selecione o Projeto'),
                items: _projetosDisponiveis
                    .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(p.nome, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: _onProjetoSelecionado,
                isExpanded: true,
              ),
              const SizedBox(height: 16),
              if (_projetoSelecionado != null)
                DropdownButtonFormField<Atividade>(
                  value: _atividadeSelecionada,
                  hint: const Text('Selecione a Atividade'),
                  items: _atividadesDisponiveis
                      .map((a) => DropdownMenuItem(
                          value: a,
                          child: Text(
                              a.descricao.isNotEmpty ? a.descricao : a.tipo,
                              overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: _onAtividadeSelecionada,
                  isExpanded: true,
                ),
              const SizedBox(height: 16),
              if (_atividadeSelecionada != null)
                DropdownButtonFormField<Fazenda>(
                  value: _fazendaSelecionada,
                  hint: const Text('Selecione a Fazenda'),
                  items: _fazendasDisponiveis
                      .map((f) => DropdownMenuItem(
                          value: f,
                          child: Text(f.nome, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: _onFazendaSelecionada,
                  isExpanded: true,
                ),
              const SizedBox(height: 16),
              if (_isLoadingTalhoes)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator()))
              else if (_fazendaSelecionada != null && _talhoesDisponiveis.isNotEmpty)
                Container(
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView(
                    children: [
                      CheckboxListTile(
                        title: const Text('Selecionar Todos',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        value: _talhoesDisponiveis.isNotEmpty &&
                            _talhoesSelecionados.length == _talhoesDisponiveis.length,
                        onChanged: (selecionarTodos) {
                          setState(() {
                            if (selecionarTodos == true) {
                              _talhoesSelecionados
                                  .addAll(_talhoesDisponiveis.map((t) => t.id!));
                            } else {
                              _talhoesSelecionados.clear();
                            }
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      const Divider(height: 1),
                      ..._talhoesDisponiveis.map((talhao) => CheckboxListTile(
                            title: Text(talhao.nome),
                            value: _talhoesSelecionados.contains(talhao.id),
                            onChanged: (isSelected) {
                              setState(() {
                                if (isSelected == true) {
                                  _talhoesSelecionados.add(talhao.id!);
                                } else {
                                  _talhoesSelecionados.remove(talhao.id);
                                }
                              });
                            },
                            controlAffinity: ListTileControlAffinity.leading,
                          )),
                    ],
                  ),
                )
              else if (_fazendaSelecionada != null)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Nenhum talhão encontrado para esta fazenda.",
                      textAlign: TextAlign.center),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _talhoesSelecionados.isNotEmpty
              ? () {
                  final selecionados = _talhoesDisponiveis
                      .where((t) => _talhoesSelecionados.contains(t.id!))
                      .toList();
                  Navigator.of(context).pop(selecionados);
                }
              : null,
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}

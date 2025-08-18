// lib/pages/menu/relatorio_diario_page.dart (VERSÃO ATUALIZADA COM CALENDÁRIO)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

// Imports do projeto
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/providers/team_provider.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/data/repositories/fazenda_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/services/export_service.dart';

import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/data/repositories/diario_de_campo_repository.dart';

// <<< 1. A ESTRUTURA DOS PASSOS FOI ALTERADA PARA UMA LÓGICA MAIS SIMPLES >>>
enum RelatorioStep {
  selecionarFiltros,
  visualizarEPreencher,
}

class RelatorioDiarioPage extends StatefulWidget {
  const RelatorioDiarioPage({super.key});

  @override
  State<RelatorioDiarioPage> createState() => _RelatorioDiarioPageState();
}

class _RelatorioDiarioPageState extends State<RelatorioDiarioPage> {
  RelatorioStep _currentStep = RelatorioStep.selecionarFiltros;

  // Controladores
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
  final _diarioRepo = DiarioDeCampoRepository();

  // Estado dos filtros
  DateTime _dataSelecionada = DateTime.now();
  List<Projeto> _projetosDisponiveis = [];
  Projeto? _projetoSelecionado;
  List<Atividade> _atividadesDisponiveis = [];
  Atividade? _atividadeSelecionada;
  List<Fazenda> _fazendasDisponiveis = [];
  Fazenda? _fazendaSelecionada;
  List<Talhao> _talhoesDisponiveis = [];
  Talhao? _talhaoSelecionado;

  // Estado dos resultados
  DiarioDeCampo? _diarioAtual;
  List<Parcela> _parcelasDoRelatorio = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final teamProvider = Provider.of<TeamProvider>(context, listen: false);
    _liderController.text = teamProvider.lider ?? '';
    _ajudantesController.text = teamProvider.ajudantes ?? '';
    _carregarProjetos();
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

  Future<void> _carregarProjetos() async {
    setState(() => _isLoading = true);
    _projetosDisponiveis = await _projetoRepo.getTodosOsProjetosParaGerente();
    setState(() => _isLoading = false);
  }

  Future<void> _selecionarData(BuildContext context) async {
    final DateTime? dataEscolhida = await showDatePicker(
      context: context,
      initialDate: _dataSelecionada,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)), // Permite selecionar até amanhã
    );

    if (dataEscolhida != null && dataEscolhida != _dataSelecionada) {
      setState(() {
        _dataSelecionada = dataEscolhida;
      });
    }
  }

  // <<< 3. LÓGICA PRINCIPAL ATUALIZADA >>>
  Future<void> _gerarRelatorio() async {
    if (_talhaoSelecionado == null || _liderController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Por favor, preencha todos os filtros obrigatórios.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    setState(() => _isLoading = true);

    final dataFormatada = DateFormat('yyyy-MM-dd').format(_dataSelecionada);
    final lider = _liderController.text.trim();
    final talhaoId = _talhaoSelecionado!.id!;

    // Busca os dois tipos de dados em paralelo para mais performance
    final results = await Future.wait([
      _diarioRepo.getDiario(dataFormatada, lider, talhaoId),
      _parcelaRepo.getParcelasDoDiaPorEquipeEFiltros(
        nomeLider: lider,
        dataSelecionada: _dataSelecionada,
        talhaoId: talhaoId,
      ),
    ]);

    _diarioAtual = results[0] as DiarioDeCampo?;
    _parcelasDoRelatorio = results[1] as List<Parcela>;

    // Preenche os controladores do diário de campo (seja com dados existentes ou vazios)
    _preencherControladoresDiario();

    setState(() {
      _isLoading = false;
      _currentStep = RelatorioStep.visualizarEPreencher;
    });
  }
  
  void _preencherControladoresDiario() {
    _kmInicialController.text = _diarioAtual?.kmInicial?.toString() ?? '';
    _kmFinalController.text = _diarioAtual?.kmFinal?.toString() ?? '';
    _destinoController.text = _diarioAtual?.localizacaoDestino ?? '';
    _pedagioController.text = _diarioAtual?.pedagioValor?.toString() ?? '';
    _abastecimentoController.text = _diarioAtual?.abastecimentoValor?.toString() ?? '';
    _marmitasController.text = _diarioAtual?.alimentacaoMarmitasQtd?.toString() ?? '';
    _refeicaoValorController.text = _diarioAtual?.alimentacaoRefeicaoValor?.toString() ?? '';
    _refeicaoDescricaoController.text = _diarioAtual?.alimentacaoDescricao ?? '';
    _placaController.text = _diarioAtual?.veiculoPlaca ?? '';
    _modeloController.text = _diarioAtual?.veiculoModelo ?? '';
  }
  
  Future<void> _salvarEExportar(bool exportarDiario, bool exportarParcelas) async {
    setState(() => _isLoading = true);
    final dataFormatada = DateFormat('yyyy-MM-dd').format(_dataSelecionada);

    final diarioParaSalvar = DiarioDeCampo(
      id: _diarioAtual?.id,
      dataRelatorio: dataFormatada,
      nomeLider: _liderController.text.trim(),
      projetoId: _projetoSelecionado!.id!,
      talhaoId: _talhaoSelecionado!.id!,
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
    _diarioAtual = diarioParaSalvar;

    setState(() => _isLoading = false);

    final exportService = ExportService();
    if (exportarDiario) {
      await exportService.exportarDiarioDeCampoCsv(context: context, diario: _diarioAtual!);
    }
    if (exportarParcelas) {
      await exportService.exportarRelatorioDiarioCsv(
        context: context, 
        parcelas: _parcelasDoRelatorio, 
        lider: _liderController.text.trim(),
        ajudantes: _ajudantesController.text.trim()
      );
    }

    if (!exportarDiario && !exportarParcelas) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Dados do diário salvos com sucesso!'),
        backgroundColor: Colors.green,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatório Diário da Equipe'),
        leading: _currentStep != RelatorioStep.selecionarFiltros
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _currentStep = RelatorioStep.selecionarFiltros),
              )
            : null,
      ),
      body: IndexedStack(
        index: _currentStep.index,
        children: [
          _buildSelecionarDados(),
          _buildVisualizarEPreencher(),
        ],
      ),
    );
  }

  Widget _buildSelecionarDados() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Text("Filtros do Relatório", style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),

              // <<< 4. WIDGET DO CALENDÁRIO ADICIONADO >>>
              ListTile(
                title: const Text("Data da Atividade"),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(_dataSelecionada), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () => _selecionarData(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.shade400)
                ),
              ),
              const SizedBox(height: 16),
              
              TextFormField(controller: _liderController, decoration: const InputDecoration(labelText: 'Líder da Equipe', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              TextFormField(controller: _ajudantesController, decoration: const InputDecoration(labelText: 'Ajudantes', border: OutlineInputBorder())),
              const SizedBox(height: 16),

              DropdownButtonFormField<Projeto>(
                value: _projetoSelecionado,
                hint: const Text('Selecione o Projeto'),
                items: _projetosDisponiveis.map((p) => DropdownMenuItem(value: p, child: Text(p.nome))).toList(),
                onChanged: _onProjetoSelecionado,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              if (_projetoSelecionado != null) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<Atividade>(
                  value: _atividadeSelecionada,
                  hint: const Text('Selecione a Atividade'),
                  items: _atividadesDisponiveis.map((a) => DropdownMenuItem(value: a, child: Text(a.tipo))).toList(),
                  onChanged: _onAtividadeSelecionada,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ],
              if (_atividadeSelecionada != null) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<Fazenda>(
                  value: _fazendaSelecionada,
                  hint: const Text('Selecione a Fazenda'),
                  items: _fazendasDisponiveis.map((f) => DropdownMenuItem(value: f, child: Text(f.nome))).toList(),
                  onChanged: _onFazendaSelecionada,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ],
              if (_fazendaSelecionada != null) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<Talhao>(
                  value: _talhaoSelecionado,
                  hint: const Text('Selecione o Talhão'),
                  items: _talhoesDisponiveis.map((t) => DropdownMenuItem(value: t, child: Text(t.nome))).toList(),
                  onChanged: (t) => setState(() => _talhaoSelecionado = t),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.receipt_long),
                onPressed: _gerarRelatorio,
                label: const Text('Gerar Relatório'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              )
            ],
          );
  }

  Widget _buildVisualizarEPreencher() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());    
if (_diarioAtual == null && _parcelasDoRelatorio.isEmpty) {
      return const Center(child: Text("Nenhum dado encontrado para o dia selecionado."));
    }
    
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.list_alt), text: "Coletas do Dia"),
            Tab(icon: Icon(Icons.local_shipping), text: "Diário de Campo"),
          ],
        ),
        body: TabBarView(
          children: [
            // Aba 1: Lista de Parcelas
            Column(
              children: [
                 if (_parcelasDoRelatorio.isEmpty)
                  const Expanded(child: Center(child: Text("Nenhuma parcela coletada neste dia.")))
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: _parcelasDoRelatorio.length,
                      itemBuilder: (context, index) {
                        final parcela = _parcelasDoRelatorio[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: ListTile(
                            leading: Icon(parcela.status.icone, color: parcela.status.cor),
                            title: Text("Parcela: ${parcela.idParcela}"),
                            subtitle: Text("Status: ${parcela.status.name}"),
                          ),
                        );
                      },
                    ),
                  )
              ],
            ),
            // Aba 2: Diário de Campo
            Form(
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
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
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            showModalBottomSheet(context: context, builder: (ctx) => Wrap(
              children: [
                 ListTile(
                  leading: const Icon(Icons.save_alt_outlined),
                  title: const Text('Apenas Salvar Diário'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _salvarEExportar(false, false);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.price_check_outlined, color: Colors.green),
                  title: const Text('Salvar e Exportar Diário (CSV)'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _salvarEExportar(true, false);
                  },
                ),
                if(_parcelasDoRelatorio.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.table_rows_outlined, color: Colors.blue),
                    title: const Text('Salvar e Exportar Parcelas (CSV)'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _salvarEExportar(false, true);
                    },
                  ),
                if(_parcelasDoRelatorio.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.collections_bookmark_outlined, color: Colors.purple),
                    title: const Text('Salvar e Exportar TUDO'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _salvarEExportar(true, true);
                    },
                  ),
              ],
            ));
          },
          label: const Text("Salvar / Exportar"),
          icon: const Icon(Icons.save),
        ),
      ),
    );
  }
  
  // Funções que não mudaram
  Future<void> _onProjetoSelecionado(Projeto? projeto) async {
    setState(() {
      _projetoSelecionado = projeto;
      _atividadeSelecionada = null; _atividadesDisponiveis = [];
      _fazendaSelecionada = null; _fazendasDisponiveis = [];
      _talhaoSelecionado = null; _talhoesDisponiveis = [];
    });
    if (projeto != null) {
      _atividadesDisponiveis = await _atividadeRepo.getAtividadesDoProjeto(projeto.id!);
      setState(() {});
    }
  }

  Future<void> _onAtividadeSelecionada(Atividade? atividade) async {
    setState(() {
      _atividadeSelecionada = atividade;
      _fazendaSelecionada = null; _fazendasDisponiveis = [];
      _talhaoSelecionado = null; _talhoesDisponiveis = [];
    });
    if (atividade != null) {
      _fazendasDisponiveis = await _fazendaRepo.getFazendasDaAtividade(atividade.id!);
      setState(() {});
    }
  }

  Future<void> _onFazendaSelecionada(Fazenda? fazenda) async {
    setState(() {
      _fazendaSelecionada = fazenda;
      _talhaoSelecionado = null; _talhoesDisponiveis = [];
    });
    if (fazenda != null) {
      _talhoesDisponiveis = await _talhaoRepo.getTalhoesDaFazenda(fazenda.id, fazenda.atividadeId);
      setState(() {});
    }
  }
}
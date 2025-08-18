// lib/pages/menu/relatorio_diario_page.dart (VERSÃO COM DIÁRIO DE CAMPO)

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

// <<< NOVOS IMPORTS >>>
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/data/repositories/diario_de_campo_repository.dart';

enum RelatorioStep {
  confirmarEquipe,
  selecionarDados,
  preencherInformacoesExtras, // <<< NOVO PASSO
  visualizarRelatorio
}

class RelatorioDiarioPage extends StatefulWidget {
  const RelatorioDiarioPage({super.key});

  @override
  State<RelatorioDiarioPage> createState() => _RelatorioDiarioPageState();
}

class _RelatorioDiarioPageState extends State<RelatorioDiarioPage> {
  RelatorioStep _currentStep = RelatorioStep.confirmarEquipe;

  // Controladores da Equipe
  final _liderController = TextEditingController();
  final _ajudantesController = TextEditingController();

  // <<< NOVOS CONTROLADORES PARA O DIÁRIO DE CAMPO >>>
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
  final _diarioRepo = DiarioDeCampoRepository(); // <<< NOVO REPOSITÓRIO

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

  // ... (initState e os métodos de carregamento em cascata permanecem os mesmos) ...
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

  Future<void> _onProjetoSelecionado(Projeto? projeto) async {
    setState(() {
      _projetoSelecionado = projeto;
      _atividadeSelecionada = null;
      _atividadesDisponiveis = [];
      _fazendaSelecionada = null;
      _fazendasDisponiveis = [];
      _talhaoSelecionado = null;
      _talhoesDisponiveis = [];
    });
    if (projeto != null) {
      _atividadesDisponiveis =
          await _atividadeRepo.getAtividadesDoProjeto(projeto.id!);
      setState(() {});
    }
  }

  Future<void> _onAtividadeSelecionada(Atividade? atividade) async {
    setState(() {
      _atividadeSelecionada = atividade;
      _fazendaSelecionada = null;
      _fazendasDisponiveis = [];
      _talhaoSelecionado = null;
      _talhoesDisponiveis = [];
    });
    if (atividade != null) {
      _fazendasDisponiveis =
          await _fazendaRepo.getFazendasDaAtividade(atividade.id!);
      setState(() {});
    }
  }

  Future<void> _onFazendaSelecionada(Fazenda? fazenda) async {
    setState(() {
      _fazendaSelecionada = fazenda;
      _talhaoSelecionado = null;
      _talhoesDisponiveis = [];
    });
    if (fazenda != null) {
      _talhoesDisponiveis =
          await _talhaoRepo.getTalhoesDaFazenda(fazenda.id, fazenda.atividadeId);
      setState(() {});
    }
  }

  // <<< MÉTODO ATUALIZADO PARA IR PARA O NOVO PASSO >>>
  Future<void> _avancarParaInformacoesExtras() async {
    if (_talhaoSelecionado == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Todos os campos são obrigatórios.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    setState(() => _isLoading = true);
    // Tenta carregar um diário existente para pré-preencher o formulário
    final dataFormatada = DateFormat('yyyy-MM-dd').format(_dataSelecionada);
    _diarioAtual = await _diarioRepo.getDiario(dataFormatada, _liderController.text.trim(), _talhaoSelecionado!.id!);

    if (_diarioAtual != null) {
      _kmInicialController.text = _diarioAtual!.kmInicial?.toString() ?? '';
      _kmFinalController.text = _diarioAtual!.kmFinal?.toString() ?? '';
      _destinoController.text = _diarioAtual!.localizacaoDestino ?? '';
      _pedagioController.text = _diarioAtual!.pedagioValor?.toString() ?? '';
      _abastecimentoController.text = _diarioAtual!.abastecimentoValor?.toString() ?? '';
      _marmitasController.text = _diarioAtual!.alimentacaoMarmitasQtd?.toString() ?? '';
      _refeicaoValorController.text = _diarioAtual!.alimentacaoRefeicaoValor?.toString() ?? '';
      _refeicaoDescricaoController.text = _diarioAtual!.alimentacaoDescricao ?? '';
      _placaController.text = _diarioAtual!.veiculoPlaca ?? '';
      _modeloController.text = _diarioAtual!.veiculoModelo ?? '';
    } else {
      // Limpa os campos se não encontrar um diário
      _kmInicialController.clear();
      _kmFinalController.clear();
      _destinoController.clear();
      _pedagioController.clear();
      _abastecimentoController.clear();
      _marmitasController.clear();
      _refeicaoValorController.clear();
      _refeicaoDescricaoController.clear();
      _placaController.clear();
      _modeloController.clear();
    }

    setState(() {
      _isLoading = false;
      _currentStep = RelatorioStep.preencherInformacoesExtras;
    });
  }

  // <<< NOVO MÉTODO PARA SALVAR O DIÁRIO E GERAR O RELATÓRIO FINAL >>>
  Future<void> _salvarDiarioEGerarRelatorio() async {
    setState(() => _isLoading = true);
    final dataFormatada = DateFormat('yyyy-MM-dd').format(_dataSelecionada);

    // Salva os dados do diário no banco
    final diarioParaSalvar = DiarioDeCampo(
      id: _diarioAtual?.id,
      dataRelatorio: dataFormatada,
      nomeLider: _liderController.text.trim(),
      projetoId: _projetoSelecionado!.id!,
      talhaoId: _talhaoSelecionado!.id!,
      kmInicial: double.tryParse(_kmInicialController.text),
      kmFinal: double.tryParse(_kmFinalController.text),
      localizacaoDestino: _destinoController.text.trim(),
      pedagioValor: double.tryParse(_pedagioController.text),
      abastecimentoValor: double.tryParse(_abastecimentoController.text),
      alimentacaoMarmitasQtd: int.tryParse(_marmitasController.text),
      alimentacaoRefeicaoValor: double.tryParse(_refeicaoValorController.text),
      alimentacaoDescricao: _refeicaoDescricaoController.text.trim(),
      veiculoPlaca: _placaController.text.trim(),
      veiculoModelo: _modeloController.text.trim(),
      equipeNoCarro: '${_liderController.text.trim()}, ${_ajudantesController.text.trim()}',
      lastModified: DateTime.now().toIso8601String(),
    );
    await _diarioRepo.insertOrUpdateDiario(diarioParaSalvar);
    _diarioAtual = diarioParaSalvar;

    // Busca as parcelas para o relatório
    _parcelasDoRelatorio = await _parcelaRepo.getParcelasDoDiaPorEquipeEFiltros(
      nomeLider: _liderController.text.trim(),
      dataSelecionada: _dataSelecionada,
      talhaoId: _talhaoSelecionado!.id!,
    );

    setState(() {
      _isLoading = false;
      _currentStep = RelatorioStep.visualizarRelatorio;
    });
  }
  
  // <<< NOVO WIDGET PARA O PASSO 3 >>>
  Widget _buildInformacoesExtras() {
    return _isLoading
      ? const Center(child: CircularProgressIndicator())
      : Form(
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Text("Passo 2 de 3: Diário de Campo", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            TextFormField(controller: _placaController, decoration: const InputDecoration(labelText: 'Placa do Veículo', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextFormField(controller: _modeloController, decoration: const InputDecoration(labelText: 'Modelo do Veículo', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextFormField(controller: _kmInicialController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'KM Inicial', border: OutlineInputBorder()))),
              const SizedBox(width: 16),
              Expanded(child: TextFormField(controller: _kmFinalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'KM Final', border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 16),
            TextFormField(controller: _destinoController, decoration: const InputDecoration(labelText: 'Localização/Destino', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextFormField(controller: _pedagioController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pedágio (R\$)', border: OutlineInputBorder()))),
              const SizedBox(width: 16),
              Expanded(child: TextFormField(controller: _abastecimentoController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Abastecimento (R\$)', border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 16),
            const Text("Alimentação", style: TextStyle(fontWeight: FontWeight.bold)),
            Row(children: [
              Expanded(child: TextFormField(controller: _marmitasController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qtd. Marmitas', border: OutlineInputBorder()))),
              const SizedBox(width: 16),
              Expanded(child: TextFormField(controller: _refeicaoValorController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Refeição (R\$)', border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 16),
            TextFormField(controller: _refeicaoDescricaoController, decoration: const InputDecoration(labelText: 'Descrição da Refeição (Local, etc)', border: OutlineInputBorder())),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.receipt_long),
              onPressed: _salvarDiarioEGerarRelatorio,
              label: const Text('Gerar Relatório'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            )
          ],
        ),
      );
  }

  // <<< WIDGET DE VISUALIZAÇÃO ATUALIZADO COM 2 BOTÕES DE EXPORTAÇÃO >>>
  Widget _buildVisualizarRelatorio() {
    return _isLoading
      ? const Center(child: CircularProgressIndicator())
      : Scaffold(
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "Passo 3 de 3: Resultado do Dia",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (_parcelasDoRelatorio.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text('Nenhuma parcela coletada para os filtros selecionados.'),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: _parcelasDoRelatorio.length,
                    itemBuilder: (context, index) {
                      final parcela = _parcelasDoRelatorio[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(child: Text((index + 1).toString())),
                          title: Text('Parcela ID: ${parcela.idParcela}'),
                          subtitle: Text(
                            'Status: ${parcela.status.name}\n'
                            'ID Único: ${parcela.idUnicoAmostra ?? 'N/A'}'
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
          floatingActionButton: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_parcelasDoRelatorio.isNotEmpty)
                FloatingActionButton.extended(
                  heroTag: 'export_parcelas_btn',
                  icon: const Icon(Icons.table_rows),
                  label: const Text('Exportar Parcelas'),
                  onPressed: _exportarRelatorioParcelas,
                ),
              const SizedBox(height: 10),
              if (_diarioAtual != null)
                FloatingActionButton.extended(
                  heroTag: 'export_diario_btn',
                  icon: const Icon(Icons.price_check),
                  label: const Text('Exportar Diário'),
                  onPressed: _exportarRelatorioDiario,
                  backgroundColor: Colors.green,
                ),
            ],
          ),
        );
  }

  // Funções de exportação
  Future<void> _exportarRelatorioParcelas() async {
    final exportService = ExportService();
    await exportService.exportarRelatorioDiarioCsv(
      context: context,
      parcelas: _parcelasDoRelatorio,
      lider: _liderController.text,
      ajudantes: _ajudantesController.text,
    );
  }

  Future<void> _exportarRelatorioDiario() async {
    final exportService = ExportService();
    // Você precisará criar este método no seu ExportService
    if (_diarioAtual != null) {
      await exportService.exportarDiarioDeCampoCsv(
        context: context,
        diario: _diarioAtual!,
      );
    }
  }

  // Build e lógica de navegação
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatório Diário da Equipe'),
        leading: _currentStep != RelatorioStep.confirmarEquipe
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    if (_currentStep == RelatorioStep.visualizarRelatorio) {
                      _currentStep = RelatorioStep.preencherInformacoesExtras;
                    } else if (_currentStep == RelatorioStep.preencherInformacoesExtras) {
                      _currentStep = RelatorioStep.selecionarDados;
                    } else if (_currentStep == RelatorioStep.selecionarDados) {
                      _currentStep = RelatorioStep.confirmarEquipe;
                    }
                  });
                },
              )
            : null,
      ),
      body: IndexedStack(
        index: _currentStep.index,
        children: [
          _buildConfirmarEquipe(),
          _buildSelecionarDados(),
          _buildInformacoesExtras(), // <<< NOVO WIDGET NA PILHA
          _buildVisualizarRelatorio(),
        ],
      ),
    );
  }
  
  // <<< BOTÃO DE AVANÇO ATUALIZADO NA TELA DE SELEÇÃO >>>
  Widget _buildSelecionarDados() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Text("Passo 1 de 3: Selecione os filtros", style: Theme.of(context).textTheme.titleLarge),
              // ... todos os seus Dropdowns ...
               const SizedBox(height: 16),
              DropdownButtonFormField<Projeto>(
                value: _projetoSelecionado,
                hint: const Text('Selecione o Projeto'),
                items: _projetosDisponiveis
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.nome)))
                    .toList(),
                onChanged: _onProjetoSelecionado,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              if (_projetoSelecionado != null) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<Atividade>(
                  value: _atividadeSelecionada,
                  hint: const Text('Selecione a Atividade'),
                  items: _atividadesDisponiveis
                      .map((a) =>
                          DropdownMenuItem(value: a, child: Text(a.tipo)))
                      .toList(),
                  onChanged: _onAtividadeSelecionada,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ],
              if (_atividadeSelecionada != null) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<Fazenda>(
                  value: _fazendaSelecionada,
                  hint: const Text('Selecione a Fazenda'),
                  items: _fazendasDisponiveis
                      .map((f) =>
                          DropdownMenuItem(value: f, child: Text(f.nome)))
                      .toList(),
                  onChanged: _onFazendaSelecionada,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ],
              if (_fazendaSelecionada != null) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<Talhao>(
                  value: _talhaoSelecionado,
                  hint: const Text('Selecione o Talhão'),
                  items: _talhoesDisponiveis
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t.nome)))
                      .toList(),
                  onChanged: (t) => setState(() => _talhaoSelecionado = t),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ],

              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _avancarParaInformacoesExtras, // <<< MUDOU AQUI
                label: const Text('Próximo'),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              )
            ],
          );
  }

  // O _buildConfirmarEquipe não precisa de alterações
  Widget _buildConfirmarEquipe() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text("Passo 1 de 3: Confirme a equipe",
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
            "Confirme ou edite os dados da equipe para este relatório:",
            style: TextStyle(fontSize: 16, color: Colors.grey)),
        const SizedBox(height: 20),
        TextField(
          controller: _liderController,
          decoration: const InputDecoration(
              labelText: 'Líder da Equipe', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _ajudantesController,
          decoration: const InputDecoration(
              labelText: 'Ajudantes', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () {
            final teamProvider =
                Provider.of<TeamProvider>(context, listen: false);
            teamProvider.setTeam(
                _liderController.text, _ajudantesController.text);
            setState(() => _currentStep = RelatorioStep.selecionarDados);
          },
          label: const Text('Próximo'),
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12)),
        )
      ],
    );
  }

}
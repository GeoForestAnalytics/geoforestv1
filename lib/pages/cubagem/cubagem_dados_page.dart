// lib/pages/cubagem/cubagem_dados_page.dart (VERSÃO COM VALIDAÇÃO FINAL CORRIGIDA)

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/cubagem_arvore_model.dart';
import '../../models/cubagem_secao_model.dart';
import '../../widgets/cubagem_secao_dialog.dart';
import 'package:geoforestv1/widgets/grafico_afilamento_widget.dart';

import 'package:geoforestv1/data/repositories/cubagem_repository.dart';

class CubagemResult {
  final CubagemArvore arvore;
  final bool irParaProxima;

  CubagemResult({
    required this.arvore,
    this.irParaProxima = false,
  });
}

class CubagemDadosPage extends StatefulWidget {
  final String metodo;
  final CubagemArvore? arvoreParaEditar;

  const CubagemDadosPage({
    super.key,
    required this.metodo,
    this.arvoreParaEditar,
  });

  @override
  State<CubagemDadosPage> createState() => _CubagemDadosPageState();
}

class _CubagemDadosPageState extends State<CubagemDadosPage> {
  final _formKey = GlobalKey<FormState>();
  final _cubagemRepository = CubagemRepository();

  // Todos os controladores e variáveis de estado permanecem os mesmos...
  late TextEditingController _idFazendaController;
  late TextEditingController _fazendaController;
  late TextEditingController _talhaoController;
  late TextEditingController _identificadorController;
  late TextEditingController _alturaTotalController;
  late TextEditingController _valorCAPController;
  late TextEditingController _alturaBaseController;
  late TextEditingController _classeController;
  late TextEditingController _observacaoController;
  late TextEditingController _rfController;

  Position? _posicaoAtualExibicao;
  bool _buscandoLocalizacao = false;
  String? _erroLocalizacao;
  
  String _tipoMedidaCAP = 'fita'; 
  List<CubagemSecao> _secoes = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final arvore = widget.arvoreParaEditar;

    _idFazendaController = TextEditingController(text: arvore?.idFazenda ?? '');
    _fazendaController = TextEditingController(text: arvore?.nomeFazenda ?? '');
    _talhaoController = TextEditingController(text: arvore?.nomeTalhao ?? '');
    _identificadorController = TextEditingController(text: arvore?.identificador ?? '');
    _alturaTotalController = TextEditingController(text: (arvore?.alturaTotal ?? 0) > 0 ? arvore!.alturaTotal.toString() : '');
    _valorCAPController = TextEditingController(text: (arvore?.valorCAP ?? 0) > 0 ? arvore!.valorCAP.toString() : '');
    _alturaBaseController = TextEditingController(text: (arvore?.alturaBase ?? 0) > 0 ? arvore!.alturaBase.toString() : '');
    _classeController = TextEditingController(text: arvore?.classe ?? '');
    _tipoMedidaCAP = arvore?.tipoMedidaCAP ?? 'fita';
    _observacaoController = TextEditingController(text: arvore?.observacao ?? '');
    _rfController = TextEditingController(text: arvore?.rf ?? '');
    
    if (arvore?.latitude != null && arvore?.longitude != null) {
      _posicaoAtualExibicao = Position(
        latitude: arvore!.latitude!, longitude: arvore.longitude!,
        timestamp: DateTime.now(), accuracy: 0, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0
      );
    }

    final arvoreId = arvore?.id;
    if (arvoreId != null) {
      _carregarSecoes(arvoreId);
    }
  }
  
  @override
  void dispose() {
    _idFazendaController.dispose();
    _fazendaController.dispose();
    _talhaoController.dispose();
    _identificadorController.dispose();
    _alturaTotalController.dispose();
    _valorCAPController.dispose();
    _alturaBaseController.dispose();
    _classeController.dispose();
    _observacaoController.dispose();
    _rfController.dispose();
    super.dispose();
  }
  
  // As outras funções (initState, dispose, _gerarSecoesAutomaticas, etc.) continuam as mesmas...
  void _gerarSecoesAutomaticas() {
    final alturaTotalStr = _alturaTotalController.text.replaceAll(',', '.');
    final double? alturaTotal = double.tryParse(alturaTotalStr);

    if (alturaTotal == null || alturaTotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Por favor, preencha a Altura Total (m) para gerar as seções.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    
    final metodoParaGerar = widget.arvoreParaEditar?.metodoCubagem ?? widget.metodo;

    List<double> alturasDeMedicao = [];

    if (metodoParaGerar.toUpperCase().contains('RELATIVA')) {
      alturasDeMedicao = [0.0,0.01, 0.02, 0.03, 0.04, 0.05, 0.10, 0.15, 0.20, 0.25, 0.35, 0.45, 0.50, 0.55, 0.65, 0.75, 0.85, 0.90, 0.95].map((p) => alturaTotal * p).toList();
    } else { 
      alturasDeMedicao = [0.0,0.1, 0.3, 0.7, 1.0, 2.0];
      for (double h = 4.0; h < alturaTotal; h += 2.0) {
        alturasDeMedicao.add(h);
      }
    }
    
    alturasDeMedicao = alturasDeMedicao.where((h) => h < alturaTotal).toSet().toList();
    alturasDeMedicao.sort();

    setState(() {
      _secoes = alturasDeMedicao.map((altura) => CubagemSecao(alturaMedicao: altura)).toList();
    });
  }

  String? _validarSecoes() {
    if (_secoes.isEmpty) {
      return 'Gere e preencha as seções antes de salvar.';
    }

    for (int i = 0; i < _secoes.length; i++) {
      final secao = _secoes[i];
      if (secao.circunferencia <= 0 || secao.casca1_mm <= 0 || secao.casca2_mm <= 0) {
        return 'Erro na seção a ${secao.alturaMedicao.toStringAsFixed(2)}m: Todos os campos (circunferência e cascas) devem ser preenchidos e maiores que zero.';
      }
    }

    for (int i = 1; i < _secoes.length; i++) {
      final secaoAnterior = _secoes[i-1];
      final secaoAtual = _secoes[i];

      if (secaoAtual.diametroSemCasca > secaoAnterior.diametroSemCasca) {
        return 'Erro de Afilamento: O diâmetro na altura ${secaoAtual.alturaMedicao.toStringAsFixed(2)}m é maior que o diâmetro na altura ${secaoAnterior.alturaMedicao.toStringAsFixed(2)}m.';
      }
    }
    return null;
  }

  // ==========================================================
  // =============== FUNÇÃO _salvarCubagem CORRIGIDA ============
  // ==========================================================
  void _salvarCubagem({required bool irParaProxima}) async {
    // 1. Valida o formulário principal (Altura, CAP, etc.)
    if (!_formKey.currentState!.validate()) return;
  
    // 2. Chama a nova função de validação robusta para as seções
    final String? erroValidacao = _validarSecoes();
  
    // 3. Se houver uma mensagem de erro, exibe e para a execução
    if (erroValidacao != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(erroValidacao),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5), // Mais tempo para o usuário ler
      ));
      return; // Impede o salvamento
    }
    
    // Se passou por todas as validações, continua com o processo de salvar
    setState(() => _isLoading = true);
  
    // Usa tryParse para evitar crashes se a validação falhar
    final alturaTotal = double.tryParse(_alturaTotalController.text.replaceAll(',', '.')) ?? 0.0;
    final valorCAP = double.tryParse(_valorCAPController.text.replaceAll(',', '.')) ?? 0.0;
    final alturaBase = double.tryParse(_alturaBaseController.text.replaceAll(',', '.')) ?? 0.0;
    
    // Verifica se os valores são válidos (deveria ter sido pego pela validação, mas é uma segurança extra)
    if (alturaTotal <= 0 || valorCAP <= 0 || alturaBase <= 0) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Erro: Valores inválidos detectados. Por favor, verifique os campos.'),
        backgroundColor: Colors.red,
      ));
      return;
    }
  
    final arvoreToSave = CubagemArvore(
      id: widget.arvoreParaEditar?.id,
      talhaoId: widget.arvoreParaEditar?.talhaoId,
      idFazenda: _idFazendaController.text.isNotEmpty ? _idFazendaController.text : null,
      nomeFazenda: _fazendaController.text,
      nomeTalhao: _talhaoController.text,
      identificador: _identificadorController.text,
      alturaTotal: alturaTotal,
      tipoMedidaCAP: _tipoMedidaCAP,
      valorCAP: valorCAP,
      alturaBase: alturaBase,
      classe: _classeController.text.isNotEmpty ? _classeController.text : null,
      observacao: _observacaoController.text.trim().isNotEmpty ? _observacaoController.text.trim() : null,
      latitude: _posicaoAtualExibicao?.latitude,
      longitude: _posicaoAtualExibicao?.longitude,
      metodoCubagem: widget.arvoreParaEditar?.metodoCubagem,
      rf: _rfController.text.trim().isNotEmpty ? _rfController.text.trim() : null,
      
      // --- CORREÇÃO AQUI ---
      // Antes estava: widget.arvoreParaEditar?.dataColeta
      // Mude para: DateTime.now() para registrar o momento exato da coleta
      dataColeta: DateTime.now(), 
      // --------------------
    );
        
    try {
      await _cubagemRepository.salvarCubagemCompleta(arvoreToSave, _secoes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cubagem salva com sucesso!'), backgroundColor: Colors.green));
      Navigator.of(context).pop(CubagemResult(arvore: arvoreToSave, irParaProxima: irParaProxima));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // As outras funções (_obterLocalizacaoAtual, etc.) continuam as mesmas...
    Future<void> _obterLocalizacaoAtual() async {
    setState(() { _buscandoLocalizacao = true; _erroLocalizacao = null; });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'Serviço de GPS desabilitado.';
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw 'Permissão negada.';
      }
      if (permission == LocationPermission.deniedForever) throw 'Permissão negada permanentemente.';
      
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 20));
      
      setState(() {
        _posicaoAtualExibicao = position;
      });

    } catch (e) {
      setState(() => _erroLocalizacao = e.toString());
    } finally {
      if (mounted) setState(() => _buscandoLocalizacao = false);
    }
  }
  void _carregarSecoes(int arvoreId) async {
    setState(() => _isLoading = true);
    final secoesDoBanco = await _cubagemRepository.getSecoesPorArvoreId(arvoreId);
    if(mounted) {
      setState(() {
        _secoes = secoesDoBanco;
        _isLoading = false;
      });
    }
  }
  void _editarDiametrosSecao(int startIndex) async {
    int currentIndex = startIndex;
    bool continuarEditando = true;

    while (continuarEditando && currentIndex < _secoes.length) {
      final result = await showDialog<SecaoDialogResult>(
        context: context,
        barrierDismissible: false,
        builder: (context) => CubagemSecaoDialog(secaoParaEditar: _secoes[currentIndex]),
      );

      if (result != null) {
        if(mounted) setState(() => _secoes[currentIndex] = result.secao);
        if (result.irParaProximaSecao) {
          currentIndex++;
        } else {
          continuarEditando = false;
        }
      } else {
        continuarEditando = false;
      }
    }
  }
  String? _validadorObrigatorio(String? v) {
    if (v == null || v.trim().isEmpty) return 'Campo obrigatório';
    return null;
  }
  Widget _buildColetorCoordenadas() {
    final latExibicao = _posicaoAtualExibicao?.latitude;
    final lonExibicao = _posicaoAtualExibicao?.longitude;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Coordenadas da Árvore (Opcional)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
          child: Row(children: [
            Expanded(
              child: _buscandoLocalizacao
                ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(width: 16), Text('Buscando...')])
                : _erroLocalizacao != null
                  ? Text('Erro: $_erroLocalizacao', style: const TextStyle(color: Colors.red))
                  : (latExibicao == null)
                    ? const Text('Nenhuma localização obtida.')
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Lat: ${latExibicao.toStringAsFixed(6)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Lon: ${lonExibicao!.toStringAsFixed(6)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (_posicaoAtualExibicao != null && _posicaoAtualExibicao!.accuracy > 0)
                          Text('Precisão: ±${_posicaoAtualExibicao!.accuracy.toStringAsFixed(1)}m', style: TextStyle(color: Colors.grey[700])),
                      ]),
            ),
            IconButton(icon: const Icon(Icons.my_location, color: Color(0xFF1D4433)), onPressed: _buscandoLocalizacao ? null : _obterLocalizacaoAtual, tooltip: 'Obter localização'),
          ]),
        ),
      ],
    );
  }
  
  // O método `build` continua o mesmo.
  @override
  Widget build(BuildContext context) {
    final metodoFinal = widget.arvoreParaEditar?.metodoCubagem ?? widget.metodo;

    return Scaffold(
      appBar: AppBar(
        title: Text('Cubagem - $metodoFinal'),
        actions: [
          if (_isLoading)
            const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)))
          else ...[
            IconButton(icon: const Icon(Icons.save), tooltip: 'Salvar Cubagem', onPressed: () => _salvarCubagem(irParaProxima: false)),
            if (widget.arvoreParaEditar?.id == null)
              IconButton(icon: const Icon(Icons.save_alt), tooltip: 'Salvar e Próxima', onPressed: () => _salvarCubagem(irParaProxima: true)),
          ]
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dados da Árvore', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              TextFormField(controller: _idFazendaController, enabled: false, decoration: const InputDecoration(labelText: 'ID da Fazenda (Automático)', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              TextFormField(controller: _fazendaController, enabled: false, decoration: const InputDecoration(labelText: 'Fazenda (Automático)', border: OutlineInputBorder()), validator: _validadorObrigatorio),
              const SizedBox(height: 16),
              TextFormField(controller: _talhaoController, enabled: false, decoration: const InputDecoration(labelText: 'Talhão (Automático)', border: OutlineInputBorder()), validator: _validadorObrigatorio),
              const SizedBox(height: 16),
              TextFormField(
                controller: _rfController,
                decoration: const InputDecoration(labelText: 'RF / UP', border: OutlineInputBorder()),
              ),
              const Divider(height: 32, thickness: 1),
              TextFormField(controller: _identificadorController, enabled: false, decoration: const InputDecoration(labelText: 'Identificador da Árvore (Automático)', border: OutlineInputBorder()), validator: _validadorObrigatorio),
              const SizedBox(height: 16),
              TextFormField(controller: _alturaTotalController, decoration: const InputDecoration(labelText: 'Altura Total (m)', border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: _validadorObrigatorio),
              const SizedBox(height: 16),
              TextFormField(controller: _classeController, enabled: false, decoration: const InputDecoration(labelText: 'Classe (Automático)', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              TextFormField(controller: _alturaBaseController, decoration: const InputDecoration(labelText: 'Altura da Base (m)', border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: _validadorObrigatorio),
              const SizedBox(height: 16),
              const Text('Medida a 1.30m (CAP/DAP)'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _tipoMedidaCAP,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'fita', child: Text('CAP com Fita Métrica (cm)')),
                  DropdownMenuItem(value: 'suta', child: Text('DAP com Suta (cm)')),
                ],
                onChanged: (String? newValue) { if (newValue != null) setState(() => _tipoMedidaCAP = newValue); },
              ),
              const SizedBox(height: 16),
              TextFormField(controller: _valorCAPController, decoration: const InputDecoration(labelText: 'Valor Medido (cm)', border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: _validadorObrigatorio),
              const SizedBox(height: 16),
              _buildColetorCoordenadas(),
              const SizedBox(height: 16),
              TextFormField(
                controller: _observacaoController,
                decoration: const InputDecoration(
                  labelText: 'Observações da Cubagem', 
                  border: OutlineInputBorder(), 
                  prefixIcon: Icon(Icons.comment_outlined)
                ), 
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.format_list_numbered),
                  label: const Text('Gerar Seções para Preenchimento'),
                  onPressed: _gerarSecoesAutomaticas,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 16)                
                  ),
                ),
              ),
              if (_secoes.length >= 2)
                Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(top: 24.0),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Perfil da Árvore',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        GraficoAfilamentoWidget(secoes: _secoes),
                      ],
                    ),
                  ),
                ),
              const Divider(height: 32, thickness: 2),
              Text('Preencher Medidas das Seções', style: Theme.of(context).textTheme.headlineSmall),
              _secoes.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text('Clique em "Gerar Seções" acima.')))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _secoes.length,
                      itemBuilder: (context, index) {
                        final secao = _secoes[index];
                        final bool isFilled = secao.circunferencia > 0;
                        return Card(
                          color: isFilled ? Colors.green.shade50 : null,
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(backgroundColor: isFilled ? Colors.green : Colors.grey.shade300, foregroundColor: isFilled ? Colors.white : Colors.black54, child: Text('${index + 1}')),
                            title: Text('Medir em ${secao.alturaMedicao.toStringAsFixed(2)} m de altura'),
                            subtitle: Text('Dsc: ${secao.diametroSemCasca.toStringAsFixed(2)} cm'),
                            trailing: const Icon(Icons.edit_note, color: Colors.blueAccent),
                            onTap: () => _editarDiametrosSecao(index),
                          ),
                        );
                      },
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
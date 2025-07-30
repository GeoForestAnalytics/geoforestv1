// lib/pages/cubagem/cubagem_dados_page.dart

import 'package:flutter/material.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../models/cubagem_arvore_model.dart';
import '../../models/cubagem_secao_model.dart';
import '../../widgets/cubagem_secao_dialog.dart';

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
  final dbHelper = DatabaseHelper.instance;

  late TextEditingController _idFazendaController;
  late TextEditingController _fazendaController;
  late TextEditingController _talhaoController;

  late TextEditingController _identificadorController;
  late TextEditingController _alturaTotalController;
  late TextEditingController _valorCAPController;
  late TextEditingController _alturaBaseController;
  late TextEditingController _classeController;
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
    super.dispose();
  }

  void _carregarSecoes(int arvoreId) async {
    setState(() => _isLoading = true);
    final secoesDoBanco = await dbHelper.getSecoesPorArvoreId(arvoreId);
    if(mounted) {
      setState(() {
        _secoes = secoesDoBanco;
        _isLoading = false;
      });
    }
  }

  void _gerarSecoesAutomaticas() {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Preencha os dados da árvore primeiro, especialmente a Altura Total.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    
    final alturaTotal = double.parse(_alturaTotalController.text.replaceAll(',', '.'));
    List<double> alturasDeMedicao = [];

    if (widget.metodo == 'Relativas') {
      alturasDeMedicao = [0.01, 0.02, 0.03, 0.04, 0.05, 0.10, 0.15, 0.20, 0.25, 0.35, 0.45, 0.50, 0.55, 0.65, 0.75, 0.85, 0.90, 0.95].map((p) => alturaTotal * p).toList();
    } else {
      alturasDeMedicao = [0.1, 0.3, 0.7, 1.0, 2.0];
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
  
  void _salvarCubagem({required bool irParaProxima}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_secoes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gere e preencha as seções antes de salvar.'), backgroundColor: Colors.red));
      return;
    }
    if (_secoes.any((s) => s.circunferencia <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha a circunferência de todas as seções.'), backgroundColor: Colors.red));
      return;
    }
      
    setState(() => _isLoading = true);

    final alturaTotal = double.parse(_alturaTotalController.text.replaceAll(',', '.'));
    final valorCAP = double.parse(_valorCAPController.text.replaceAll(',', '.'));
    final alturaBase = double.parse(_alturaBaseController.text.replaceAll(',', '.'));

    final arvoreToSave = CubagemArvore(
      id: widget.arvoreParaEditar?.id,
      talhaoId: widget.arvoreParaEditar?.talhaoId, // << Preserva o talhaoId
      idFazenda: _idFazendaController.text.isNotEmpty ? _idFazendaController.text : null,
      nomeFazenda: _fazendaController.text,
      nomeTalhao: _talhaoController.text,
      identificador: _identificadorController.text,
      alturaTotal: alturaTotal,
      tipoMedidaCAP: _tipoMedidaCAP,
      valorCAP: valorCAP,
      alturaBase: alturaBase,
      classe: _classeController.text.isNotEmpty ? _classeController.text : null,
    );
      
    try {
      await dbHelper.salvarCubagemCompleta(arvoreToSave, _secoes);
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

  String? _validadorObrigatorio(String? v) {
    if (v == null || v.trim().isEmpty) return 'Campo obrigatório';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cubagem - ${widget.metodo}'),
        actions: [
          if (_isLoading)
            const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)))
          else ...[
            IconButton(icon: const Icon(Icons.save), tooltip: 'Salvar Cubagem', onPressed: () => _salvarCubagem(irParaProxima: false)),
            if (widget.arvoreParaEditar == null)
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
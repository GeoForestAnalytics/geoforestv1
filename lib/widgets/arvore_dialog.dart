// lib/widgets/arvore_dialog.dart

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';

class DialogResult {
  final Arvore arvore;
  final bool irParaProxima;
  final bool continuarNaMesmaPosicao;
  final bool atualizarEProximo;
  final bool atualizarEAnterior;

  DialogResult({
    required this.arvore,
    this.irParaProxima = false,
    this.continuarNaMesmaPosicao = false,
    this.atualizarEProximo = false,
    this.atualizarEAnterior = false,
  });
}

class ArvoreDialog extends StatefulWidget {
  final Arvore? arvoreParaEditar;
  final int linhaAtual;
  final int posicaoNaLinhaAtual;
  final bool isAdicionandoFuste;
  final int projetoId; 

  const ArvoreDialog({
    super.key,
    this.arvoreParaEditar,
    required this.linhaAtual,
    required this.posicaoNaLinhaAtual,
    required this.projetoId,
    this.isAdicionandoFuste = false,
  });

  @override
  State<ArvoreDialog> createState() => _ArvoreDialogState();
}

class _ArvoreDialogState extends State<ArvoreDialog> {
  final _formKey = GlobalKey<FormState>();
  final _capController = TextEditingController();
  final _alturaController = TextEditingController();
  final _linhaController = TextEditingController();
  final _posicaoController = TextEditingController();
  final _alturaDanoController = TextEditingController();
  
  bool _mostrarCampoAlturaDano = false; // Controle de visibilidade do Dano
  String _codigoSelecionado = '101'; 
  String? _codigo2Selecionado;
  
  List<Map<String, dynamic>> _regrasDisponiveis = [];
  Map<String, dynamic>? _regraAtual;

  bool _fimDeLinha = false;
  bool _capHabilitado = true;
  bool _alturaHabilitada = true;

  @override
  void initState() {
    super.initState();
    _carregarRegrasEInicializar();
  }

  Future<void> _carregarRegrasEInicializar() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> rules = await db.query(
      'regras_codigos',
      where: 'projetoId = ?',
      whereArgs: [widget.projetoId],
      orderBy: 'codigo_id ASC'
    );

    if (mounted) {
      setState(() {
        _regrasDisponiveis = rules;
        
        final arvore = widget.arvoreParaEditar;
        if (arvore != null) {
          _codigoSelecionado = arvore.codigo;
          _codigo2Selecionado = arvore.codigo2;
          _capController.text = (arvore.cap > 0) ? arvore.cap.toString().replaceAll('.', ',') : '';
          _alturaController.text = arvore.altura?.toString().replaceAll('.', ',') ?? '';
          _alturaDanoController.text = arvore.alturaDano?.toString().replaceAll('.', ',') ?? '';
          _fimDeLinha = arvore.fimDeLinha;
          _linhaController.text = arvore.linha.toString();
          _posicaoController.text = arvore.posicaoNaLinha.toString();
        } else {
          _linhaController.text = widget.linhaAtual.toString();
          _posicaoController.text = widget.posicaoNaLinhaAtual.toString();
        }
        
        _aplicarRegrasDoCodigo(_codigoSelecionado);
      });
    }
  }

  void _aplicarRegrasDoCodigo(String codigoId) {
    final regra = _regrasDisponiveis.firstWhere(
      (r) => r['codigo_id'].toString() == codigoId,
      orElse: () => {},
    );

    setState(() {
      _regraAtual = regra.isNotEmpty ? regra : null;

      if (_regraAtual != null) {
        // Regra de CAP: Se for 'N', desabilita e zera
        if (_regraAtual!['cap'] == 'N') {
          _capHabilitado = false;
          _capController.text = '0';
        } else {
          _capHabilitado = true;
        }

        // Regra de Altura: Se for 'N', desabilita
        _alturaHabilitada = _regraAtual!['altura'] != 'N';

        // Regra de Altura do Dano (Extra1 no seu Excel)
        _mostrarCampoAlturaDano = _regraAtual!['obrigaAlturaDano'] == 'S';
      }
    });
  }

  @override
  void dispose() {
    _capController.dispose();
    _alturaController.dispose();
    _linhaController.dispose();
    _posicaoController.dispose();
    _alturaDanoController.dispose();
    super.dispose();
  }

  void _submit({bool proxima = false, bool mesmoFuste = false, bool atualizarEProximo = false, bool atualizarEAnterior = false}) {
    if (_formKey.currentState!.validate()) {
      
      // Validação baseada no Excel: CAP Obrigatório
      if (_regraAtual != null && _regraAtual!['cap'] == 'S' && (_capController.text == '0' || _capController.text.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("CAP é obrigatório para este código."), backgroundColor: Colors.red));
        return;
      }

      // Validação baseada no Excel: Altura do Dano Obrigatória se campo visível
      if (_mostrarCampoAlturaDano && _alturaDanoController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Altura do Dano é obrigatória."), backgroundColor: Colors.red));
        return;
      }

      final arvore = Arvore(
        id: widget.arvoreParaEditar?.id,
        cap: double.tryParse(_capController.text.replaceAll(',', '.')) ?? 0.0,
        altura: double.tryParse(_alturaController.text.replaceAll(',', '.')),
        alturaDano: double.tryParse(_alturaDanoController.text.replaceAll(',', '.')),
        linha: int.parse(_linhaController.text),
        posicaoNaLinha: int.parse(_posicaoController.text),
        codigo: _codigoSelecionado,
        codigo2: _codigo2Selecionado ?? '',
        fimDeLinha: _fimDeLinha,
        dominante: widget.arvoreParaEditar?.dominante ?? false,
      );

      Navigator.of(context).pop(DialogResult(
        arvore: arvore,
        irParaProxima: proxima,
        continuarNaMesmaPosicao: mesmoFuste,
        atualizarEProximo: atualizarEProximo,
        atualizarEAnterior: atualizarEAnterior,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_regrasDisponiveis.isEmpty) {
      return const Dialog(child: Padding(padding: EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 10), Text("Carregando Regras...")])));
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Coleta L${_linhaController.text} P${_posicaoController.text}", 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 20),

                // Seletor de Código 1 (Dinâmico do Excel)
                DropdownButtonFormField<String>(
                  value: _codigoSelecionado,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Código Primário', border: OutlineInputBorder()),
                  items: _regrasDisponiveis.map((r) {
                    return DropdownMenuItem<String>(
                      value: r['codigo_id'].toString(),
                      child: Text("${r['codigo_id']} - ${r['sigla']} (${r['descricao']})", style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _codigoSelecionado = val);
                      _aplicarRegrasDoCodigo(val);
                    }
                  },
                ),

                const SizedBox(height: 16),

                // CAP
                TextFormField(
                  controller: _capController,
                  enabled: _capHabilitado,
                  decoration: InputDecoration(
                    labelText: 'CAP (cm)',
                    border: const OutlineInputBorder(),
                    filled: !_capHabilitado,
                    fillColor: _capHabilitado ? null : Colors.grey.shade200
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),

                const SizedBox(height: 16),

                // Altura Total
                TextFormField(
                  controller: _alturaController,
                  enabled: _alturaHabilitada,
                  decoration: InputDecoration(
                    labelText: 'Altura Total (m)',
                    border: const OutlineInputBorder(),
                    helperText: _regraAtual?['altura'] == 'C' ? 'Obrigatório ao concluir parcela' : null,
                    filled: !_alturaHabilitada,
                    fillColor: _alturaHabilitada ? null : Colors.grey.shade200
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),

                // Altura do Dano (SÓ APARECE SE O EXCEL DISSER 'S' NA COLUNA EXTRA1)
                if (_mostrarCampoAlturaDano)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: TextFormField(
                      controller: _alturaDanoController,
                      decoration: const InputDecoration(
                        labelText: 'Altura do Dano / Bifurcação (m)',
                        border: OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.straighten, color: Colors.orange),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),

                const SizedBox(height: 24),
                
                // Botões
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR")),
                    ElevatedButton(
                      onPressed: () => _submit(proxima: true),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF023853), foregroundColor: Colors.white),
                      child: const Text("SALVAR E PRÓXIMO"),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
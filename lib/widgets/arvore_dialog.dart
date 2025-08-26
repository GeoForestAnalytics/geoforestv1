// lib/widgets/arvore_dialog.dart (VERSÃO COM LÓGICA DE MÚLTIPLOS FUSTES)

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/arvore_model.dart';

// A classe DialogResult permanece a mesma
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

  const ArvoreDialog({
    super.key,
    this.arvoreParaEditar,
    required this.linhaAtual,
    required this.posicaoNaLinhaAtual,
    this.isAdicionandoFuste = false,
  });

  bool get isEditing => arvoreParaEditar != null && arvoreParaEditar!.id != null;

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

  late Codigo _codigo;
  Codigo2? _codigo2;
  bool _fimDeLinha = false;
  bool _camposHabilitados = true;
  
  // <<< NOVA LÓGICA 1: Variável de estado para controlar o fluxo de "Multipla" >>>
  bool _isInMultiplaFlow = false;

  final _codesRequiringAlturaDano = [
    Codigo.Bifurcada, Codigo.Multipla, Codigo.Quebrada,
    Codigo.AtaqueMacaco, Codigo.Fogo, Codigo.PragasOuDoencas,
    Codigo.VespaMadeira, Codigo.MortaOuSeca, Codigo.PonteiraSeca,
    Codigo.Rebrota, Codigo.AtaqueFormiga, Codigo.Torta,
    Codigo.FoxTail,Codigo.FeridaBase, Codigo.Resinado, Codigo.Outro
  ];

  @override
void initState() {
  super.initState();

  // --- INÍCIO DA CORREÇÃO ---
  final arvore = widget.arvoreParaEditar;

  if (widget.isEditing) {
    // Modo de EDIÇÃO REAL (a árvore já existe no banco)
    _capController.text = arvore!.cap.toString().replaceAll('.', ',');
    _alturaController.text = arvore.altura?.toString().replaceAll('.', ',') ?? '';
    _alturaDanoController.text = arvore.alturaDano?.toString().replaceAll('.', ',') ?? '';
    _codigo = arvore.codigo;
    _codigo2 = arvore.codigo2;
    _fimDeLinha = arvore.fimDeLinha;
    _linhaController.text = arvore.linha.toString();
    _posicaoController.text = arvore.posicaoNaLinha.toString();
  } else {
    // Modo de ADIÇÃO (pode ou não ter um template)
    _capController.text = (arvore?.cap ?? 0) > 0 ? arvore!.cap.toString().replaceAll('.', ',') : '';
    _alturaController.text = arvore?.altura?.toString().replaceAll('.', ',') ?? '';
    _alturaDanoController.text = arvore?.alturaDano?.toString().replaceAll('.', ',') ?? '';
    _codigo = arvore?.codigo ?? Codigo.Normal; // Usa o código do template se existir!
    _codigo2 = arvore?.codigo2;
    _fimDeLinha = arvore?.fimDeLinha ?? false;
    _linhaController.text = (arvore?.linha ?? widget.linhaAtual).toString();
    _posicaoController.text = (arvore?.posicaoNaLinha ?? widget.posicaoNaLinhaAtual).toString();
  }
  // --- FIM DA CORREÇÃO ---

  _checkMultiplaFlow(); // A lógica dos botões agora vai funcionar corretamente
  _atualizarEstadoCampos();
}

  // <<< NOVA LÓGICA 3: Função para verificar e ativar/desativar o fluxo >>>
  void _checkMultiplaFlow() {
    // O fluxo especial só se aplica ao ADICIONAR uma nova árvore (não ao editar)
    // E se o código for Multipla.
    setState(() {
      _isInMultiplaFlow = _codigo == Codigo.Multipla;
    });
  }

  void _atualizarEstadoCampos() {
    setState(() {
      if (_codigo == Codigo.Falha || _codigo == Codigo.Caida) {
        _camposHabilitados = false;
        _capController.text = '0';
        _alturaController.clear();
        _alturaDanoController.clear();
      } else {
        _camposHabilitados = true;
        if (_capController.text == '0') {
          _capController.clear();
        }
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
      final double cap = double.tryParse(_capController.text.replaceAll(',', '.')) ?? 0.0;
      final double? altura = _alturaController.text.isNotEmpty ? double.tryParse(_alturaController.text.replaceAll(',', '.')) : null;
      final double? alturaDano = _alturaDanoController.text.isNotEmpty ? double.tryParse(_alturaDanoController.text.replaceAll(',', '.')) : null;
      final int linha = int.tryParse(_linhaController.text) ?? widget.linhaAtual;
      final int posicao = int.tryParse(_posicaoController.text) ?? widget.posicaoNaLinhaAtual;

      final arvore = Arvore(
        id: widget.arvoreParaEditar?.id,
        cap: cap,
        altura: altura,
        alturaDano: alturaDano,
        linha: linha,
        posicaoNaLinha: posicao,
        codigo: _codigo,
        codigo2: _codigo2,
        fimDeLinha: _fimDeLinha,
        dominante: widget.arvoreParaEditar?.dominante ?? false,
        capAuditoria: widget.arvoreParaEditar?.capAuditoria,
        alturaAuditoria: widget.arvoreParaEditar?.alturaAuditoria,
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
    final theme = Theme.of(context);
    final bool showAlturaDano = _codesRequiringAlturaDano.contains(_codigo);

    return Dialog(
      insetPadding: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.isEditing
                    ? 'Editar Árvore'
                    : 'Adicionar Árvore L${_linhaController.text}/P${_posicaoController.text}',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _linhaController,
                            enabled: true,
                            decoration: const InputDecoration(labelText: 'Linha'),
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            validator: (v) => (v == null || v.isEmpty || int.tryParse(v) == null) ? 'Inválido' : null,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: TextFormField(
                            controller: _posicaoController,
                            enabled: true,
                            decoration: const InputDecoration(labelText: 'Posição'),
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            validator: (v) => (v == null || v.isEmpty || int.tryParse(v) == null) ? 'Inválido' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<Codigo>(
                      value: _codigo,
                      decoration: const InputDecoration(labelText: 'Código 1'),
                      items: Codigo.values.map((s) => DropdownMenuItem(value: s, child: Text(s.name))).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _codigo = value);
                          _atualizarEstadoCampos();
                          // <<< NOVA LÓGICA 4: Atualiza o fluxo sempre que o código principal muda >>>
                          _checkMultiplaFlow();
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    // ... o resto dos campos do formulário continua igual ...
                    DropdownButtonFormField<Codigo2?>(
                      value: _codigo2,
                      decoration: const InputDecoration(labelText: 'Código 2 (Opcional)'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Nenhum')),
                        ...Codigo2.values.map((s) => DropdownMenuItem(value: s, child: Text(s.name))),
                      ],
                      onChanged: (value) => setState(() => _codigo2 = value),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _capController,
                      enabled: _camposHabilitados,
                      decoration: const InputDecoration(labelText: 'CAP (cm)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (_camposHabilitados && (value == null || value.isEmpty)) {
                          return 'Campo obrigatório';
                        }
                        if (value != null && value.isNotEmpty && double.tryParse(value.replaceAll(',', '.')) == null) {
                          return 'Número inválido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _alturaController,
                      enabled: _camposHabilitados,
                      decoration: const InputDecoration(labelText: 'Altura Total (m) - Opcional'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    Visibility(
                      visible: showAlturaDano,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: TextFormField(
                          controller: _alturaDanoController,
                          enabled: _camposHabilitados,
                          decoration: const InputDecoration(labelText: 'Altura do Dano/Bifurcação (m)'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ),
                    if (widget.arvoreParaEditar?.capAuditoria != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: widget.arvoreParaEditar!.capAuditoria!.toStringAsFixed(1).replaceAll('.', ','),
                                enabled: false,
                                decoration: const InputDecoration(labelText: 'CAP Anterior (cm)'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                initialValue: widget.arvoreParaEditar!.alturaAuditoria?.toStringAsFixed(1).replaceAll('.', ',') ?? '-',
                                enabled: false,
                                decoration: const InputDecoration(labelText: 'Altura Anterior (m)'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // O switch de fim de linha agora só aparece se não estiver no fluxo "Multipla"
                    if (!widget.isEditing && !_isInMultiplaFlow)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: SwitchListTile(
                          title: const Text('Fim da linha de plantio?'),
                          value: _fimDeLinha,
                          onChanged: (value) => setState(() => _fimDeLinha = value),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // <<< NOVA LÓGICA 5: Renderização condicional dos botões >>>
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8.0,
                runSpacing: 8.0,
                children: widget.isEditing
                    ? [ // Botões para o modo de EDIÇÃO (permanecem os mesmos)
                        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
                        TextButton(onPressed: () => _submit(atualizarEAnterior: true), child: const Text('Anterior')),
                        ElevatedButton(onPressed: () => _submit(), child: const Text('Atualizar')),
                        TextButton(onPressed: () => _submit(atualizarEProximo: true), child: const Text('Próximo')),
                      ]
                    : _isInMultiplaFlow 
                      ? [ // Botões para o modo de ADIÇÃO, quando o código é "Multipla"
                          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
                          // Botão "Adicionar Fuste" continua na mesma posição
                          ElevatedButton(onPressed: () => _submit(mesmoFuste: true), child: const Text('Adic. Fuste')),
                          // Botão "Salvar e Próximo" vai para a PRÓXIMA árvore
                          ElevatedButton(
                            onPressed: () => _submit(proxima: true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: theme.colorScheme.onPrimary,
                            ),
                            child: const Text('Salvar e Próximo'),
                          ),
                        ]
                      : [ // Botões para o modo de ADIÇÃO normal
                          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
                          // Botão "Adic. Fuste" não é o principal aqui
                          OutlinedButton(onPressed: () => _submit(mesmoFuste: true), child: const Text('Adic. Fuste')),
                          ElevatedButton(
                            onPressed: () => _submit(proxima: true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: theme.colorScheme.onPrimary,
                            ),
                            child: const Text('Salvar e Próximo'),
                          ),
                        ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
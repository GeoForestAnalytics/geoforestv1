// ================================================================================
// Arquivo: lib\widgets\arvore_dialog.dart
// ================================================================================

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/especie_model.dart';
import 'package:geoforestv1/data/repositories/especie_repository.dart';
import 'package:geoforestv1/utils/image_utils.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geoforestv1/models/codigo_florestal_model.dart';
import 'package:geoforestv1/data/repositories/codigos_repository.dart';

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
  final bool isBio;
  
  final String projetoNome;
  final String fazendaNome;
  final String talhaoNome;
  final String idParcela;
  
  final String? atividadeTipo;

  const ArvoreDialog({
    super.key,
    this.arvoreParaEditar,
    required this.linhaAtual,
    required this.posicaoNaLinhaAtual,
    this.isAdicionandoFuste = false,
    this.isBio = false,
    required this.projetoNome,
    required this.fazendaNome,
    required this.talhaoNome,
    required this.idParcela,
    this.atividadeTipo,
  });

  bool get isEditing => arvoreParaEditar != null && !isAdicionandoFuste;

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
  final _especieController = TextEditingController();
  
  final _especieRepository = EspecieRepository();

  List<CodigoFlorestal> _codigosDisponiveis = [];
  CodigoFlorestal? _regraAtual; 
  List<String> _siglasSecundariasSelecionadas = []; 

  bool _isLoadingCodigos = true;
  bool _fimDeLinha = false;
  
  List<String> _fotosArvore = [];
  bool _processandoFoto = false;

  @override
  void initState() {
    super.initState();
    
    _linhaController.text = widget.arvoreParaEditar?.linha.toString() ?? widget.linhaAtual.toString();
    _posicaoController.text = widget.arvoreParaEditar?.posicaoNaLinha.toString() ?? widget.posicaoNaLinhaAtual.toString();
    _fimDeLinha = widget.arvoreParaEditar?.fimDeLinha ?? false;
    _fotosArvore = List.from(widget.arvoreParaEditar?.photoPaths ?? []);

    if (widget.arvoreParaEditar != null) {
      _capController.text = (widget.arvoreParaEditar!.cap > 0) ? widget.arvoreParaEditar!.cap.toString().replaceAll('.', ',') : '';
      _alturaController.text = widget.arvoreParaEditar!.altura?.toString().replaceAll('.', ',') ?? '';
      _alturaDanoController.text = widget.arvoreParaEditar!.alturaDano?.toString().replaceAll('.', ',') ?? '';
      _especieController.text = widget.arvoreParaEditar!.especie ?? '';
    }

    _carregarRegras();
  }

  Future<void> _carregarRegras() async {
    String tipo = widget.atividadeTipo ?? "IPC"; 
    
    final repo = CodigosRepository();
    final dados = await repo.carregarCodigos(tipo);
    
    if (mounted) {
      setState(() {
        _codigosDisponiveis = dados;
        _isLoadingCodigos = false;
        
        if (widget.arvoreParaEditar != null) {
           final cod1 = widget.arvoreParaEditar!.codigo;
           final cod2String = widget.arvoreParaEditar!.codigo2; 
           
           try {
             _regraAtual = _codigosDisponiveis.firstWhere((c) => c.sigla == cod1);
           } catch (_) {
             _regraAtual = _codigosDisponiveis.isNotEmpty ? _codigosDisponiveis.first : null;
           }

           if (cod2String != null && cod2String.isNotEmpty) {
             _siglasSecundariasSelecionadas = cod2String.split(',').map((e) => e.trim()).toList();
           }
        } else {
           _regraAtual = _codigosDisponiveis.isNotEmpty ? _codigosDisponiveis.first : null;
        }
        
        _aplicarRegrasAosCampos();
      });
    }
  }

  List<CodigoFlorestal> get _codigosSecundariosDisponiveis {
    return _codigosDisponiveis.where((c) {
      if (_regraAtual != null && c.sigla == _regraAtual!.sigla) return false;
      final sigla = c.sigla.toUpperCase();
      const naoPodeSerSecundario = ['N', 'F', 'CA']; 
      if (naoPodeSerSecundario.contains(sigla)) return false;
      if (c.capBloqueado) return false;
      return true;
    }).toList();
  }

  // --- REGRAS DE NEGÓCIO ---
  bool get _isPrimeiroFuste => !widget.isAdicionandoFuste;

  bool get _bloquearConclusao {
    if (_regraAtual == null) return false;
    if (widget.isEditing) return false; 
    return _regraAtual!.exigeMultiplosFustes && _isPrimeiroFuste;
  }

  void _onCodigoChanged(CodigoFlorestal? novoCodigo) {
    if (novoCodigo == null) return;
    setState(() {
      _regraAtual = novoCodigo;
      _siglasSecundariasSelecionadas.remove(novoCodigo.sigla);
      _aplicarRegrasAosCampos();
    });
  }

  void _aplicarRegrasAosCampos() {
    if (_regraAtual == null) return;

    if (_regraAtual!.capBloqueado) {
      _capController.text = "0"; 
    } else if (_capController.text == "0") {
      _capController.clear();
    }

    if (_regraAtual!.alturaBloqueada) {
      _alturaController.text = ""; 
    }
    
    if (!_regraAtual!.requerAlturaDano) {
      _alturaDanoController.clear();
    }
  }

  Future<void> _capturarFoto() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera, 
      imageQuality: 50, // Qualidade reduzida para rapidez
      maxWidth: 1000,   
      maxHeight: 1000,   
    );
    
    if (photo == null) return;

    setState(() => _processandoFoto = true);

    try {
      final linha = _linhaController.text.isEmpty ? "0" : _linhaController.text;
      final pos = _posicaoController.text.isEmpty ? "0" : _posicaoController.text;
      final String metadados = "Projeto: ${widget.projetoNome} | Talhao: ${widget.talhaoNome} | L:$linha P:$pos";
      final nomeArquivo = "TREE_${widget.talhaoNome}_L${linha}_P${pos}_${DateTime.now().millisecondsSinceEpoch}";

      await ImageUtils.carimbarMetadadosESalvar(
        pathOriginal: photo.path,
        informacoesHierarquia: metadados,
        nomeArquivoFinal: nomeArquivo,
      );

      setState(() {
        _fotosArvore.add(photo.path);
      });

    } catch (e) {
      debugPrint("Erro: $e");
    } finally {
      if (mounted) setState(() => _processandoFoto = false);
    }
  }
  
  Future<void> _mostrarDialogoMultiplaEscolha() async {
    final List<CodigoFlorestal> opcoes = _codigosSecundariosDisponiveis;
    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Códigos Secundários"),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: opcoes.length,
                  itemBuilder: (ctx, index) {
                    final cod = opcoes[index];
                    final isSelected = _siglasSecundariasSelecionadas.contains(cod.sigla);
                    return CheckboxListTile(
                      title: Text("${cod.sigla} - ${cod.descricao}"),
                      value: isSelected,
                      onChanged: (bool? val) {
                        setDialogState(() {
                          if (val == true) {
                            _siglasSecundariasSelecionadas.add(cod.sigla);
                          } else {
                            _siglasSecundariasSelecionadas.remove(cod.sigla);
                          }
                        });
                        this.setState(() {});
                      },
                    );
                  },
                ),
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _capController.dispose();
    _alturaController.dispose();
    _linhaController.dispose();
    _posicaoController.dispose();
    _alturaDanoController.dispose();
    _especieController.dispose();
    super.dispose();
  }

  void _submit({bool proxima = false, bool mesmoFuste = false, bool atualizarEProximo = false, bool atualizarEAnterior = false}) {
    if (_formKey.currentState!.validate()) {
      
      if (widget.isBio && _especieController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Espécie é obrigatória.'), backgroundColor: Colors.red));
        return;
      }

      final double cap = double.tryParse(_capController.text.replaceAll(',', '.')) ?? 0.0;
      final double? altura = _alturaController.text.isNotEmpty ? double.tryParse(_alturaController.text.replaceAll(',', '.')) : null;
      final double? alturaDano = _alturaDanoController.text.isNotEmpty ? double.tryParse(_alturaDanoController.text.replaceAll(',', '.')) : null;
      final int linha = int.tryParse(_linhaController.text) ?? widget.linhaAtual;
      final int posicao = int.tryParse(_posicaoController.text) ?? widget.posicaoNaLinhaAtual;

      String codigoParaSalvar = _regraAtual?.sigla ?? "N";
      String? codigo2ParaSalvar;
      if (_siglasSecundariasSelecionadas.isNotEmpty) {
        _siglasSecundariasSelecionadas.sort();
        codigo2ParaSalvar = _siglasSecundariasSelecionadas.join(',');
      }

      bool isDominante = (widget.arvoreParaEditar?.dominante ?? false);
      if (codigoParaSalvar.toUpperCase() == 'H') {
         isDominante = true;
         codigoParaSalvar = "N"; 
      }

      final arvore = Arvore(
        id: widget.arvoreParaEditar?.id,
        cap: cap,
        altura: altura,
        alturaDano: alturaDano,
        especie: _especieController.text.trim(), 
        linha: linha,
        posicaoNaLinha: posicao,
        codigo: codigoParaSalvar, 
        codigo2: codigo2ParaSalvar, 
        fimDeLinha: _fimDeLinha,
        dominante: isDominante,
        photoPaths: _fotosArvore, 
        lastModified: DateTime.now(),
      );

      // Lógica de retorno baseada nos botões
      Navigator.of(context).pop(DialogResult(
        arvore: arvore,
        irParaProxima: proxima,
        continuarNaMesmaPosicao: mesmoFuste,
        atualizarEProximo: atualizarEProximo,
        atualizarEAnterior: atualizarEAnterior,
      ));
    }
  }

  // Helper para InputDecoration compacto
  InputDecoration _compactInput(String label, {IconData? icon, String? suffix}) {
    return InputDecoration(
      labelText: label,
      isDense: true, // Reduz altura
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      border: const OutlineInputBorder(),
      suffixText: suffix,
      prefixIcon: icon != null ? Icon(icon, size: 18) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Regras Visuais
    bool capHabilitado = !(_regraAtual?.capBloqueado ?? false);
    bool alturaHabilitada = !(_regraAtual?.alturaBloqueada ?? false);
    bool mostraDano = _regraAtual?.requerAlturaDano ?? false;
    bool alturaObrigatoria = _regraAtual?.alturaObrigatoria ?? false;
    
    // Visibilidade do botão Adic. Fuste
    bool permiteFuste = widget.isAdicionandoFuste || (_regraAtual?.exigeMultiplosFustes ?? false);

    return Dialog(
      // Padding minúsculo para usar quase toda a largura e evitar rolagem
      insetPadding: const EdgeInsets.all(8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      
      child: Container(
        padding: const EdgeInsets.all(12),
        // Altura restrita para garantir que caiba acima do teclado
        constraints: const BoxConstraints(maxHeight: 500), 
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // TÍTULO COMPACTO
                Text(
                  widget.isEditing
                      ? 'Editando L${_linhaController.text}/P${_posicaoController.text}'
                      : 'Nova Árvore L${_linhaController.text}/P${_posicaoController.text}',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                // LINHA 1: LINHA | POSIÇÃO
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _linhaController,
                        decoration: _compactInput('Linha'),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _posicaoController,
                        decoration: _compactInput('Posição'),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // LINHA 2: CÓDIGO PRINCIPAL
                 if (!_isLoadingCodigos)
                  Row(
                    children: [
                      // CÓDIGO 1 (PRINCIPAL)
                      Expanded(
                        child: DropdownButtonFormField<CodigoFlorestal>(
                          value: _regraAtual,
                          isExpanded: true,
                          // Encurtei o texto para "Cód. 1" para caber melhor lado a lado
                          decoration: _compactInput('Cód. 1'), 
                          items: _codigosDisponiveis.map((cod) {
                            return DropdownMenuItem(
                              value: cod,
                              child: Text(
                                "${cod.sigla} - ${cod.descricao}", 
                                style: const TextStyle(fontSize: 13), // Fonte levemente menor
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: _onCodigoChanged,
                        ),
                      ),
                      
                      const SizedBox(width: 8), // Espaçamento entre os dois

                      // CÓDIGO 2 (SECUNDÁRIO)
                      Expanded(
                        child: InkWell(
                          onTap: _mostrarDialogoMultiplaEscolha,
                          child: InputDecorator(
                            // Encurtei para "Cód. 2"
                            decoration: _compactInput('Cód. 2', suffix: '▼'),
                            child: Text(
                              _siglasSecundariasSelecionadas.isEmpty 
                                  ? 'Nenhum' 
                                  : _siglasSecundariasSelecionadas.join(', '),
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1, // Garante que não quebre linha
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                
                const SizedBox(height: 8),

                // CAMPO BIO (SE NECESSÁRIO)
                if (widget.isBio) ...[
                  Autocomplete<Especie>(
                    optionsBuilder: (textValue) async {
                      if (textValue.text.length < 2) return const Iterable<Especie>.empty();
                      return await _especieRepository.buscarPorNome(textValue.text);
                    },
                    displayStringForOption: (Especie o) => o.nomeComum,
                    onSelected: (selection) => _especieController.text = selection.nomeComum,
                    fieldViewBuilder: (ctx, ctrl, node, onComplete) {
                      if (_especieController.text.isNotEmpty && ctrl.text.isEmpty) ctrl.text = _especieController.text;
                      ctrl.addListener(() => _especieController.text = ctrl.text);
                      return TextFormField(
                        controller: ctrl,
                        focusNode: node,
                        onEditingComplete: onComplete,
                        decoration: _compactInput('Espécie', icon: Icons.spa),
                        validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],

                // LINHA 4: CAP | ALTURA (AGORA JUNTOS)
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _capController,
                        enabled: capHabilitado,
                        autofocus: true, // Foco aqui para agilizar
                        decoration: _compactInput('CAP', suffix: 'cm').copyWith(
                          fillColor: !capHabilitado ? Colors.grey[200] : null,
                          filled: !capHabilitado,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) => (capHabilitado && (v == null || v.isEmpty)) ? '!' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _alturaController,
                        enabled: alturaHabilitada,
                        decoration: _compactInput('Altura', suffix: alturaObrigatoria ? '* m' : 'm').copyWith(
                          fillColor: !alturaHabilitada ? Colors.grey[200] : null,
                          filled: !alturaHabilitada,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) => (alturaObrigatoria && (v == null || v.isEmpty)) ? '!' : null,
                      ),
                    ),
                  ],
                ),
                
                // ALTURA DE DANO (CONDICIONAL)
                if (mostraDano) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _alturaDanoController,
                    decoration: _compactInput('Alt. Dano (m) *', icon: Icons.warning),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
                  ),
                ],

                const SizedBox(height: 10),

                // LINHA 5: FOTO E FIM DE LINHA
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Botão Foto Compacto
                    InkWell(
                      onTap: _capturarFoto,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            _processandoFoto 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.camera_alt, size: 20),
                            const SizedBox(width: 6),
                            Text(_fotosArvore.isNotEmpty ? "${_fotosArvore.length} Foto(s)" : "Foto"),
                          ],
                        ),
                      ),
                    ),
                    
                    // Switch Fim de Linha
                    if (!widget.isEditing && !permiteFuste)
                      Row(
                        children: [
                          const Text("Fim de linha? ", style: TextStyle(fontSize: 12)),
                          SizedBox(
                            height: 24,
                            child: Switch(
                              value: _fimDeLinha,
                              onChanged: (v) => setState(() => _fimDeLinha = v),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),

                const SizedBox(height: 16),

                // ============================================================
                // GRID DE BOTÕES (2 LINHAS) - CONFORME SEU DESENHO
                // ============================================================
                if (widget.isEditing)
                  // MODO EDIÇÃO (Botões de Navegação)
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar"))),
                          const SizedBox(width: 8),
                          Expanded(child: ElevatedButton(onPressed: () => _submit(), child: const Text("Atualizar"))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: TextButton(onPressed: () => _submit(atualizarEAnterior: true), child: const Text("< Anterior"))),
                          const SizedBox(width: 8),
                          Expanded(child: TextButton(onPressed: () => _submit(atualizarEProximo: true), child: const Text("Próximo >"))),
                        ],
                      )
                    ],
                  )
                else
                  // MODO INSERÇÃO (Layout do seu desenho)
                  Column(
                    children: [
                      // LINHA A: Cancelar | Salvar e Próximo
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                              child: const Text("Cancelar"),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              // Se estiver bloqueado pela regra, mostra mensagem, senão submete
                              onPressed: _bloquearConclusao 
                                ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Insira o 2º fuste antes de avançar.'), backgroundColor: Colors.orange))
                                : () => _submit(proxima: true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _bloquearConclusao ? Colors.grey : theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text("Salvar/Próximo"),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // LINHA B: Salvar | Adic. Fuste
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              // Salvar e fechar (sem ir para próxima)
                              onPressed: _bloquearConclusao
                                ? null // Desabilita se precisa de fuste
                                : () => _submit(proxima: false), 
                              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                              child: const Text("Salvar"),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Botão Adic. Fuste (Só habilitado se permitido/necessário)
                          Expanded(
                            child: IgnorePointer(
                              ignoring: !permiteFuste,
                              child: ElevatedButton(
                                onPressed: () => _submit(mesmoFuste: true),
                                style: ElevatedButton.styleFrom(
                                  // Se bloqueado a conclusão, destaca este botão (Vermelho Claro) para o usuário clicar
                                  backgroundColor: _bloquearConclusao ? Colors.red.shade100 : (permiteFuste ? Colors.blue.shade50 : Colors.grey.shade200),
                                  foregroundColor: _bloquearConclusao ? Colors.red.shade900 : Colors.blue.shade900,
                                  elevation: 0,
                                  side: _bloquearConclusao ? BorderSide(color: Colors.red.shade400) : null,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: Text("Adic. Fuste", style: TextStyle(color: permiteFuste ? null : Colors.grey)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
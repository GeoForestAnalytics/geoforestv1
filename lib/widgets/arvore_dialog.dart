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

  // Lista dinâmica vinda do CSV
  List<CodigoFlorestal> _codigosDisponiveis = [];
  
  // Regra selecionada PRINCIPAL (Objeto CodigoFlorestal)
  CodigoFlorestal? _regraAtual; 
  
  // --- MUDANÇA 1: Lista de siglas para múltiplos códigos secundários ---
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
        
        // --- INICIALIZAÇÃO DOS CÓDIGOS SALVOS ---
        if (widget.arvoreParaEditar != null) {
           final cod1 = widget.arvoreParaEditar!.codigo;
           final cod2String = widget.arvoreParaEditar!.codigo2; // Ex: "A,B"
           
           // Tenta encontrar o objeto do Código 1
           try {
             _regraAtual = _codigosDisponiveis.firstWhere((c) => c.sigla == cod1);
           } catch (_) {
             _regraAtual = _codigosDisponiveis.isNotEmpty ? _codigosDisponiveis.first : null;
           }

           // --- MUDANÇA 2: Parse da String para Lista ---
           if (cod2String != null && cod2String.isNotEmpty) {
             // Separa por vírgula e remove espaços
             _siglasSecundariasSelecionadas = cod2String.split(',').map((e) => e.trim()).toList();
           }
        } else {
           // Novo cadastro: Padrão (Geralmente o primeiro da lista, 'N')
           _regraAtual = _codigosDisponiveis.isNotEmpty ? _codigosDisponiveis.first : null;
        }
        
        _aplicarRegrasAosCampos();
      });
    }
  }

  // --- FILTRO INTELIGENTE PARA O CÓDIGO SECUNDÁRIO ---
  List<CodigoFlorestal> get _codigosSecundariosDisponiveis {
    return _codigosDisponiveis.where((c) {
      // 1. Não pode ser igual ao código principal selecionado
      if (_regraAtual != null && c.sigla == _regraAtual!.sigla) return false;
      
      final sigla = c.sigla.toUpperCase();

      // 2. Não pode ser um código estrutural (Normal, Falha, Caída)
      const naoPodeSerSecundario = ['N', 'F', 'CA']; 
      if (naoPodeSerSecundario.contains(sigla)) return false;

      // 3. Regra extra de segurança
      if (c.capBloqueado) return false;

      return true;
    }).toList();
  }

  void _onCodigoChanged(CodigoFlorestal? novoCodigo) {
    if (novoCodigo == null) return;
    setState(() {
      _regraAtual = novoCodigo;
      // Se mudar o código principal, remove ele da lista de secundários se estiver lá
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
      imageQuality: 70, 
      maxWidth: 1200,   
      maxHeight: 1200,   
    );
    
    if (photo == null) return;

    setState(() => _processandoFoto = true);

    try {
      final linha = _linhaController.text.isEmpty ? "0" : _linhaController.text;
      final pos = _posicaoController.text.isEmpty ? "0" : _posicaoController.text;
      final String metadados = "Projeto: ${widget.projetoNome} | Fazenda: ${widget.fazendaNome} | Talhao: ${widget.talhaoNome} | Parcela: ${widget.idParcela} | L:$linha P:$pos";
      final nomeArquivo = "TREE_${widget.talhaoNome}_P${widget.idParcela}_L${linha}_P${pos}_${DateTime.now().millisecondsSinceEpoch}";

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
  
  // --- MUDANÇA 3: Função para mostrar o Dialog de Multi-Seleção ---
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
                        // Atualiza a tela principal também
                        this.setState(() {});
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                )
              ],
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
      
      if (widget.isBio) {
        if (_especieController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Espécie é obrigatória.'), backgroundColor: Colors.red));
          return;
        }
      }

      final double cap = double.tryParse(_capController.text.replaceAll(',', '.')) ?? 0.0;
      final double? altura = _alturaController.text.isNotEmpty ? double.tryParse(_alturaController.text.replaceAll(',', '.')) : null;
      final double? alturaDano = _alturaDanoController.text.isNotEmpty ? double.tryParse(_alturaDanoController.text.replaceAll(',', '.')) : null;
      final int linha = int.tryParse(_linhaController.text) ?? widget.linhaAtual;
      final int posicao = int.tryParse(_posicaoController.text) ?? widget.posicaoNaLinhaAtual;

      // Obtém a String (Sigla) dos códigos selecionados
      String codigoParaSalvar = _regraAtual?.sigla ?? "N";
      
      // --- MUDANÇA 4: Juntar os códigos secundários numa String ---
      // Exemplo: se selecionou 'T' e 'V', vira "T,V"
      String? codigo2ParaSalvar;
      if (_siglasSecundariasSelecionadas.isNotEmpty) {
        _siglasSecundariasSelecionadas.sort(); // Opcional: ordenar alfabeticamente
        codigo2ParaSalvar = _siglasSecundariasSelecionadas.join(',');
      }

      // Regra de Dominante (Se o código for H, salva como N mas marca flag)
      bool isDominante = (widget.arvoreParaEditar?.dominante ?? false);
      if (codigoParaSalvar.toUpperCase() == 'H') {
         isDominante = true;
         codigoParaSalvar = "N"; // Salva como Normal
      }

      final arvore = Arvore(
        id: widget.arvoreParaEditar?.id,
        cap: cap,
        altura: altura,
        alturaDano: alturaDano,
        especie: _especieController.text.trim(), 
        linha: linha,
        posicaoNaLinha: posicao,
        
        codigo: codigoParaSalvar, // String
        codigo2: codigo2ParaSalvar, // String (agora pode ser "A,B")
        
        fimDeLinha: _fimDeLinha,
        dominante: isDominante,
        photoPaths: _fotosArvore, 
        lastModified: DateTime.now(),
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
    
    // Regras Visuais
    bool capHabilitado = !(_regraAtual?.capBloqueado ?? false);
    bool alturaHabilitada = !(_regraAtual?.alturaBloqueada ?? false);
    bool mostraDano = _regraAtual?.requerAlturaDano ?? false;
    bool alturaObrigatoria = _regraAtual?.alturaObrigatoria ?? false;
    bool permiteFuste = (_regraAtual?.permiteMultifuste ?? true) || widget.isAdicionandoFuste;

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
                    ? 'Editar Árvore L${_linhaController.text}/P${_posicaoController.text}'
                    : 'Adicionar Árvore L${_linhaController.text}/P${_posicaoController.text}',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              if (widget.isBio)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text("Inventário BIO (Nativa)", 
                    textAlign: TextAlign.center, 
                    style: TextStyle(color: Colors.green[700], fontSize: 12, fontWeight: FontWeight.bold)
                  ),
                ),
              const SizedBox(height: 20),
              
              if (_isLoadingCodigos)
                const Center(child: CircularProgressIndicator())
              else
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
                              decoration: const InputDecoration(labelText: 'Linha'),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              validator: (v) => (v == null || v.isEmpty) ? 'Inválido' : null,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: TextFormField(
                              controller: _posicaoController,
                              decoration: const InputDecoration(labelText: 'Posição'),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              validator: (v) => (v == null || v.isEmpty) ? 'Inválido' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // 1. DROPDOWN PRINCIPAL (Todas as opções do CSV)
                      DropdownButtonFormField<CodigoFlorestal>(
                        value: _regraAtual,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Código 1 (Principal)'),
                        items: _codigosDisponiveis.map((cod) {
                          return DropdownMenuItem(
                            value: cod,
                            child: Text("${cod.sigla} - ${cod.descricao}", overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: _onCodigoChanged,
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // --- MUDANÇA 5: NOVO SELETOR MÚLTIPLO ---
                      InkWell(
                        onTap: _mostrarDialogoMultiplaEscolha,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Códigos Secundários',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.arrow_drop_down),
                          ),
                          child: Text(
                            _siglasSecundariasSelecionadas.isEmpty 
                                ? 'Nenhum' 
                                : _siglasSecundariasSelecionadas.join(', '),
                            style: const TextStyle(fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),

                      if (widget.isBio)
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
                              decoration: const InputDecoration(
                                labelText: 'Espécie *', 
                                prefixIcon: Icon(Icons.spa, color: Colors.green)
                              ),
                              validator: (v) => (widget.isBio && (v == null || v.isEmpty)) ? 'Obrigatório' : null,
                            );
                          },
                        ),

                      if (widget.isBio) const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _capController,
                        enabled: capHabilitado,
                        decoration: InputDecoration(
                          labelText: 'CAP (cm)',
                          filled: !capHabilitado,
                          fillColor: Colors.grey[200],
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (capHabilitado && (v == null || v.isEmpty)) return 'Obrigatório';
                          return null;
                        },
                      ),
                      
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _alturaController,
                        enabled: alturaHabilitada,
                        decoration: InputDecoration(
                          labelText: 'Altura Total (m)', 
                          suffixText: alturaObrigatoria ? '*' : '',
                          filled: !alturaHabilitada,
                          fillColor: Colors.grey[200],
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (alturaObrigatoria && (v == null || v.isEmpty)) {
                            return 'Altura Obrigatória';
                          }
                          return null;
                        },
                      ),

                      if (mostraDano)
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: TextFormField(
                            controller: _alturaDanoController,
                            decoration: const InputDecoration(
                              labelText: 'Altura do Dano/Bifurcação (m) *',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.warning_amber_rounded, color: Colors.orange)
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório para este código' : null,
                          ),
                        ),

                      const SizedBox(height: 16),

                      Row(
                        children: [
                          _processandoFoto 
                            ? const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: SizedBox(
                                  width: 30, 
                                  height: 30, 
                                  child: CircularProgressIndicator(strokeWidth: 3)
                                ),
                              )
                            : IconButton(
                                onPressed: _capturarFoto,
                                icon: const Icon(Icons.camera_alt, color: Color(0xFF023853), size: 40),
                                tooltip: "Tirar foto da árvore",
                              ),
                          
                          if (_fotosArvore.isNotEmpty && !_processandoFoto)
                            Text("${_fotosArvore.length} foto(s)", 
                              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)
                            ),
                          
                          const Spacer(),
                          
                          if (!widget.isEditing) 
                            Row(
                              children: [
                                const Text("Fim de linha?", style: TextStyle(fontWeight: FontWeight.bold)),
                                Switch(
                                  value: _fimDeLinha,
                                  activeColor: const Color.fromARGB(255, 10, 82, 177), // Destaque em vermelho para chamar atenção
                                  onChanged: (v) => setState(() => _fimDeLinha = v),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              
              const SizedBox(height: 24),
              
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8.0,
                runSpacing: 8.0,
                children: widget.isEditing
                    ? [
                        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
                        TextButton(onPressed: () => _submit(atualizarEAnterior: true), child: const Text('Anterior')),
                        ElevatedButton(onPressed: () => _submit(), child: const Text('Atualizar')),
                        TextButton(onPressed: () => _submit(atualizarEProximo: true), child: const Text('Próximo')),
                      ]
                    : [
                        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
                        
                        if (permiteFuste)
                           OutlinedButton(onPressed: () => _submit(mesmoFuste: true), child: const Text('Adic. Fuste')),
                        
                        ElevatedButton(
                          onPressed: () => _submit(proxima: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary, 
                            foregroundColor: theme.colorScheme.onPrimary
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
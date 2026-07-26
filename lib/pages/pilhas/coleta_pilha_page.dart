import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoforestv1/data/repositories/pilha_repository.dart';
import 'package:geoforestv1/models/pilha_madeira_model.dart';
import 'package:geoforestv1/pages/pilhas/detalhe_pilha_page.dart';
import 'dart:io';

class ColetaPilhaPage extends StatefulWidget {
  final CentroidePilha centroide;
  final PilhaMadeira? pilhaParaEditar;

  const ColetaPilhaPage({
    super.key,
    required this.centroide,
    this.pilhaParaEditar,
  });

  @override
  State<ColetaPilhaPage> createState() => _ColetaPilhaPageState();
}

class _ColetaPilhaPageState extends State<ColetaPilhaPage> {
  final _pilhaRepository = PilhaRepository();
  final _comprimentoController = TextEditingController();
  final _toraRealController = TextEditingController();
  final _observacoesController = TextEditingController();

  SortimentoConfig? _sortimentoSelecionado;
  List<SecaoPilha> _secoes = [];
  List<TextEditingController> _alturaControllers = [];
  double? _gpsLat;
  double? _gpsLon;
  bool _buscandoGps = false;
  bool _salvando = false;
  final List<String> _fotos = [];
  final _imagePicker = ImagePicker();
  double _fatorEmpilhamento = 0.65;

  bool get _isEdicao => widget.pilhaParaEditar != null;

  @override
  void initState() {
    super.initState();
    final pilha = widget.pilhaParaEditar;
    final sortimentos = widget.centroide.sortimentos;

    if (pilha != null) {
      // Modo edição: pré-preencher todos os campos
      _comprimentoController.text = pilha.comprimentoPilha.toStringAsFixed(2);
      _toraRealController.text = (pilha.comprimentoToraReal ?? pilha.comprimentoTora).toStringAsFixed(2);
      _observacoesController.text = pilha.observacoes ?? '';
      _fotos.addAll(pilha.fotos);
      _fatorEmpilhamento = pilha.fatorEmpilhamento;
      _gpsLat = pilha.latitude;
      _gpsLon = pilha.longitude;

      // Selecionar sortimento pelo nome
      try {
        _sortimentoSelecionado = sortimentos.firstWhere((s) => s.nome == pilha.sortimento);
      } catch (_) {
        _sortimentoSelecionado = sortimentos.isNotEmpty ? sortimentos.first : null;
      }

      // Gerar seções e preencher alturas
      _secoes = List<SecaoPilha>.from(pilha.secoes);
      _alturaControllers = _secoes
          .map((s) => TextEditingController(text: s.altura > 0 ? s.altura.toStringAsFixed(2) : ''))
          .toList();
    } else {
      // Modo novo
      if (sortimentos.length == 1) {
        _sortimentoSelecionado = sortimentos.first;
        _toraRealController.text = sortimentos.first.comprimentoTora.toStringAsFixed(2);
        _fatorEmpilhamento = sortimentos.first.fatorEmpilhamento;
      }
    }
  }

  @override
  void dispose() {
    _comprimentoController.dispose();
    _toraRealController.dispose();
    _observacoesController.dispose();
    for (final c in _alturaControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _onSortimentoChanged(SortimentoConfig? s) {
    setState(() {
      _sortimentoSelecionado = s;
      if (s != null) {
        _toraRealController.text = s.comprimentoTora.toStringAsFixed(2);
        _fatorEmpilhamento = s.fatorEmpilhamento;
      }
    });
  }

  void _gerarSecoes() {
    final comprimento =
        double.tryParse(_comprimentoController.text.replaceAll(',', '.'));
    if (comprimento == null || comprimento <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um comprimento válido (> 0).')),
      );
      return;
    }
    for (final c in _alturaControllers) {
      c.dispose();
    }
    setState(() {
      _secoes = PilhaMadeira.gerarSecoes(comprimento);
      _alturaControllers =
          List.generate(_secoes.length, (_) => TextEditingController());
    });
  }

  Future<void> _capturarGps() async {
    setState(() => _buscandoGps = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('GPS desabilitado.');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Permissão negada.');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Permissão negada permanentemente.');
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      setState(() {
        _gpsLat = pos.latitude;
        _gpsLon = pos.longitude;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro GPS: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _buscandoGps = false);
    }
  }

  Future<void> _tirarFoto() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (picked != null) setState(() => _fotos.add(picked.path));
  }

  Future<void> _escolherDaGaleria() async {
    final picked = await _imagePicker.pickMultiImage(imageQuality: 80);
    if (picked.isNotEmpty) {
      setState(() => _fotos.addAll(picked.map((x) => x.path)));
    }
  }

  void _removerFoto(int index) {
    setState(() => _fotos.removeAt(index));
  }

  double _comprimentoToraEfetivo() {
    final raw = _toraRealController.text.replaceAll(',', '.');
    return double.tryParse(raw) ??
        (_sortimentoSelecionado?.comprimentoTora ?? 2.4);
  }

  double _calcularVolumeEstereo() {
    if (_secoes.isEmpty || _sortimentoSelecionado == null) return 0;
    final comprimento =
        double.tryParse(_comprimentoController.text.replaceAll(',', '.')) ?? 0;
    if (comprimento <= 0) return 0;

    final tora = _comprimentoToraEfetivo();
    final secoesCom = List<SecaoPilha>.generate(_secoes.length, (i) {
      final h =
          double.tryParse(_alturaControllers[i].text.replaceAll(',', '.')) ?? 0;
      return SecaoPilha(
          posicao: _secoes[i].posicao,
          distanciaMetros: _secoes[i].distanciaMetros,
          altura: h);
    });

    double vol = 0;
    if (secoesCom.first.distanciaMetros > 0) {
      vol += (secoesCom.first.altura / 2) *
          secoesCom.first.distanciaMetros *
          tora;
    }
    for (int i = 0; i < secoesCom.length - 1; i++) {
      final L = secoesCom[i + 1].distanciaMetros - secoesCom[i].distanciaMetros;
      vol += ((secoesCom[i].altura + secoesCom[i + 1].altura) / 2) * L * tora;
    }
    if (secoesCom.last.distanciaMetros < comprimento) {
      vol += (secoesCom.last.altura / 2) *
          (comprimento - secoesCom.last.distanciaMetros) *
          tora;
    }
    return vol;
  }

  Future<void> _salvar() async {
    if (_sortimentoSelecionado == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Selecione o sortimento.')));
      return;
    }
    if (_secoes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gere as seções antes de salvar.')));
      return;
    }
    if (_gpsLat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Capture o GPS da pilha.')));
      return;
    }

    for (int i = 0; i < _alturaControllers.length; i++) {
      final h = double.tryParse(_alturaControllers[i].text.replaceAll(',', '.'));
      if (h == null || h <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Informe a altura da Seção ${i + 1}.')),
        );
        return;
      }
      _secoes[i].altura = h;
    }

    setState(() => _salvando = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final nomeLider = prefs.getString('nome_lider') ?? '';
      final comprimento =
          double.tryParse(_comprimentoController.text.replaceAll(',', '.')) ?? 0;
      final toraReal = _comprimentoToraEfetivo();
      final toraOS = _sortimentoSelecionado!.comprimentoTora;
      final toraRealDiferente = (toraReal - toraOS).abs() > 0.01;
      final obsText = _observacoesController.text.trim();

      if (_isEdicao) {
        // Atualizar pilha existente
        final pilhaAtualizada = PilhaMadeira(
          id: widget.pilhaParaEditar!.id,
          talhaoId: widget.pilhaParaEditar!.talhaoId,
          centroideId: widget.pilhaParaEditar!.centroideId,
          numeroPilha: widget.pilhaParaEditar!.numeroPilha,
          sortimento: _sortimentoSelecionado!.nome,
          dapMin: _sortimentoSelecionado!.dapMin,
          dapMax: _sortimentoSelecionado!.dapMax,
          comprimentoTora: toraOS,
          comprimentoToraReal: toraRealDiferente ? toraReal : null,
          comprimentoPilha: comprimento,
          secoes: _secoes,
          latitude: _gpsLat,
          longitude: _gpsLon,
          nomeFazenda: widget.pilhaParaEditar!.nomeFazenda,
          nomeTalhao: widget.pilhaParaEditar!.nomeTalhao,
          nomeLider: nomeLider,
          dataColeta: widget.pilhaParaEditar!.dataColeta,
          observacoes: obsText.isEmpty ? null : obsText,
          fotos: List.from(_fotos),
          fatorEmpilhamento: _fatorEmpilhamento,
          exportada: false,
        );

        await _pilhaRepository.updatePilha(pilhaAtualizada);

        if (mounted) {
          Navigator.of(context).pop(pilhaAtualizada);
        }
      } else {
        // Nova pilha
        final numero =
            await _pilhaRepository.getProximoNumeroPilha(widget.centroide.nomeFazenda);
        final pilha = PilhaMadeira(
          talhaoId: widget.centroide.talhaoId,
          centroideId: widget.centroide.id,
          numeroPilha: numero,
          sortimento: _sortimentoSelecionado!.nome,
          dapMin: _sortimentoSelecionado!.dapMin,
          dapMax: _sortimentoSelecionado!.dapMax,
          comprimentoTora: toraOS,
          comprimentoToraReal: toraRealDiferente ? toraReal : null,
          comprimentoPilha: comprimento,
          secoes: _secoes,
          latitude: _gpsLat,
          longitude: _gpsLon,
          nomeFazenda: widget.centroide.nomeFazenda,
          nomeTalhao: widget.centroide.nomeTalhao,
          nomeLider: nomeLider,
          dataColeta: DateTime.now(),
          observacoes: obsText.isEmpty ? null : obsText,
          fotos: List.from(_fotos),
          fatorEmpilhamento: _fatorEmpilhamento,
        );

        final savedId = await _pilhaRepository.savePilha(pilha);

        if (mounted) {
          final pilhaSalva = pilha..id = savedId;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => DetalhePilhaPage(pilha: pilhaSalva)),
          );
          final vs = pilhaSalva.calcularVolumesolido();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
                'Pilha ${pilhaSalva.numeroPilhaFormatado} salva! Sólido: ${vs.toStringAsFixed(2)} m³')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estereo = _calcularVolumeEstereo();
    final solido = estereo * _fatorEmpilhamento;
    final sortimentos = widget.centroide.sortimentos;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdicao
            ? 'Editar Pilha — ${widget.centroide.nomeTalhao}'
            : 'Nova Pilha — ${widget.centroide.nomeTalhao}'),
        actions: [
          if (_salvando)
            const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          else
            IconButton(
                icon: const Icon(Icons.save),
                tooltip: 'Salvar pilha',
                onPressed: _salvar),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. Sortimento ────────────────────────────────────────────
            _sectionTitle('1. Sortimento'),
            if (sortimentos.isEmpty)
              const Text('Nenhum sortimento encontrado na OS.',
                  style: TextStyle(color: Colors.red))
            else
              DropdownButtonFormField<SortimentoConfig>(
                value: _sortimentoSelecionado,
                hint: const Text('Selecione o sortimento'),
                items: sortimentos
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                              s.dapMin != null || s.dapMax != null
                                  ? '${s.nome}  (${s.descricaoClasse})'
                                  : s.nome),
                        ))
                    .toList(),
                onChanged: _onSortimentoChanged,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),

            if (_sortimentoSelecionado != null) ...[
              const SizedBox(height: 8),
              _infoRow('Tora OS', '${_sortimentoSelecionado!.comprimentoTora.toStringAsFixed(2)} m'),
              if (_sortimentoSelecionado!.dapMin != null ||
                  _sortimentoSelecionado!.dapMax != null)
                _infoRow('Classe DAP', _sortimentoSelecionado!.descricaoClasse),
              if (_sortimentoSelecionado!.volumeEsperadoM3 != null)
                _infoRow('Vol. Esperado',
                    '${_sortimentoSelecionado!.volumeEsperadoM3!.toStringAsFixed(2)} m³'),
            ],

            const SizedBox(height: 20),

            // ── 2. Comprimento da Pilha ──────────────────────────────────
            _sectionTitle('2. Comprimento da Pilha'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _comprimentoController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Comprimento (m)',
                      border: OutlineInputBorder(),
                      suffixText: 'm',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.format_list_numbered),
                  label: const Text('Gerar Seções'),
                  onPressed: _gerarSecoes,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Comprimento real da tora ─────────────────────────────────
            TextFormField(
              controller: _toraRealController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Comprimento real da tora (m)',
                helperText: 'Altere se diferente da OS',
                border: OutlineInputBorder(),
                suffixText: 'm',
              ),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 20),

            // ── 3. GPS da Pilha ──────────────────────────────────────────
            _sectionTitle('3. GPS da Pilha'),
            Row(
              children: [
                Expanded(
                  child: _gpsLat == null
                      ? const Text('Nenhuma posição capturada.',
                          style: TextStyle(color: Colors.grey))
                      : Text(
                          'Lat: ${_gpsLat!.toStringAsFixed(6)}\nLon: ${_gpsLon!.toStringAsFixed(6)}',
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 13),
                        ),
                ),
                const SizedBox(width: 12),
                _buscandoGps
                    ? const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : ElevatedButton.icon(
                        icon: const Icon(Icons.gps_fixed),
                        label: Text(_gpsLat != null ? 'Recapturar' : 'Capturar'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _gpsLat != null ? Colors.green : null),
                        onPressed: _capturarGps,
                      ),
              ],
            ),

            const SizedBox(height: 20),

            // ── 4. Seções de altura ──────────────────────────────────────
            if (_secoes.isNotEmpty) ...[
              _sectionTitle('4. Alturas por Seção'),
              const Text(
                'Meça a altura em cada ponto marcado ao longo da pilha.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _secoes.length,
                itemBuilder: (ctx, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          'Seção ${_secoes[i].posicao}\n${_secoes[i].distanciaMetros.toStringAsFixed(2)} m',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: TextFormField(
                          controller: _alturaControllers[i],
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Altura (m)',
                            border: const OutlineInputBorder(),
                            suffixText: 'm',
                            filled: true,
                            fillColor: (double.tryParse(_alturaControllers[i]
                                            .text
                                            .replaceAll(',', '.')) ??
                                        0) >
                                    0
                                ? (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.green.shade900.withAlpha(120)
                                    : Colors.green.shade50)
                                : null,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // ── Resumo de Volume ─────────────────────────────────────────
            if (_secoes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.brown.shade900.withAlpha(160)
                    : Colors.brown.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Volume Estéreo', style: TextStyle(color: Colors.brown.shade700, fontSize: 13)),
                          Text(
                            '${estereo.toStringAsFixed(2)} st',
                            style: TextStyle(fontSize: 15, color: Colors.brown.shade700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Slider do fator de empilhamento
                      Row(
                        children: [
                          const Text('fe:', style: TextStyle(fontSize: 12)),
                          Expanded(
                            child: Slider(
                              value: _fatorEmpilhamento,
                              min: 0.55,
                              max: 0.85,
                              divisions: 30,
                              label: _fatorEmpilhamento.toStringAsFixed(2),
                              activeColor: Colors.brown.shade600,
                              onChanged: (v) => setState(() => _fatorEmpilhamento = double.parse(v.toStringAsFixed(2))),
                            ),
                          ),
                          SizedBox(
                            width: 36,
                            child: Text(_fatorEmpilhamento.toStringAsFixed(2),
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      const Divider(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Volume Sólido',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          Text(
                            '${solido.toStringAsFixed(2)} m³',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: solido > 0 ? Colors.brown.shade800 : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── 5. Fotos ─────────────────────────────────────────────────
            _sectionTitle('5. Fotos'),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Câmera'),
                  onPressed: _tirarFoto,
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galeria'),
                  onPressed: _escolherDaGaleria,
                ),
              ],
            ),
            if (_fotos.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _fotos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(_fotos[i]),
                            width: 110, height: 110, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => _removerFoto(i),
                          child: Container(
                            decoration: const BoxDecoration(
                                color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close,
                                size: 18, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── 6. Observações ───────────────────────────────────────────
            _sectionTitle('6. Observações'),
            TextFormField(
              controller: _observacoesController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Ex: tora real 3,0 m, pilha em declive, etc.',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child:
            Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Text('$label: ', style: const TextStyle(color: Colors.grey, fontSize: 13)),
            Text(value, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geoforestv1/data/repositories/silvi_repository.dart';
import 'package:geoforestv1/models/silvi_model.dart';
import 'package:geoforestv1/pages/silvicultura/desenhar_area_silvi_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ColetaSilviPage extends StatefulWidget {
  final CentroideSilvi centroide;
  final OperacaoSilvi? initialData;

  const ColetaSilviPage({super.key, required this.centroide, this.initialData});

  @override
  State<ColetaSilviPage> createState() => _ColetaSilviPageState();
}

class _ColetaSilviPageState extends State<ColetaSilviPage> {
  final _formKey = GlobalKey<FormState>();
  final _repo = SilviRepository();
  final _imagePicker = ImagePicker();

  String? _tipoSelecionado;
  final _areaController = TextEditingController();
  final _obsController = TextEditingController();
  DateTime _data = DateTime.now();
  String? _nomeLider;
  double? _latitude;
  double? _longitude;
  bool _buscandoGps = false;
  bool _salvando = false;
  final List<String> _fotos = [];
  List<LatLng> _pontosArea = [];
  String? _areaGeoJson;

  bool get _editando => widget.initialData != null;

  // Sempre exibe todos os tipos — a OS só define o padrão pré-selecionado
  List<String> get _todosOsTipos =>
      OperacaoSilviTipo.values.map((t) => t.name).toList();

  @override
  void initState() {
    super.initState();
    final init = widget.initialData;
    if (init != null) {
      _tipoSelecionado = init.tipo;
      _areaController.text =
          init.areaAplicadaHa?.toString().replaceAll('.', ',') ?? '';
      _obsController.text = init.observacoes ?? '';
      _data = init.dataExecucao != null
          ? (DateTime.tryParse(init.dataExecucao!) ?? DateTime.now())
          : DateTime.now();
      _nomeLider = init.nomeLider;
      _latitude = init.latitude;
      _longitude = init.longitude;
      _fotos.addAll(init.fotos);
      _areaGeoJson = init.areaGeoJson;
    } else {
      _carregarLider();
      final planos = widget.centroide.operacoesPlanejadas;
      if (planos.isNotEmpty) _tipoSelecionado = planos.first.tipo;
    }
  }

  Future<void> _carregarLider() async {
    final prefs = await SharedPreferences.getInstance();
    final nome = prefs.getString('nome_lider') ?? '';
    if (mounted && nome.isNotEmpty) {
      setState(() => _nomeLider = nome);
    }
  }

  @override
  void dispose() {
    _areaController.dispose();
    _obsController.dispose();
    super.dispose();
  }

  Future<void> _capturarGps() async {
    setState(() => _buscandoGps = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permissão de GPS negada.')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
      if (mounted) {
        setState(() {
          _latitude = pos.latitude;
          _longitude = pos.longitude;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao obter GPS: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _buscandoGps = false);
    }
  }

  Future<void> _selecionarData() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) setState(() => _data = picked);
  }

  Future<void> _tirarFoto() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 60,
      maxWidth: 1024,
      maxHeight: 768,
    );
    if (picked != null && mounted) setState(() => _fotos.add(picked.path));
  }

  Future<void> _escolherDaGaleria() async {
    final picked = await _imagePicker.pickMultiImage(
      imageQuality: 60,
      maxWidth: 1024,
      maxHeight: 768,
    );
    if (picked.isNotEmpty && mounted) {
      setState(() => _fotos.addAll(picked.map((x) => x.path)));
    }
  }

  void _removerFoto(int index) => setState(() => _fotos.removeAt(index));

  Future<void> _abrirDesenhoArea() async {
    final resultado = await Navigator.push<ResultadoAreaSilvi>(
      context,
      MaterialPageRoute(
        builder: (_) => DesenharAreaSilviPage(
          centroide: widget.centroide,
          pontosIniciais: _pontosArea.isNotEmpty ? _pontosArea : null,
        ),
      ),
    );
    if (resultado != null && mounted) {
      setState(() {
        _pontosArea = resultado.pontos;
        _areaGeoJson = resultado.geoJson;
        // Preenche área aplicada automaticamente se estiver vazio
        if (_areaController.text.trim().isEmpty) {
          _areaController.text =
              resultado.areaHa.toStringAsFixed(2).replaceAll('.', ',');
        }
      });
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_tipoSelecionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione o tipo de operação.')),
      );
      return;
    }
    setState(() => _salvando = true);
    final init = widget.initialData;
    final op = OperacaoSilvi(
      id: init?.id,
      centroideId: init?.centroideId ?? widget.centroide.id,
      talhaoId: init?.talhaoId ?? widget.centroide.talhaoId,
      fazendaId: init?.fazendaId ?? widget.centroide.fazendaId,
      nomeFazenda: init?.nomeFazenda ?? widget.centroide.nomeFazenda,
      nomeTalhao: init?.nomeTalhao ?? widget.centroide.nomeTalhao,
      tipo: _tipoSelecionado!,
      areaAplicadaHa: _areaController.text.trim().isEmpty
          ? null
          : double.tryParse(_areaController.text.replaceAll(',', '.')),
      areaGeoJson: _areaGeoJson,
      dataExecucao: _data.toIso8601String(),
      status: 'concluida',
      observacoes: _obsController.text.trim().isEmpty
          ? null
          : _obsController.text.trim(),
      nomeLider: _nomeLider,
      fotos: List.from(_fotos),
      latitude: _latitude,
      longitude: _longitude,
      exportada: init?.exportada ?? false,
      isSynced: false,
      lastModified: DateTime.now().toIso8601String(),
    );

    if (_editando) {
      await _repo.atualizarOperacao(op);
    } else {
      await _repo.inserirOperacao(op);
    }

    if (!mounted) return;
    setState(() => _salvando = false);

    final tipo = OperacaoSilviTipo.fromString(op.tipo);
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.green.shade100,
                child: Icon(Icons.check_circle_outline,
                    color: Colors.green.shade700, size: 34),
              ),
              const SizedBox(height: 12),
              Text(
                _editando ? '${tipo.label} atualizado!' : '${tipo.label} registrado!',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              if (op.areaAplicadaHa != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Área aplicada: ${op.areaAplicadaHa!.toStringAsFixed(2)} ha',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              const SizedBox(height: 20),
              if (op.latitude != null) ...[
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context); // fecha sheet
                    // TODO: abrir mapa centrado no ponto quando tela de mapa silvi estiver pronta
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Localização: ${op.latitude!.toStringAsFixed(5)}, ${op.longitude!.toStringAsFixed(5)}',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Ver localização'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                onPressed: () {
                  Navigator.pop(context); // fecha sheet
                  Navigator.pop(context, true); // volta para lista
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  minimumSize: const Size(double.infinity, 44),
                ),
                child: const Text('Concluir'),
              ),
            ],
          ),
        ),
      ),
    );

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar Operação' : 'Registrar Operação'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Cabeçalho: Fazenda / Talhão / Área ──────────────────────
            Card(
              color: colorScheme.primaryContainer,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.domain_outlined,
                            size: 16,
                            color: colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Text('FAZENDA',
                            style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 1.0,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onPrimaryContainer
                                    .withValues(alpha: 0.7))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.centroide.nomeFazenda,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.forest_outlined,
                            size: 16,
                            color: colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.85)),
                        const SizedBox(width: 6),
                        Text(
                          'Talhão: ${widget.centroide.nomeTalhao}',
                          style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onPrimaryContainer),
                        ),
                        if (widget.centroide.areaTotalHa != null) ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: colorScheme.onPrimaryContainer
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${widget.centroide.areaTotalHa!.toStringAsFixed(1)} ha',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onPrimaryContainer),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Tipo de operação ─────────────────────────────────────────
            // Lista todos os tipos do enum; OS define apenas o padrão pré-selecionado
            DropdownButtonFormField<String>(
              initialValue: _tipoSelecionado,
              decoration: const InputDecoration(
                labelText: 'Tipo de Operação *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.eco_outlined),
              ),
              items: _todosOsTipos.map((t) {
                final tipo = OperacaoSilviTipo.fromString(t);
                final isFromOs = widget.centroide.operacoesPlanejadas
                    .any((o) => o.tipo == t);
                return DropdownMenuItem(
                  value: t,
                  child: Row(
                    children: [
                      Icon(tipo.icon, color: tipo.color, size: 18),
                      const SizedBox(width: 8),
                      Text(tipo.label),
                      if (isFromOs) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('OS',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() => _tipoSelecionado = v),
              validator: (v) =>
                  v == null ? 'Selecione o tipo de operação' : null,
            ),

            const SizedBox(height: 16),

            // ── Área aplicada ────────────────────────────────────────────
            TextFormField(
              controller: _areaController,
              decoration: const InputDecoration(
                labelText: 'Área Aplicada (ha)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.straighten_outlined),
                suffixText: 'ha',
                hintText: 'Opcional',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d,\.]'))
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final d = double.tryParse(v.replaceAll(',', '.'));
                if (d == null || d <= 0) return 'Área inválida';
                return null;
              },
            ),

            const SizedBox(height: 16),

            // ── Data da execução ─────────────────────────────────────────
            InkWell(
              onTap: _selecionarData,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Data da execução',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                  suffixIcon: Icon(Icons.edit_calendar_outlined),
                ),
                child: Text(DateFormat('dd/MM/yyyy').format(_data)),
              ),
            ),

            const SizedBox(height: 16),

            // ── GPS (opcional) ───────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: _buscandoGps
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.gps_fixed,
                            color: _latitude != null
                                ? Colors.green.shade700
                                : Colors.grey.shade600),
                    label: Text(
                      _buscandoGps
                          ? 'Obtendo GPS...'
                          : _latitude != null
                              ? '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}'
                              : 'Capturar GPS (opcional)',
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: _buscandoGps ? null : _capturarGps,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      alignment: Alignment.centerLeft,
                      side: BorderSide(
                        color: _latitude != null
                            ? Colors.green.shade400
                            : Colors.grey.shade400,
                      ),
                      foregroundColor: _latitude != null
                          ? Colors.green.shade700
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
                if (_latitude != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Remover GPS',
                    onPressed: () => setState(() {
                      _latitude = null;
                      _longitude = null;
                    }),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 16),

            // ── Delimitar área no mapa ───────────────────────────────────
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.draw_outlined,
                  color: _pontosArea.isNotEmpty
                      ? Colors.green.shade700
                      : Colors.grey.shade600),
              title: Text(
                _pontosArea.isNotEmpty
                    ? 'Área desenhada: ${(_pontosArea.length)} pontos'
                    : 'Delimitar área no mapa',
              ),
              subtitle: Text(
                _pontosArea.isNotEmpty
                    ? 'Toque para redesenhar'
                    : 'Desenhe o polígono da operação no mapa',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: _pontosArea.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      tooltip: 'Remover área',
                      onPressed: () => setState(() {
                        _pontosArea = [];
                        _areaGeoJson = null;
                      }),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _abrirDesenhoArea,
              shape: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: _pontosArea.isNotEmpty
                          ? Colors.green.shade400
                          : Colors.grey.shade400)),
            ),

            const SizedBox(height: 16),

            // ── Fotos ────────────────────────────────────────────────────
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Câmera'),
                  onPressed: _tirarFoto,
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library_outlined),
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
                            width: 110, height: 110, fit: BoxFit.cover,
                            cacheWidth: 220, cacheHeight: 220),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => _removerFoto(i),
                          child: Container(
                            decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle),
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

            const SizedBox(height: 16),

            // ── Observações ──────────────────────────────────────────────
            TextFormField(
              controller: _obsController,
              decoration: const InputDecoration(
                labelText: 'Observações',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 3,
            ),

            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _salvando ? null : _salvar,
              icon: _salvando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: Text(
                  _editando ? 'Salvar Alterações' : 'Registrar Operação'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

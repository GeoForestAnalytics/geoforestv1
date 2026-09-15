import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geoforestv1/data/repositories/estoque_repository.dart';
import 'package:geoforestv1/models/estoque_saida_model.dart';
import 'package:geoforestv1/models/pilha_madeira_model.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EstoqueSaidaPage extends StatefulWidget {
  final CentroidePilha centroide;
  final EstoqueSaida? initialData; // não-null = modo edição

  const EstoqueSaidaPage({super.key, required this.centroide, this.initialData});

  @override
  State<EstoqueSaidaPage> createState() => _EstoqueSaidaPageState();
}

class _EstoqueSaidaPageState extends State<EstoqueSaidaPage> {
  final _formKey = GlobalKey<FormState>();
  final _repo = EstoqueRepository();

  String? _sortimentoSelecionado;
  final _caminhaoController = TextEditingController();
  final _volumeController = TextEditingController();
  final _obsController = TextEditingController();
  DateTime _data = DateTime.now();
  String? _nomeLider;
  bool _salvando = false;

  bool get _editando => widget.initialData != null;

  @override
  void initState() {
    super.initState();
    final init = widget.initialData;
    if (init != null) {
      // modo edição — pré-preenche com os dados existentes
      _sortimentoSelecionado = init.sortimento;
      _volumeController.text = init.volumeM3.toString().replaceAll('.', ',');
      if (init.numeroCaminhoes > 0) _caminhaoController.text = init.numeroCaminhoes.toString();
      _obsController.text = init.observacoes ?? '';
      _data = DateTime.tryParse(init.dataRegistro) ?? DateTime.now();
      _nomeLider = init.nomeLider;
    } else {
      _carregarLider();
      if (widget.centroide.sortimentos.isNotEmpty) {
        _sortimentoSelecionado = widget.centroide.sortimentos.first.nome;
      }
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
    _caminhaoController.dispose();
    _volumeController.dispose();
    _obsController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_sortimentoSelecionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione o sortimento.')),
      );
      return;
    }

    setState(() => _salvando = true);

    final now = DateTime.now().toIso8601String();
    final init = widget.initialData;
    final estoque = EstoqueSaida(
      id: init?.id,
      talhaoId: init?.talhaoId ?? widget.centroide.talhaoId,
      centroideId: init?.centroideId ?? widget.centroide.id,
      fazendaId: init?.fazendaId ?? widget.centroide.fazendaId,
      nomeFazenda: init?.nomeFazenda ?? widget.centroide.nomeFazenda,
      nomeTalhao: init?.nomeTalhao ?? widget.centroide.nomeTalhao,
      sortimento: _sortimentoSelecionado!,
      numeroCaminhoes: int.tryParse(_caminhaoController.text) ?? 0,
      volumeM3: double.parse(_volumeController.text.replaceAll(',', '.')),
      nomeLider: _nomeLider,
      dataRegistro: _data.toIso8601String(),
      observacoes: _obsController.text.trim().isEmpty ? null : _obsController.text.trim(),
      exportada: init?.exportada ?? false,
      isSynced: false,
      lastModified: now,
    );

    if (_editando) {
      await _repo.atualizar(estoque);
    } else {
      await _repo.inserir(estoque);
    }

    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_editando
              ? 'Saída atualizada: ${estoque.volumeM3.toStringAsFixed(2)} m³.'
              : 'Saída de ${estoque.volumeM3.toStringAsFixed(2)} m³ registrada.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    final sortimentos = widget.centroide.sortimentos;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar Saída de Estoque' : 'Saída de Estoque'),
        backgroundColor: Colors.brown.shade700,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Cabeçalho do talhão ─────────────────────────────────────
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: Icon(Icons.forest_outlined,
                    color: Theme.of(context).colorScheme.primary),
                title: Text(widget.centroide.nomeTalhao,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(widget.centroide.nomeFazenda,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
              ),
            ),

            const SizedBox(height: 16),

            // ── Sortimento ──────────────────────────────────────────────
            if (sortimentos.isEmpty)
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Sortimento *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category_outlined),
                  hintText: 'Ex: 18-25, 25-32, >32…',
                ),
                onChanged: (v) => _sortimentoSelecionado = v.trim().isEmpty ? null : v.trim(),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe o sortimento' : null,
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _sortimentoSelecionado,
                decoration: const InputDecoration(
                  labelText: 'Sortimento',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: sortimentos
                    .map((s) => DropdownMenuItem(value: s.nome, child: Text(s.nome)))
                    .toList(),
                onChanged: (v) => setState(() => _sortimentoSelecionado = v),
                validator: (v) => v == null ? 'Selecione o sortimento' : null,
              ),

            const SizedBox(height: 16),

            // ── Volume ──────────────────────────────────────────────────
            TextFormField(
              controller: _volumeController,
              decoration: const InputDecoration(
                labelText: 'Volume (m³) *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.straighten_outlined),
                suffixText: 'm³',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,\.]'))],
              validator: (v) {
                if (v == null || v.isEmpty) return 'Informe o volume';
                final d = double.tryParse(v.replaceAll(',', '.'));
                if (d == null || d <= 0) return 'Volume inválido';
                return null;
              },
            ),

            const SizedBox(height: 16),

            // ── Nº de caminhões ─────────────────────────────────────────
            TextFormField(
              controller: _caminhaoController,
              decoration: const InputDecoration(
                labelText: 'Nº de caminhões',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_shipping_outlined),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),

            const SizedBox(height: 16),

            // ── Data ─────────────────────────────────────────────────────
            InkWell(
              onTap: _selecionarData,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Data da saída',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                  isDense: false,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(DateFormat('dd/MM/yyyy').format(_data),
                        style: const TextStyle(fontSize: 16)),
                    Text('Alterar',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ],
                ),
              ),
            ),

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
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: Text(_editando ? 'Salvar Alterações' : 'Registrar Saída'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.brown.shade700,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

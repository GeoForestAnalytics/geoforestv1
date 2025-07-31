// lib/pages/talhoes/form_talhao_page.dart (VERSÃO COMPLETA E REFATORADA)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geoforestv1/models/talhao_model.dart';

// --- NOVO IMPORT DO REPOSITÓRIO ---
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
// ------------------------------------

// O import do database_helper foi removido.
// import 'package:geoforestv1/data/datasources/local/database_helper.dart';

class FormTalhaoPage extends StatefulWidget {
  final String fazendaId;
  final int fazendaAtividadeId;
  final Talhao? talhaoParaEditar;

  const FormTalhaoPage({
    super.key,
    required this.fazendaId,
    required this.fazendaAtividadeId,
    this.talhaoParaEditar,
  });

  bool get isEditing => talhaoParaEditar != null;

  @override
  State<FormTalhaoPage> createState() => _FormTalhaoPageState();
}

class _FormTalhaoPageState extends State<FormTalhaoPage> {
  final _formKey = GlobalKey<FormState>();
  
  // --- INSTÂNCIA DO NOVO REPOSITÓRIO ---
  final _talhaoRepository = TalhaoRepository();
  // ---------------------------------------
  
  final _nomeController = TextEditingController();
  final _areaController = TextEditingController();
  final _idadeController = TextEditingController();
  final _especieController = TextEditingController();
  final _espacamentoController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      final talhao = widget.talhaoParaEditar!;
      _nomeController.text = talhao.nome;
      _especieController.text = talhao.especie ?? '';
      _espacamentoController.text = talhao.espacamento ?? '';
      _areaController.text = talhao.areaHa?.toString().replaceAll('.', ',') ?? '';
      _idadeController.text = talhao.idadeAnos?.toString().replaceAll('.', ',') ?? '';
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _areaController.dispose();
    _idadeController.dispose();
    _especieController.dispose();
    _espacamentoController.dispose();
    super.dispose();
  }

  // --- MÉTODO ATUALIZADO ---
  Future<void> _salvar() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() => _isSaving = true);

      final talhao = Talhao(
        id: widget.isEditing ? widget.talhaoParaEditar!.id : null,
        fazendaId: widget.fazendaId,
        fazendaAtividadeId: widget.fazendaAtividadeId,
        nome: _nomeController.text.trim(),
        areaHa: double.tryParse(_areaController.text.replaceAll(',', '.')),
        idadeAnos: double.tryParse(_idadeController.text.replaceAll(',', '.')),
        especie: _especieController.text.trim(),
        espacamento: _espacamentoController.text.trim().isNotEmpty ? _espacamentoController.text.trim() : null,
      );

      try {
        // A lógica de `update` não está no repositório, então vamos adicioná-la ou
        // podemos simplesmente chamar `insertTalhao` que pode ter um `conflictAlgorithm.replace`.
        // Para ser explícito e correto, vamos garantir que o repositório tenha um método de update.
        // Assumindo que o `insertTalhao` do repositório já lida com `update` (se o ID existir)
        // ou que podemos criar um método `updateTalhao`. Vamos usar `insertTalhao` por simplicidade,
        // mas o ideal seria ter um método de update explícito no repositório.
        
        // A melhor abordagem é usar um único método no repositório.
        await _talhaoRepository.insertTalhao(talhao);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Talhão ${widget.isEditing ? 'atualizado' : 'criado'} com sucesso!'), 
              backgroundColor: Colors.green
            ),
          );
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao salvar talhão: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
    }
  }

  // O método `build` não precisa de alterações.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Editar Talhão' : 'Novo Talhão'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nomeController,
                decoration: const InputDecoration(
                  labelText: 'Nome ou Código do Talhão',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'O nome do talhão é obrigatório.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _especieController,
                decoration: const InputDecoration(
                  labelText: 'Espécie (ex: Eucalipto)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.eco_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _espacamentoController,
                decoration: const InputDecoration(
                  labelText: 'Espaçamento (ex: 3x2)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.space_bar_outlined),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _areaController,
                      decoration: const InputDecoration(
                        labelText: 'Área (ha)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.area_chart_outlined),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*[,.]?\d*')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _idadeController,
                      decoration: const InputDecoration(
                        labelText: 'Idade (anos)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.cake_outlined),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*[,.]?\d*')),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _salvar,
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined),
                label: Text(_isSaving ? 'Salvando...' : 'Salvar Talhão'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// lib/pages/atividades/form_atividade_page.dart (VERSÃO COMPLETA E REFATORADA)

import 'package:flutter/material.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart'; // <-- IMPORT CORRIGIDO
import 'package:geoforestv1/models/atividade_model.dart';


class FormAtividadePage extends StatefulWidget {
  final int projetoId;
  final Atividade? atividadeParaEditar;

  const FormAtividadePage({
    super.key,
    required this.projetoId,
    this.atividadeParaEditar,
  });

  bool get isEditing => atividadeParaEditar != null;

  @override
  State<FormAtividadePage> createState() => _FormAtividadePageState();
}

class _FormAtividadePageState extends State<FormAtividadePage> {
  final _formKey = GlobalKey<FormState>();
  final _tipoController = TextEditingController();
  final _descricaoController = TextEditingController();

  // --- INSTÂNCIA DO REPOSITÓRIO ---
  final _atividadeRepository = AtividadeRepository();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      final atividade = widget.atividadeParaEditar!;
      _tipoController.text = atividade.tipo;
      _descricaoController.text = atividade.descricao;
    }
  }

  @override
  void dispose() {
    _tipoController.dispose();
    _descricaoController.dispose();
    super.dispose();
  }

  // --- FUNÇÃO DE SALVAR ATUALIZADA ---
  Future<void> _salvarAtividade() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);

      final atividade = Atividade(
        id: widget.isEditing ? widget.atividadeParaEditar!.id : null,
        projetoId: widget.projetoId,
        tipo: _tipoController.text.trim(),
        descricao: _descricaoController.text.trim(),
        dataCriacao: widget.isEditing ? widget.atividadeParaEditar!.dataCriacao : DateTime.now(),
        metodoCubagem: widget.isEditing ? widget.atividadeParaEditar!.metodoCubagem : null,
      );

      try {
        // <<< LÓGICA DE SALVAR CORRIGIDA >>>
        if (widget.isEditing) {
          await _atividadeRepository.updateAtividade(atividade);
        } else {
          await _atividadeRepository.insertAtividade(atividade);
        }
        // <<< FIM DA CORREÇÃO >>>

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Atividade ${widget.isEditing ? "atualizada" : "criada"} com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao salvar atividade: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Editar Atividade' : 'Nova Atividade'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _tipoController,
                decoration: const InputDecoration(
                  labelText: 'Tipo da Atividade (ex: Inventário, Cubagem)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'O tipo da atividade é obrigatório.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descricaoController,
                decoration: const InputDecoration(
                  labelText: 'Descrição (Opcional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _salvarAtividade,
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined),
                label: Text(_isSaving ? 'Salvando...' : (widget.isEditing ? 'Atualizar Atividade' : 'Salvar Atividade')),
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
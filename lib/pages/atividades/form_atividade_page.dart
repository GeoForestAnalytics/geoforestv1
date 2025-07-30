// lib/pages/atividades/form_atividade_page.dart (VERSÃO COM SUPORTE PARA EDIÇÃO)

import 'package:flutter/material.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/atividade_model.dart';

class FormAtividadePage extends StatefulWidget {
  final int projetoId;
  // <<< MUDANÇA 1 >>> Adiciona o parâmetro opcional para edição
  final Atividade? atividadeParaEditar;

  const FormAtividadePage({
    super.key,
    required this.projetoId,
    this.atividadeParaEditar,
  });

  // <<< MUDANÇA 2 >>> Adiciona um getter para facilitar a verificação do modo de edição
  bool get isEditing => atividadeParaEditar != null;

  @override
  State<FormAtividadePage> createState() => _FormAtividadePageState();
}

class _FormAtividadePageState extends State<FormAtividadePage> {
  final _formKey = GlobalKey<FormState>();
  final _tipoController = TextEditingController();
  final _descricaoController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // <<< MUDANÇA 3 >>> Lógica para pré-preencher o formulário no modo de edição
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

  // <<< MUDANÇA 4 >>> Função de salvar agora lida com criação e edição
  Future<void> _salvarAtividade() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);

      // Constrói o objeto Atividade. Se estiver editando, mantém o ID e a data de criação originais.
      final atividade = Atividade(
        id: widget.isEditing ? widget.atividadeParaEditar!.id : null,
        projetoId: widget.projetoId,
        tipo: _tipoController.text.trim(),
        descricao: _descricaoController.text.trim(),
        dataCriacao: widget.isEditing ? widget.atividadeParaEditar!.dataCriacao : DateTime.now(),
        // Preserva o método de cubagem se já existir
        metodoCubagem: widget.isEditing ? widget.atividadeParaEditar!.metodoCubagem : null,
      );

      try {
        final dbHelper = DatabaseHelper.instance;
        final db = await dbHelper.database; // Obtém a instância do banco
        
        if (widget.isEditing) {
          // Se estiver editando, executa um UPDATE
          await db.update(
            'atividades',
            atividade.toMap(),
            where: 'id = ?',
            whereArgs: [atividade.id],
          );
        } else {
          // Se não, executa um INSERT
          await db.insert('atividades', atividade.toMap());
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Atividade ${widget.isEditing ? "atualizada" : "criada"} com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true); // Retorna 'true' para recarregar a lista
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
      // <<< MUDANÇA 5 >>> O título da página e o texto do botão agora são dinâmicos
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
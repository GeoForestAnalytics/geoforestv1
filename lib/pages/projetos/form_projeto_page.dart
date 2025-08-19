// lib/pages/projetos/form_projeto_page.dart (VERSÃO CORRIGIDA E COMPLETA)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// --- NOVOS IMPORTS ---
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/providers/license_provider.dart';
// ---------------------

class FormProjetoPage extends StatefulWidget {
  final Projeto? projetoParaEditar;

  const FormProjetoPage({
    super.key,
    this.projetoParaEditar,
  });

  bool get isEditing => projetoParaEditar != null;

  @override
  State<FormProjetoPage> createState() => _FormProjetoPageState();
}

class _FormProjetoPageState extends State<FormProjetoPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _empresaController = TextEditingController();
  final _responsavelController = TextEditingController();

  // --- INSTÂNCIA DO REPOSITÓRIO ---
  final _projetoRepository = ProjetoRepository();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      final projeto = widget.projetoParaEditar!;
      _nomeController.text = projeto.nome;
      _empresaController.text = projeto.empresa;
      _responsavelController.text = projeto.responsavel;
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _empresaController.dispose();
    _responsavelController.dispose();
    super.dispose();
  }
  
  // --- FUNÇÃO DE SALVAR ATUALIZADA ---
  Future<void> _salvarProjeto() async {
  if (_formKey.currentState!.validate()) {
    setState(() => _isSaving = true);
    
    try {
      final licenseProvider = context.read<LicenseProvider>();
      if (licenseProvider.licenseData == null) {
        throw Exception("Não foi possível identificar a licença do usuário.");
      }
      final licenseId = licenseProvider.licenseData!.id;

      final projeto = Projeto(
        id: widget.isEditing ? widget.projetoParaEditar!.id : null,
        licenseId: widget.isEditing ? widget.projetoParaEditar!.licenseId : licenseId,
        nome: _nomeController.text.trim(),
        empresa: _empresaController.text.trim(),
        responsavel: _responsavelController.text.trim(),
        dataCriacao: widget.isEditing ? widget.projetoParaEditar!.dataCriacao : DateTime.now(),
        status: widget.isEditing ? widget.projetoParaEditar!.status : 'ativo',
        delegadoPorLicenseId: widget.isEditing ? widget.projetoParaEditar!.delegadoPorLicenseId : null,
      );

      // <<< LÓGICA DE SALVAR CORRIGIDA >>>
      // Agora, ele verifica se está editando e chama o método correto.
      if (widget.isEditing) {
        await _projetoRepository.updateProjeto(projeto);
      } else {
        await _projetoRepository.insertProjeto(projeto);
      }
      // <<< FIM DA CORREÇÃO >>>

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Projeto ${widget.isEditing ? "atualizado" : "criado"} com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Erro ao salvar o projeto: $e';
        // Melhora a mensagem de erro para o usuário
        if (e.toString().contains('UNIQUE constraint failed')) {
            errorMessage = 'Erro: Já existe um projeto com este nome ou ID.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
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
        title: Text(widget.isEditing ? 'Editar Projeto' : 'Novo Projeto'),
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
                  labelText: 'Nome do Projeto',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'O nome do projeto é obrigatório.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _empresaController,
                decoration: const InputDecoration(
                  labelText: 'Empresa Cliente',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'O nome da empresa é obrigatório.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _responsavelController,
                decoration: const InputDecoration(
                  labelText: 'Responsável Técnico',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                 validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'O nome do responsável é obrigatório.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _salvarProjeto,
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined),
                label: Text(_isSaving ? 'Salvando...' : (widget.isEditing ? 'Atualizar Projeto' : 'Salvar Projeto')),
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
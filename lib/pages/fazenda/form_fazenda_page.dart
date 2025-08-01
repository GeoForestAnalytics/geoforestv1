// lib/pages/fazenda/form_fazenda_page.dart (VERSÃO CORRIGIDA)

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:sqflite/sqflite.dart';

// <<< 1. IMPORTE O REPOSITÓRIO E REMOVA O DATABASE_HELPER >>>
import 'package:geoforestv1/data/repositories/fazenda_repository.dart';
// import 'package:geoforestv1/data/datasources/local/database_helper.dart'; // REMOVA ESTA LINHA

class FormFazendaPage extends StatefulWidget {
  final int atividadeId;
  final Fazenda? fazendaParaEditar; 

  const FormFazendaPage({
    super.key,
    required this.atividadeId,
    this.fazendaParaEditar, 
  });

  bool get isEditing => fazendaParaEditar != null;

  @override
  State<FormFazendaPage> createState() => _FormFazendaPageState();
}

class _FormFazendaPageState extends State<FormFazendaPage> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _nomeController = TextEditingController();
  final _municipioController = TextEditingController();
  final _estadoController = TextEditingController();
  
  // <<< 2. INSTANCIE O REPOSITÓRIO >>>
  final _fazendaRepository = FazendaRepository();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      final fazenda = widget.fazendaParaEditar!;
      _idController.text = fazenda.id;
      _nomeController.text = fazenda.nome;
      _municipioController.text = fazenda.municipio;
      _estadoController.text = fazenda.estado;
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _nomeController.dispose();
    _municipioController.dispose();
    _estadoController.dispose();
    super.dispose();
  }

  // <<< 3. SUBSTITUA COMPLETAMENTE O MÉTODO _salvar >>>
  Future<void> _salvar() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() => _isSaving = true);

      final fazenda = Fazenda(
        // O ID não pode ser editado, então pegamos do controlador.
        // A atividadeId vem do widget.
        id: _idController.text.trim(),
        atividadeId: widget.atividadeId,
        nome: _nomeController.text.trim(),
        municipio: _municipioController.text.trim(),
        estado: _estadoController.text.trim().toUpperCase(),
      );

      try {
        if (widget.isEditing) {
          // No modo de edição, usamos o novo método de update
          await _fazendaRepository.updateFazenda(fazenda);
        } else {
          // No modo de criação, usamos o método de insert
          await _fazendaRepository.insertFazenda(fazenda);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fazenda ${widget.isEditing ? 'atualizada' : 'criada'} com sucesso!'),
              backgroundColor: Colors.green
            ),
          );
          Navigator.of(context).pop(true);
        }
      } on DatabaseException catch (e) {
        if (e.isUniqueConstraintError() && mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: O ID "${fazenda.id}" já existe para esta atividade.'), backgroundColor: Colors.red),
          );
        } else if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro de banco de dados ao salvar: $e'), backgroundColor: Colors.red),
          );
        }
      } 
      catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ocorreu um erro inesperado: $e'), backgroundColor: Colors.red),
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
    // O método build permanece o mesmo, não precisa de alterações.
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Editar Fazenda' : 'Nova Fazenda'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _idController,
                // O ID da fazenda (chave primária) não deve ser editável.
                enabled: !widget.isEditing,
                style: TextStyle(
                  color: widget.isEditing ? Colors.grey.shade600 : null,
                ),
                decoration: InputDecoration(
                  labelText: 'ID da Fazenda (Código do Cliente)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  filled: widget.isEditing,
                  fillColor: widget.isEditing ? Colors.grey.shade200 : null,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'O ID da fazenda é obrigatório.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nomeController,
                decoration: const InputDecoration(
                  labelText: 'Nome da Fazenda',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.maps_home_work_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'O nome da fazenda é obrigatório.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _municipioController,
                decoration: const InputDecoration(
                  labelText: 'Município',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_city_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'O município é obrigatório.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _estadoController,
                maxLength: 2,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Estado (UF)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.public_outlined),
                  counterText: "",
                ),
                 validator: (value) {
                  if (value == null || value.trim().length != 2) {
                    return 'Informe a sigla do estado (ex: SP).';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _salvar,
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined),
                label: Text(_isSaving ? 'Salvando...' : 'Salvar Fazenda'),
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
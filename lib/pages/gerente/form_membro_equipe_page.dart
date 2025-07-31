// lib/pages/gerente/form_membro_equipe_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

class FormMembroEquipePage extends StatefulWidget {
  const FormMembroEquipePage({super.key});

  @override
  State<FormMembroEquipePage> createState() => _FormMembroEquipePageState();
}

class _FormMembroEquipePageState extends State<FormMembroEquipePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String _cargoSelecionado = 'equipe';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _salvarNovoMembro() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // --- VERIFIQUE ESTA LINHA ---
      // Garanta que a região é a mesma da sua Cloud Function.
      final functions = FirebaseFunctions.instanceFor(region: 'southamerica-east1'); 
      // --------------------------

      final callable = functions.httpsCallable('adicionarMembroEquipe');
      
      final result = await callable.call(<String, dynamic>{
        'email': _emailController.text.trim(),
        'password': _passwordController.text,
        'name': _nameController.text.trim(),
        'cargo': _cargoSelecionado,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.data['message']), backgroundColor: Colors.green)
        );
        Navigator.pop(context);
      }

    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        // Agora o erro será mais descritivo
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro [${e.code}]: ${e.message}"), backgroundColor: Colors.red)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ocorreu um erro inesperado: $e"), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adicionar Membro'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nome Completo', border: OutlineInputBorder()),
                validator: (v) => v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Campo obrigatório';
                  if (!v.contains('@')) return 'Email inválido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Senha Temporária', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.length < 6) ? 'A senha deve ter no mínimo 6 caracteres' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _cargoSelecionado,
                items: const [
                  DropdownMenuItem(value: 'equipe', child: Text('Equipe (Coletor)')),
                  DropdownMenuItem(value: 'gerente', child: Text('Gerente (Administrador)')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _cargoSelecionado = value);
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Cargo',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _salvarNovoMembro,
                icon: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.person_add_alt_1),
                label: Text(_isLoading ? 'Adicionando...' : 'Adicionar Membro'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
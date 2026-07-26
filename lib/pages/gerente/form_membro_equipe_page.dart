// lib/pages/gerente/form_membro_equipe_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:provider/provider.dart';

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
  String _moduloSelecionado = 'inventario';
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
      final functions = FirebaseFunctions.instanceFor(region: 'southamerica-east1');
      final callable = functions.httpsCallable('adicionarMembroEquipe');

      final result = await callable.call(<String, dynamic>{
        'email': _emailController.text.trim(),
        'password': _passwordController.text,
        'name': _nameController.text.trim(),
        'cargo': _cargoSelecionado,
        'modulo': _cargoSelecionado == 'gerente' ? _moduloSelecionado : null,
      });

      // Se o novo membro é gerente, garante que modulo está salvo no Firestore.
      // A Cloud Function precisa gravar o campo; este bloco é um fallback direto
      // caso a versão da função ainda não suporte 'modulo'.
      if (_cargoSelecionado == 'gerente' && mounted) {
        final licenseId = context.read<LicenseProvider>().licenseData?.id;
        final newUid = result.data['uid'] as String?;
        if (licenseId != null && newUid != null) {
          await FirebaseFirestore.instance
              .collection('clientes')
              .doc(licenseId)
              .update({'usuariosPermitidos.$newUid.modulo': _moduloSelecionado});
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.data['message']), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro [${e.code}]: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ocorreu um erro inesperado: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                  DropdownMenuItem(value: 'gerente', child: Text('Gerente')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _cargoSelecionado = value);
                },
                decoration: const InputDecoration(
                  labelText: 'Cargo',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_cargoSelecionado == 'gerente') ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _moduloSelecionado,
                  items: const [
                    DropdownMenuItem(value: 'inventario', child: Text('Inventário / Cubagem')),
                    DropdownMenuItem(value: 'colheita', child: Text('Colheita')),
                    DropdownMenuItem(value: 'silvicultura', child: Text('Silvicultura')),
                    DropdownMenuItem(value: 'todos', child: Text('Geral (todos os módulos)')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _moduloSelecionado = value);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Módulo do gerente',
                    helperText: 'Define quais dashboards este gerente acessa',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
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
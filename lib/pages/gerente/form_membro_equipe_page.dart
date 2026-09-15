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

      final gerenteModulo = context.read<LicenseProvider>().licenseData?.modulo ?? 'inventario';
      // Módulo sempre travado ao do gerente quando não é 'todos'
      final moduloEfetivo = gerenteModulo == 'todos' ? _moduloSelecionado : gerenteModulo;
      // Cargo pode ser escolhido por qualquer gerente (restrito ou não), mas validado no servidor
      final cargoEfetivo = _cargoSelecionado;

      final result = await callable.call(<String, dynamic>{
        'email': _emailController.text.trim(),
        'password': _passwordController.text,
        'name': _nameController.text.trim(),
        'cargo': cargoEfetivo,
        'modulo': moduloEfetivo,
      });

      // Fallback direto: garante que modulo está salvo no Firestore para qualquer cargo
      if (mounted) {
        final licenseId = context.read<LicenseProvider>().licenseData?.id;
        final newUid = result.data['uid'] as String?;
        if (licenseId != null && newUid != null) {
          await FirebaseFirestore.instance
              .collection('clientes')
              .doc(licenseId)
              .update({
            'usuariosPermitidos.$newUid.modulo': moduloEfetivo,
            'usuariosPermitidos.$newUid.cargo': cargoEfetivo,
          });
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


  static const _moduloLabels = {
    'inventario': 'Inventário / Cubagem',
    'colheita': 'Colheita',
    'silvicultura': 'Silvicultura',
    'todos': 'Geral (todos os módulos)',
  };

  @override
  Widget build(BuildContext context) {
    final gerenteModulo =
        context.watch<LicenseProvider>().licenseData?.modulo ?? 'inventario';
    final gerenteTodos = gerenteModulo == 'todos';

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

              // Qualquer gerente pode escolher o cargo
              DropdownButtonFormField<String>(
                initialValue: _cargoSelecionado,
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
              const SizedBox(height: 16),

              if (gerenteTodos) ...[
                // Gerente "todos" → escolhe o módulo livremente
                DropdownButtonFormField<String>(
                  initialValue: _moduloSelecionado,
                  items: _moduloLabels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _moduloSelecionado = value);
                  },
                  decoration: InputDecoration(
                    labelText: _cargoSelecionado == 'gerente' ? 'Módulo do gerente' : 'Módulo do coletor',
                    helperText: 'Define quais atividades este membro acessa',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ] else ...[
                // Gerente restrito → módulo travado ao próprio módulo
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Módulo: ${_moduloLabels[gerenteModulo] ?? gerenteModulo}  ·  '
                          '${_cargoSelecionado == 'gerente' ? 'Gerente do mesmo módulo que você' : 'Coletor do mesmo módulo'}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
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
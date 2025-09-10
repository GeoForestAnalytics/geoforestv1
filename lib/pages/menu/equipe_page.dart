// lib/pages/menu/equipe_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:geoforestv1/providers/team_provider.dart';

class EquipePage extends StatefulWidget {
  const EquipePage({super.key});

  @override
  State<EquipePage> createState() => _EquipePageState();
}

class _EquipePageState extends State<EquipePage> {
  final _formKey = GlobalKey<FormState>();
  final _liderController = TextEditingController();
  final _ajudantesController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Carrega os nomes usando o Provider assim que a tela é construída
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final teamProvider = Provider.of<TeamProvider>(context, listen: false);
      _liderController.text = teamProvider.lider ?? '';
      _ajudantesController.text = teamProvider.ajudantes ?? '';
    });
  }

  void _continuar() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      // <<< CORREÇÃO: Usa o provider para salvar os dados
      final teamProvider = Provider.of<TeamProvider>(context, listen: false);
      await teamProvider.setTeam(
        _liderController.text,
        _ajudantesController.text,
      );

      if (mounted) {
        context.go('/home');
      }
    }
  }

  // O resto do build da tela permanece o mesmo...
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Identificação da Equipe')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.groups_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Antes de começar, por favor, identifique a equipe de hoje.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _liderController,
                decoration: const InputDecoration(
                  labelText: 'Nome do Líder da Equipe',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value!.trim().isEmpty
                    ? 'O nome do líder é obrigatório'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ajudantesController,
                decoration: const InputDecoration(
                  labelText: 'Nomes dos Ajudantes',
                  hintText: 'Ex: João, Maria, Pedro',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _continuar,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(color: Colors.white))
                    : const Text('Continuar para o Menu'),
              )
            ],
          ),
        ),
      ),
    );
  }
}
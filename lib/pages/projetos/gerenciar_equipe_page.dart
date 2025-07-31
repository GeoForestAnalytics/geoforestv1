// lib/pages/projetos/gerenciar_equipe_page.dart (PÁGINA NOVA)

import 'package:flutter/material.dart';

class GerenciarEquipePage extends StatefulWidget {
  const GerenciarEquipePage({super.key});

  @override
  State<GerenciarEquipePage> createState() => _GerenciarEquipePageState();
}

class _GerenciarEquipePageState extends State<GerenciarEquipePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Equipe'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Esta tela permitirá que o gerente adicione, visualize e remova membros da equipe de sua licença.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: Implementar a lógica para adicionar um novo membro
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Funcionalidade de adicionar membro a ser implementada.'))
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Novo Membro'),
      ),
    );
  }
}
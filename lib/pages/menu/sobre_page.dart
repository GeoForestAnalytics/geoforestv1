// lib/pages/sobre_page.dart

import 'package:flutter/material.dart';

class SobrePage extends StatelessWidget {
  const SobrePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Usamos o 'Theme.of(context)' para acessar as cores e estilos do seu tema.
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        // O título da página.
        title: const Text('Sobre o Aplicativo'),
      ),
      body: Padding(
        // Adiciona um espaçamento em todas as bordas da tela.
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            // Centraliza o conteúdo verticalmente.
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Um ícone para dar um toque visual, usando a cor primária do seu tema.
              Icon(
                Icons.forest_outlined,
                size: 80.0,
                color: theme.colorScheme.primary,
              ),

              const SizedBox(height: 24.0),

              // O título do aplicativo.
              Text(
                'Geo Forest Analytics',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16.0),

              // A descrição que você pediu.
              const Text(
                'Geo Forest Analytics é um coletor florestal.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18.0,
                  height: 1.5, // Aumenta o espaçamento entre as linhas para melhor legibilidade.
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
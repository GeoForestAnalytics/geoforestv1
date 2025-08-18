// lib/pages/menu/splash_page.dart

import 'package:flutter/material.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/fundo_textura.png'), // Caminho da sua imagem de textura
            fit: BoxFit.cover, // Faz a imagem cobrir toda a tela
          ),
        ),
        child: const Center(
          child: Image(
            image: AssetImage('assets/images/logo_oficial.png'),
            width: 280,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
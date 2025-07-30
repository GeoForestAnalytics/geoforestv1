// lib/pages/menu/splash_page.dart (VERSÃO CORRIGIDA E SIMPLIFICADA)

import 'package:flutter/material.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    // A Splash Page agora é "burra". Ela apenas exibe a imagem e não faz mais nada.
    // A lógica de navegação foi movida para o AppInitializer no main.dart.
    return const Scaffold(
      backgroundColor: Color.fromARGB(255, 243, 243, 244),
      body: Center(
        child: Image(
          image: AssetImage('assets/images/icon5.png'),
          width: 280,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

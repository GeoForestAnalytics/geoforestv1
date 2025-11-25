import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:audioplayers/audioplayers.dart';
import 'login_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _iniciarSistema();
  }

  Future<void> _iniciarSistema() async {
    try {
      await _audioPlayer.setVolume(0.6);
      // Toca o som (verifique se intro.mp3 está na pasta assets/sounds)
      await _audioPlayer.play(AssetSource('sounds/intro.mp3'));
    } catch (e) {
      print("Erro ao tocar som: $e");
    }

    // Tempo total da animação antes de trocar de tela
    await Future.delayed(const Duration(seconds: 5));

    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(seconds: 2), // Transição lenta e elegante
          pageBuilder: (_, __, ___) => const LoginPage(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cores do seu tema
    final Color azulMarinho = const Color.fromARGB(255, 229, 222, 164);
    final Color azulPreto = const Color.fromARGB(255, 1, 33, 92);
    final Color brilhoAzul = const Color.fromARGB(223, 247, 245, 227); // Azul Neon para o brilho

    return Scaffold(
      // 1. FUNDO GRADIENTE AZUL MARINHO (Cobre tudo, sem cortes)
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.5,
            colors: [
              azulMarinho, // Centro mais azul
              azulPreto,   // Bordas pretas (dá profundidade)
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),

            // 2. O LOGO COM EFEITO DE ENERGIA/BRILHO NA BORDA
            Container(
              width: 280, // Tamanho controlado para não ficar gigante
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Sombras que criam o efeito de "Glow"
                boxShadow: [
                  BoxShadow(
                    color: brilhoAzul.withOpacity(0.6),
                    blurRadius: 40, // Borrão grande para fazer o brilho
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Image.asset(
                'assets/images/icon_azul.png', // SEU LOGO TRANSPARENTE
                fit: BoxFit.contain,
              ),
            )
            .animate(onPlay: (controller) => controller.repeat(reverse: true)) // Animação em Loop (Vai e Volta)
            .scale(
              begin: const Offset(1.0, 1.0), 
              end: const Offset(1.05, 1.05), // Pulsa de tamanho levemente
              duration: 2.seconds,
              curve: Curves.easeInOut,
            )
            .boxShadow(
              // Anima a intensidade do brilho (Pulsa a luz)
              begin: BoxShadow(color: brilhoAzul.withOpacity(0.5), blurRadius: 90, spreadRadius: 0),
              end: BoxShadow(color: brilhoAzul.withOpacity(0.9), blurRadius: 90, spreadRadius: 0),
              duration: 2.seconds,
            ),

            const Spacer(),

            // 3. BARRA DE CARREGAMENTO FUTURISTA
            Column(
              children: [
                Text(
                  "INICIANDO SISTEMA...",
                  style: TextStyle(
                    color: brilhoAzul, // Texto cor de "Holograma"
                    letterSpacing: 4,
                    fontSize: 12,
                    fontFamily: 'Courier', // Fonte estilo computador/código
                    fontWeight: FontWeight.bold
                  ),
                )
                .animate()
                .fadeIn(delay: 500.ms)
                .shimmer(duration: 2.seconds, color: Colors.white), // Texto brilhando
                
                const SizedBox(height: 20),
                
                // Barrinha fina e elegante
                SizedBox(
                  width: 200,
                  child: LinearProgressIndicator(
                    backgroundColor: azulMarinho.withOpacity(0.5),
                    color: brilhoAzul,
                    minHeight: 1,
                  ),
                ).animate().fadeIn(delay: 1.seconds),
              ],
            ),
            
            const SizedBox(height: 50), // Espaço final
          ],
        ),
      ),
    );
  }
}
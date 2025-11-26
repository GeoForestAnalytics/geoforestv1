import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:go_router/go_router.dart'; // ✅ IMPORT NECESSÁRIO

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
      // Verifique se o arquivo existe em pubspec.yaml
      await _audioPlayer.play(AssetSource('sounds/intro.mp3')); 
    } catch (e) {
      // Apenas printa o erro de som e continua, não trava o app
      debugPrint("Erro ao tocar som (não fatal): $e");
    }

    // Tempo total da animação antes de trocar de tela
    await Future.delayed(const Duration(seconds: 5));

    if (mounted) {
      // ✅ CORREÇÃO AQUI:
      // Usamos context.go('/login') em vez de Navigator.pushReplacement.
      // O AppRouter (redirect) vai decidir se ele realmente vai pro login
      // ou se já está logado e vai para a home.
      context.go('/login');
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
    final Color brilhoAzul = const Color.fromARGB(223, 247, 245, 227); 

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.5,
            colors: [
              azulMarinho, 
              azulPreto,   
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),

            // 2. O LOGO COM EFEITO DE ENERGIA/BRILHO NA BORDA
            Container(
              width: 280, 
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: brilhoAzul.withOpacity(0.6),
                    blurRadius: 40, 
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Image.asset(
                'assets/images/icon_azul.png', 
                fit: BoxFit.contain,
              ),
            )
            .animate(onPlay: (controller) => controller.repeat(reverse: true)) 
            .scale(
              begin: const Offset(1.0, 1.0), 
              end: const Offset(1.05, 1.05), 
              duration: 2.seconds,
              curve: Curves.easeInOut,
            )
            .boxShadow(
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
                    color: brilhoAzul, 
                    letterSpacing: 4,
                    fontSize: 12,
                    fontFamily: 'Courier', 
                    fontWeight: FontWeight.bold
                  ),
                )
                .animate()
                .fadeIn(delay: 500.ms)
                .shimmer(duration: 2.seconds, color: Colors.white), 
                
                const SizedBox(height: 20),
                
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
            
            const SizedBox(height: 50), 
          ],
        ),
      ),
    );
  }
}
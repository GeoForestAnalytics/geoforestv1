import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

class MenuCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int index;

  const MenuCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.index = 0,
  });

  @override
  State<MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<MenuCard> {
  final AudioPlayer _audioPlayer = AudioPlayer();

  Future<void> _handleTap() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setVolume(0.3);
      await _audioPlayer.play(AssetSource('sounds/click.mp3'));
    } catch (_) {}
    
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    // --- VERIFICA O TEMA ---
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // --- DEFINIÇÃO DE CORES ---
    
    // 1. Cor Dourada Específica (Para a borda no modo escuro)
    final Color corDourada = const Color.fromARGB(255, 240, 228, 140); 

    // 2. Cores do Fundo do Cartão (Azul Clarinho / Creme)
    final Color corFundoBase = const Color.fromARGB(255, 204, 222, 245); 
    final Color corFundoGradiente = const Color.fromARGB(255, 255, 251, 226);
    
    // 3. Cor do Texto e Ícone (Azul Escuro)
    final Color corConteudo = const Color(0xFF023853); 
    
    // --- LÓGICA DA BORDA (AQUI ESTÁ A MUDANÇA) ---
    // Se for Dark: Borda DOURADA. 
    // Se for Light: Borda AZUL ESCURA.
    final Color corBorda = isDark ? corDourada : corConteudo;

    return Card(
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        // A espessura da borda dourada no escuro pode ser um pouco maior (2.0) para destacar
        side: BorderSide(color: corBorda, width: isDark ? 2.0 : 1.5), 
      ),
      child: InkWell(
        onTap: _handleTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: corConteudo.withOpacity(0.1),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                corFundoBase,
                corFundoGradiente,
              ],
            ),
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: corConteudo.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.icon,
                  size: 42.0,
                  color: corConteudo,
                ),
              ),
              const SizedBox(height: 16.0),
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: corConteudo,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    )
    .animate()
    .fadeIn(duration: 600.ms, delay: (widget.index * 100).ms)
    .slideY(begin: 0.2, end: 0, duration: 600.ms, delay: (widget.index * 100).ms);
  }
}
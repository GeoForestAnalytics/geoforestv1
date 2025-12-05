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
      // Feedback sonoro (opcional, já estava no seu código)
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
    
    // Cores do Tema (mantendo sua identidade visual)
    final Color corDourada = const Color(0xFFEBE4AB); 
     
    
    // Cores do Fundo do Cartão
    final Color corFundoBase = const Color.fromARGB(255, 204, 222, 245); 
    final Color corFundoGradiente = const Color.fromARGB(255, 255, 251, 226);
    
    final Color corConteudo = const Color(0xFF023853); 
    final Color corBorda = isDark ? corDourada : corConteudo;

    // --- EFEITO DE LUZ (O SEGREDO ESTÁ AQUI) ---
    // Se for escuro, a "luz" é dourada brilhante.
    // Se for claro, a "luz" é branca intensa.
    final Color corDaLuzSplash = isDark 
        ? const Color(0xFFEBE4AB).withOpacity(0.4) // Luz Dourada
        : Colors.white.withOpacity(0.6);           // Luz Branca

    final Color corDaLuzHighlight = isDark 
        ? const Color(0xFFEBE4AB).withOpacity(0.1) 
        : Colors.white.withOpacity(0.3);

    return Card(
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: corBorda, width: isDark ? 2.0 : 1.5), 
      ),
      // O ClipRRect garante que o efeito de luz não "vaze" pelas bordas arredondadas
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // 1. O Fundo Gradiente
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    corFundoBase,
                    corFundoGradiente,
                  ],
                ),
              ),
            ),
            
            // 2. O Conteúdo (Ícone e Texto)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: double.infinity, // Força centralização
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

            // 3. O Efeito de Luz (InkWell por cima de tudo)
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _handleTap,
                  // Configuração do Brilho
                  splashColor: corDaLuzSplash,       // O círculo de luz que se expande
                  highlightColor: corDaLuzHighlight, // O fundo que acende enquanto segura
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ),
      ),
    )
    .animate()
    .fadeIn(duration: 600.ms, delay: (widget.index * 100).ms)
    .slideY(begin: 0.2, end: 0, duration: 600.ms, delay: (widget.index * 100).ms);
  }
}
import 'package:flutter/material.dart';

class ModernMenuTile extends StatelessWidget {
  final String title;
  final String imagePath;
  final VoidCallback onTap;

  const ModernMenuTile({
    super.key,
    required this.title,
    required this.imagePath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Texto sempre Azul Escuro para contrastar com o fundo branco
    const primaryNavy = Color(0xFF023853);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          // --- AQUI ESTAVA O PROBLEMA ---
          // Antes: Colors.white.withOpacity(0.95)
          // Agora: Colors.white (Branco Puro para fundir com a imagem)
          color: Colors.white, 
          
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15), // Sombra suave
              blurRadius: 15,
              offset: const Offset(0, 8),
              spreadRadius: 2, // Espalha um pouco para destacar no fundo claro
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Imagem
            Container(
              height: 90,
              width: 90,
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(
                color: Colors.transparent, 
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                imagePath,
                fit: BoxFit.contain, 
              ),
            ),
            const SizedBox(height: 8),
            // Título
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0), // Aumentei um pouco a margem lateral
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: primaryNavy, 
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
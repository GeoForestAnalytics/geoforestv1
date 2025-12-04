// Arquivo: lib/widgets/grafico_distribuicao_widget.dart

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class GraficoDistribuicaoWidget extends StatelessWidget {
  final Map<double, int> dadosDistribuicao;

  const GraficoDistribuicaoWidget({
    super.key,
    required this.dadosDistribuicao,
  });

  @override
  Widget build(BuildContext context) {
    if (dadosDistribuicao.isEmpty) {
      return const SizedBox(
        height: 200, 
        child: Center(child: Text("Dados insuficientes para gerar o gráfico."))
      );
    }

    // --- CONFIGURAÇÃO DE TEMA E CORES ---
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Cor do texto dos eixos (Branco no escuro, Azul Escuro no claro)
    final Color corTextoEixo = isDark ? Colors.white70 : const Color(0xFF023853);
    
    // Gradiente das Barras (Estilo Neon: Ciano -> Azul Profundo)
    final LinearGradient gradienteBarras = LinearGradient(
      colors: [
        Colors.cyan.shade300, // Topo brilhante
        Colors.blue.shade900, // Base escura
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    final maxY = dadosDistribuicao.values.reduce((a, b) => a > b ? a : b).toDouble();

    // Gera os grupos de barras
    final barGroups = List.generate(dadosDistribuicao.length, (index) {
      final contagem = dadosDistribuicao.values.elementAt(index);
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: contagem.toDouble(),
            gradient: gradienteBarras, // Aplica o gradiente
            width: 18,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(6),
            ),
            // Fundo da barra (trilho)
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxY * 1.1,
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200,
            ),
          ),
        ],
      );
    });

    return AspectRatio(
      aspectRatio: 1.6,
      child: Padding(
        padding: const EdgeInsets.only(top: 16.0),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY * 1.1,
            
            // >>> CORREÇÃO DO ERRO ANTERIOR AQUI <<<
            barGroups: barGroups, 
            
            // Configuração do Tooltip (Fundo Escuro Fixo para contraste)
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFF1E293B), // Sempre escuro
                tooltipMargin: 8,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final pontoMedio = dadosDistribuicao.keys.elementAt(groupIndex);
                  // Lógica aproximada para exibir o intervalo
                  const larguraClasse = 5; 
                  final inicioClasse = pontoMedio - (larguraClasse / 2);
                  final fimClasse = pontoMedio + (larguraClasse / 2) - 0.1;
                  
                  return BarTooltipItem(
                    "Classe: ${inicioClasse.toStringAsFixed(1)}-${fimClasse.toStringAsFixed(1)}\n",
                    const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
                    children: [
                      TextSpan(
                        text: "${rod.toY.round()}",
                        style: const TextStyle(
                          color: Colors.cyanAccent, // Valor em destaque
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ]
                  );
                },
              ),
            ),
            
            // Eixos
            titlesData: FlTitlesData(
              show: true,
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), // Remove eixo Y visual
              
              // Eixo X (Categorias)
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 38,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < dadosDistribuicao.keys.length) {
                      final pontoMedio = dadosDistribuicao.keys.elementAt(index);
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          pontoMedio.toStringAsFixed(0), 
                          style: TextStyle(
                            fontSize: 11, 
                            color: corTextoEixo, 
                            fontWeight: FontWeight.bold
                          )
                        ),
                      );
                    }
                    return const Text('');
                  },
                ),
              ),
            ),
            
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(show: false),
          ),
        ),
      ),
    );
  }
}
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class GraficoDistribuicaoWidget extends StatelessWidget {
  final Map<double, int> dadosDistribuicao;
  final Color corDaBarra;

  const GraficoDistribuicaoWidget({
    super.key,
    required this.dadosDistribuicao,
    this.corDaBarra = Colors.green, // Será substituído pela cor do tema
  });

  @override
  Widget build(BuildContext context) {
    if (dadosDistribuicao.isEmpty) {
      return const SizedBox(height: 200, child: Center(child: Text("Dados insuficientes.")));
    }

    // --- DETECTA O TEMA PARA AJUSTAR CORES ---
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color corTexto = isDark ? Colors.white70 : Colors.black87;
    final Color corBarraFinal = isDark ? const Color(0xFFEBE4AB) : const Color(0xFF023853); // Dourado no Dark, Azul no Light
    
    final maxY = dadosDistribuicao.values.reduce((a, b) => a > b ? a : b).toDouble();

    final barGroups = List.generate(dadosDistribuicao.length, (index) {
      final contagem = dadosDistribuicao.values.elementAt(index);
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: contagem.toDouble(),
            color: corBarraFinal,
            width: 16,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
        ],
      );
    });

    return AspectRatio(
      aspectRatio: 1.6,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY * 1.2,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.blueGrey.shade900,
              tooltipMargin: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final pontoMedio = dadosDistribuicao.keys.elementAt(groupIndex);
                const larguraClasse = 5;
                final inicioClasse = pontoMedio - (larguraClasse / 2);
                final fimClasse = pontoMedio + (larguraClasse / 2) - 0.1;
                
                return BarTooltipItem(
                  "Classe: ${inicioClasse.toStringAsFixed(1)}-${fimClasse.toStringAsFixed(1)} cm\n"
                  "Contagem: ${rod.toY.round()}", 
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < dadosDistribuicao.keys.length) {
                    final pontoMedio = dadosDistribuicao.keys.elementAt(index);
                    return Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      // AQUI ESTAVA O ERRO: COR DO TEXTO
                      child: Text(
                        pontoMedio.toStringAsFixed(0), 
                        style: TextStyle(fontSize: 10, color: corTexto, fontWeight: FontWeight.bold)
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  if (value == 0) return const Text('');
                  if (value % meta.appliedInterval == 0) {
                     // AQUI ESTAVA O ERRO: COR DO TEXTO
                     return Text(
                       value.toInt().toString(), 
                       style: TextStyle(fontSize: 10, color: corTexto), 
                       textAlign: TextAlign.left
                     );
                  }
                  return const Text('');
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(color: corTexto.withOpacity(0.1), strokeWidth: 0.5),
          ),
          barGroups: barGroups,
        ),
      ),
    );
  }
}
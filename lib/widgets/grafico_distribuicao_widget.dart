// lib/widgets/grafico_distribuicao_widget.dart (VERSÃO DEFINITIVA CORRIGIDA)

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class GraficoDistribuicaoWidget extends StatelessWidget {
  /// O mapa de dados: { Ponto médio da classe (eixo X) : Contagem (eixo Y) }
  final Map<double, int> dadosDistribuicao;
  final Color corDaBarra;

  const GraficoDistribuicaoWidget({
    super.key,
    required this.dadosDistribuicao,
    this.corDaBarra = Colors.green,
  });

  @override
  Widget build(BuildContext context) {
    if (dadosDistribuicao.isEmpty) {
      return const SizedBox(height: 200, child: Center(child: Text("Dados insuficientes para o gráfico.")));
    }

    final maxY = dadosDistribuicao.values.reduce((a, b) => a > b ? a : b).toDouble();

    final barGroups = List.generate(dadosDistribuicao.length, (index) {
      final contagem = dadosDistribuicao.values.elementAt(index);
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: contagem.toDouble(),
            color: corDaBarra,
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
              getTooltipColor: (_) => Colors.blueGrey,
              tooltipMargin: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final pontoMedio = dadosDistribuicao.keys.elementAt(groupIndex);
                const larguraClasse = 5;
                final inicioClasse = pontoMedio - (larguraClasse / 2);
                final fimClasse = pontoMedio + (larguraClasse / 2) - 0.1;
                
                String label = "Classe: ${inicioClasse.toStringAsFixed(1)}-${fimClasse.toStringAsFixed(1)} cm\n";
                label += "Contagem: ${rod.toY.round()} árvores";
                return BarTooltipItem(
                  label, 
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
                      child: Text(pontoMedio.toStringAsFixed(0), style: const TextStyle(fontSize: 10)),
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
                     return Text(value.toInt().toString(), style: const TextStyle(fontSize: 10), textAlign: TextAlign.left);
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
            getDrawingHorizontalLine: (value) => const FlLine(color: Colors.grey, strokeWidth: 0.5),
          ),
          barGroups: barGroups,
        ),
      ),
    );
  }
}
// Arquivo: lib/widgets/grafico_afilamento_widget.dart (NOVO ARQUIVO)

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:geoforestv1/models/cubagem_secao_model.dart';

/// Um widget que exibe um gráfico de linha representando o afilamento de uma árvore.
class GraficoAfilamentoWidget extends StatelessWidget {
  final List<CubagemSecao> secoes;

  const GraficoAfilamentoWidget({super.key, required this.secoes});

  @override
  Widget build(BuildContext context) {
    // Só exibe o gráfico se houver pelo menos 2 pontos para formar uma linha.
    if (secoes.length < 2) {
      return const SizedBox.shrink(); // Retorna um widget vazio se não houver dados
    }

    // Converte os dados das seções para pontos que o gráfico entende (FlSpot).
    // Eixo X: Diâmetro (para ver o perfil "deitado" da árvore)
    // Eixo Y: Altura
    final spots = secoes.map((secao) {
      return FlSpot(secao.diametroSemCasca, secao.alturaMedicao);
    }).toList();

    return AspectRatio(
      aspectRatio: 1.7, // Proporção do gráfico
      child: LineChart(
        LineChartData(
          // Aparência da linha principal
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false, // Linhas retas entre os pontos
              color: Colors.brown.shade700,
              barWidth: 3,
              dotData: FlDotData(
                show: true, // Mostra os pontos de medição
                getDotPainter: (spot, percent, barData, index) =>
                    FlDotCirclePainter(radius: 4, color: Colors.orange.shade800),
              ),
              belowBarData: BarAreaData(show: false),
            ),
          ],
          // Títulos dos eixos
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              axisNameWidget: const Text("Diâmetro Sem Casca (cm)"),
              sideTitles: SideTitles(showTitles: true, reservedSize: 30, interval: 10),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: const Text("Altura (m)"),
              sideTitles: SideTitles(showTitles: true, reservedSize: 40, interval: 5),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          // Tooltip ao tocar nos pontos
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => Colors.blueGrey,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    'Altura: ${spot.y.toStringAsFixed(2)} m\nDiâmetro: ${spot.x.toStringAsFixed(2)} cm',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  );
                }).toList();
              },
            ),
          ),
          // Linhas de grade e bordas
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: 5,
            verticalInterval: 10,
            getDrawingHorizontalLine: (value) => const FlLine(color: Colors.grey, strokeWidth: 0.5),
            getDrawingVerticalLine: (value) => const FlLine(color: Colors.grey, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: const Color(0xff37434d), width: 1),
          ),
        ),
      ),
    );
  }
}
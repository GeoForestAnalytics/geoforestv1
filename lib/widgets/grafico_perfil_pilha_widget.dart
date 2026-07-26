import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/models/pilha_madeira_model.dart';

/// Gráfico do perfil de altura da pilha ao longo do seu comprimento.
/// X = distância (m) desde o início; Y = altura medida em cada seção.
/// Pontos virtuais em 0,0m e comprimento (altura=0) representam as cunhas das bordas.
class GraficoPerfilPilhaWidget extends StatelessWidget {
  final List<SecaoPilha> secoes;
  final double comprimentoPilha;

  const GraficoPerfilPilhaWidget({
    super.key,
    required this.secoes,
    required this.comprimentoPilha,
  });

  @override
  Widget build(BuildContext context) {
    if (secoes.isEmpty) return const SizedBox.shrink();

    // Pontos da linha: borda esquerda (0, 0) + seções medidas + borda direita (comp, 0)
    final spots = <FlSpot>[
      const FlSpot(0, 0),
      ...secoes.map((s) => FlSpot(s.distanciaMetros, s.altura)),
      FlSpot(comprimentoPilha, 0),
    ];

    final maxY = secoes.map((s) => s.altura).reduce((a, b) => a > b ? a : b);
    final yInterval = _niceInterval(maxY);

    return AspectRatio(
      aspectRatio: 2.0,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: comprimentoPilha,
          minY: 0,
          maxY: (maxY * 1.2).ceilToDouble(),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              color: Colors.brown.shade700,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                checkToShowDot: (spot, _) => spot.x != 0 && spot.x != comprimentoPilha,
                getDotPainter: (_, __, ___, ____) =>
                    FlDotCirclePainter(radius: 4, color: Colors.orange.shade700),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.brown.shade100.withAlpha(180),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              axisNameWidget: const Text('Distância (m)', style: TextStyle(fontSize: 11)),
              axisNameSize: 18,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: _niceInterval(comprimentoPilha),
                getTitlesWidget: (v, _) => Text(
                  v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1),
                  style: const TextStyle(fontSize: 9),
                ),
              ),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: const Text('Altura (m)', style: TextStyle(fontSize: 11)),
              axisNameSize: 18,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: yInterval,
                getTitlesWidget: (v, _) => Text(
                  v.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 9),
                ),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => Colors.brown.shade800,
              getTooltipItems: (spots) => spots.map((s) {
                if (s.x == 0 || s.x == comprimentoPilha) return null;
                return LineTooltipItem(
                  '${s.x.toStringAsFixed(2)} m\n${s.y.toStringAsFixed(2)} m alt',
                  const TextStyle(color: Colors.white, fontSize: 11),
                );
              }).toList(),
            ),
          ),
          gridData: FlGridData(
            show: true,
            horizontalInterval: yInterval,
            verticalInterval: _niceInterval(comprimentoPilha),
            getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade300, strokeWidth: 0.5),
            getDrawingVerticalLine: (_) => FlLine(color: Colors.grey.shade300, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: Colors.grey.shade400),
          ),
        ),
      ),
    );
  }

  double _niceInterval(double range) {
    if (range <= 2) return 0.5;
    if (range <= 5) return 1.0;
    if (range <= 10) return 2.0;
    if (range <= 20) return 5.0;
    if (range <= 50) return 10.0;
    return (range / 5).ceilToDouble();
  }
}

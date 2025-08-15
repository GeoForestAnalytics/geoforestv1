// lib/widgets/fazenda_progress_cluster.dart (ARQUIVO CORRIGIDO)

import 'package:flutter/material.dart';
import 'package:pie_chart/pie_chart.dart';

class FazendaProgressCluster extends StatelessWidget {
  final String nomeFazenda;
  final int totalParcelas;
  final int concluidas;
  final double progresso;
  final VoidCallback onTap;

  const FazendaProgressCluster({
    super.key,
    required this.nomeFazenda,
    required this.totalParcelas,
    required this.concluidas,
    required this.progresso,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color progressoColor;
    if (progresso >= 1.0) {
      progressoColor = Colors.green;
    } else if (progresso > 0) {
      progressoColor = Colors.orange.shade700;
    } else {
      progressoColor = Colors.grey.shade600;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              dataMap: {
                "concluidas": progresso,
                "restantes": progresso > 0 ? 1.0 - progresso : 1.0, // Garante que a soma seja sempre > 0
              },
              animationDuration: const Duration(milliseconds: 800),
              chartType: ChartType.ring,
              ringStrokeWidth: 8,
              chartRadius: 100,
              colorList: [progressoColor, Colors.black.withOpacity(0.3)],
              // <<< CORREÇÃO: A sintaxe correta para esconder a legenda >>>
              legendOptions: const LegendOptions(
                showLegends: false,
              ),
              chartValuesOptions: const ChartValuesOptions(showChartValues: false),
            ),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.95),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        nomeFazenda,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "$concluidas / $totalParcelas",
                        style: TextStyle(
                          fontSize: 14,
                          color: progressoColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
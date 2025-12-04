// lib/widgets/ranking_detalhado_chart.dart

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'dart:math' as math;

class LeaderStats {
  final String name;
  final int amostras;
  final int cubagens;
  
  int get total => amostras + cubagens;

  LeaderStats(this.name, this.amostras, this.cubagens);
}

class RankingDetalhadoChart extends StatefulWidget {
  final List<Parcela> parcelas;
  final List<CubagemArvore> cubagens;

  const RankingDetalhadoChart({
    super.key, 
    required this.parcelas, 
    required this.cubagens
  });

  @override
  State<RankingDetalhadoChart> createState() => _RankingDetalhadoChartState();
}

class _RankingDetalhadoChartState extends State<RankingDetalhadoChart> {
  late List<LeaderStats> _data;

  @override
  void initState() {
    super.initState();
    _processData();
  }

  void _processData() {
    // 1. Agrupa Parcelas (Amostras) por Líder
    final Map<String, int> amostrasMap = {};
    for (var p in widget.parcelas) {
      if (p.status == StatusParcela.concluida || p.status == StatusParcela.exportada) {
        final lider = p.nomeLider ?? 'Desconhecido';
        amostrasMap[lider] = (amostrasMap[lider] ?? 0) + 1;
      }
    }

    // 2. Agrupa Cubagens por Líder
    final Map<String, int> cubagensMap = {};
    for (var c in widget.cubagens) {
      if (c.alturaTotal > 0) {
        final lider = c.nomeLider ?? 'Desconhecido';
        cubagensMap[lider] = (cubagensMap[lider] ?? 0) + 1;
      }
    }

    // 3. Unifica as listas
    final Set<String> todosLideres = {...amostrasMap.keys, ...cubagensMap.keys};
    
    _data = todosLideres.map((lider) {
      return LeaderStats(
        lider, 
        amostrasMap[lider] ?? 0, 
        cubagensMap[lider] ?? 0
      );
    }).toList();

    // 4. Ordena pelo total (maior para o menor) e pega o top 7
    _data.sort((a, b) => b.total.compareTo(a.total));
    if (_data.length > 7) {
      _data = _data.sublist(0, 7);
    }
    
    // Inverte a lista para o Top 1 aparecer no topo visual do gráfico (após a rotação)
    _data = _data.reversed.toList();
  }

  String _getInitials(String name) {
    if (name.isEmpty) return "?";
    List<String> names = name.trim().split(" ");
    if (names.length > 1) {
      return "${names[0][0]}${names[1][0]}".toUpperCase();
    }
    return names[0].length > 1 ? names[0].substring(0, 2).toUpperCase() : names[0].toUpperCase();
  }
  
  // Pega apenas o primeiro nome para exibir no eixo
  String _getFirstName(String name) {
    if (name.isEmpty) return "N/A";
    return name.trim().split(" ").first;
  }

  @override
  Widget build(BuildContext context) {
    const Color corFundo = Color(0xFF2D3440);
    const Color corAmostra = Color(0xFFFFC107); // Amarelo
    const Color corCubagem = Color(0xFF26C6DA); // Ciano
    const Color corTexto = Colors.white;
    
    // Altura dinâmica
    final double chartHeight = math.max(_data.length * 80.0, 350.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(10),
      child: Container(
        width: double.infinity,
        height: chartHeight,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: corFundo,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Produtividade por Equipe",
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                )
              ],
            ),
            const SizedBox(height: 10),
            
            // Legenda
            Row(
              children: [
                _buildLegendItem(corAmostra, "Amostras"),
                const SizedBox(width: 16),
                _buildLegendItem(corCubagem, "Cubagens"),
              ],
            ),
            const SizedBox(height: 20),
            
            // Gráfico
            Expanded(
              child: RotatedBox(
                quarterTurns: 1, // Gira 90 graus
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    
                    // Desativa linhas de grade para visual mais limpo
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    
                    titlesData: FlTitlesData(
                      show: true,
                      // Esconde Eixo Esquerdo (que virou Topo)
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      // Esconde Eixo Direito (que virou Baixo)
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      // Esconde Eixo Topo (que virou Direita)
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),

                      // BOTTOM TITLES: Após a rotação de 90 graus, o 'Bottom' vira a 'Esquerda' visualmente.
                      // É aqui que colocamos os nomes/avatares.
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 110, // Espaço reservado para Nome + Avatar
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= _data.length) return const SizedBox();
                            
                            final stats = _data[index];

                            // Rotacionamos o conteúdo de volta (-1) para ficar em pé
                            return RotatedBox(
                              quarterTurns: -1,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  // Nome do Líder
                                  Flexible(
                                    child: Text(
                                      _getFirstName(stats.name),
                                      style: const TextStyle(color: corTexto, fontSize: 12, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Avatar com Iniciais
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Colors.white.withOpacity(0.15),
                                    child: Text(
                                      _getInitials(stats.name),
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // Tooltip ao tocar na barra
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => Colors.black87,
                        tooltipPadding: const EdgeInsets.all(8),
                        tooltipMargin: 8,
                        rotateAngle: -90, // Gira o tooltip para ficar legível
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final stats = _data[groupIndex];
                          return BarTooltipItem(
                            stats.name, // Nome completo no tooltip
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            children: [
                              TextSpan(text: '\n\nAmostras: ${stats.amostras}', style: const TextStyle(color: corAmostra, fontSize: 12)),
                              TextSpan(text: '\nCubagens: ${stats.cubagens}', style: const TextStyle(color: corCubagem, fontSize: 12)),
                              TextSpan(text: '\nTotal: ${stats.total}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          );
                        },
                      ),
                    ),
                    
                    // Dados das Barras
                    barGroups: _data.asMap().entries.map((entry) {
                      final index = entry.key;
                      final stats = entry.value;
                      return BarChartGroupData(
                        x: index,
                        barRods: [
                          // Barra de Cubagem (Azul)
                          BarChartRodData(
                            toY: stats.cubagens.toDouble(),
                            color: corCubagem,
                            width: 14,
                            borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                          ),
                          // Barra de Amostras (Amarela)
                          BarChartRodData(
                            toY: stats.amostras.toDouble(),
                            color: corAmostra,
                            width: 14,
                            borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                          ),
                        ],
                        barsSpace: 8, // Espaço entre as barras do mesmo líder
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
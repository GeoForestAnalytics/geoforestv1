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
    final Map<String, int> amostrasMap = {};
    for (var p in widget.parcelas) {
      if (p.status == StatusParcela.concluida || p.status == StatusParcela.exportada) {
        final lider = p.nomeLider ?? 'Desconhecido';
        amostrasMap[lider] = (amostrasMap[lider] ?? 0) + 1;
      }
    }

    final Map<String, int> cubagensMap = {};
    for (var c in widget.cubagens) {
      if (c.alturaTotal > 0) {
        final lider = c.nomeLider ?? 'Desconhecido';
        cubagensMap[lider] = (cubagensMap[lider] ?? 0) + 1;
      }
    }

    final Set<String> todosLideres = {...amostrasMap.keys, ...cubagensMap.keys};
    
    _data = todosLideres.map((lider) {
      return LeaderStats(
        lider, 
        amostrasMap[lider] ?? 0, 
        cubagensMap[lider] ?? 0
      );
    }).toList();

    // Ordena do Maior para o Menor (Top 1 no índice 0)
    _data.sort((a, b) => b.total.compareTo(a.total));
    
    // REMOVIDO: _data = _data.reversed.toList(); 
    // Sem o reverse, o Índice 0 (Maior) fica no topo do gráfico rotacionado.
  }

  String _getInitials(String name) {
    if (name.isEmpty) return "?";
    List<String> names = name.trim().split(" ");
    if (names.length > 1) {
      return "${names[0][0]}${names[1][0]}".toUpperCase();
    }
    return names[0].length > 1 ? names[0].substring(0, 2).toUpperCase() : names[0].toUpperCase();
  }
  
  String _getFirstName(String name) {
    if (name.isEmpty) return "N/A";
    return name.trim().split(" ").first;
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 0: return const Color(0xFFFFD700); // Ouro (1º Lugar)
      case 1: return const Color(0xFFC0C0C0); // Prata (2º Lugar)
      case 2: return const Color(0xFFCD7F32); // Bronze (3º Lugar)
      default: return Colors.grey;
    }
  }

  Widget? _getRankIcon(int rank) {
    switch (rank) {
      case 0: return const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 14);
      case 1: return const Icon(Icons.looks_two, color: Color(0xFFC0C0C0), size: 14);
      case 2: return const Icon(Icons.looks_3, color: Color(0xFFCD7F32), size: 14);
      default: return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // --- CORES ---
    final Color corFundo = isDark ? const Color(0xFF2D3440) : Colors.white;
    final Color corTextoPrincipal = isDark ? Colors.white : const Color(0xFF023853);
    final Color corTextoSecundario = isDark ? Colors.white70 : Colors.black54;
    final Color corIconeFechar = isDark ? Colors.white54 : Colors.grey;
    
    // Cores fixas para o gráfico (Amostra/Cubagem)
    const Color corAmostra = Color.fromARGB(255, 255, 250, 160); // Ouro Vibrante 
    const Color corCubagem = Color(0xFF00838F); // Ciano/Teal Escuro (para contraste no branco) 
    
    final Color corAvatarPadraoBg = isDark ? Colors.white.withOpacity(0.15) : Colors.grey.shade200;
    final Color corAvatarPadraoTxt = isDark ? Colors.white : Colors.black87;

    final double chartHeight = math.max(_data.length * 90.0, 400.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          height: chartHeight,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: corFundo,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Ranking Completo (${_data.length})",
                    style: TextStyle(color: corTextoPrincipal, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: corIconeFechar),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                ],
              ),
              const SizedBox(height: 10),
              
              // Legenda
              Row(
                children: [
                  _buildLegendItem(corAmostra, "Amostras", corTextoSecundario),
                  const SizedBox(width: 16),
                  _buildLegendItem(corCubagem, "Cubagens", corTextoSecundario),
                ],
              ),
              const SizedBox(height: 20),
              
              // Gráfico
              Expanded(
                child: RotatedBox(
                  quarterTurns: 1, // Gira 90 graus. Índice 0 fica no TOPO.
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      
                      titlesData: FlTitlesData(
                        show: true,
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),

                        // EIXO DOS NOMES
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 120, 
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= _data.length) return const SizedBox();
                              
                              final stats = _data[index];
                              
                              // CORREÇÃO: O rank é o próprio índice agora (0 é o primeiro)
                              final int rank = index; 
                              final bool isTop3 = rank <= 2;
                              
                              final Color corDestaque = isTop3 ? _getRankColor(rank) : corTextoSecundario;
                              final Widget? iconeRank = _getRankIcon(rank);

                              return RotatedBox(
                                quarterTurns: -1,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (iconeRank != null) ...[
                                      iconeRank,
                                      const SizedBox(width: 4),
                                    ],
                                    
                                    // Nome do Líder
                                    Flexible(
                                      child: Text(
                                        _getFirstName(stats.name),
                                        style: TextStyle(
                                          color: isTop3 && isDark ? corDestaque : (isTop3 ? Colors.black87 : corTextoSecundario), 
                                          fontSize: 12, 
                                          fontWeight: isTop3 ? FontWeight.bold : FontWeight.normal
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    
                                    // Avatar com Iniciais
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: isTop3 ? corDestaque.withOpacity(0.2) : corAvatarPadraoBg,
                                        shape: BoxShape.circle,
                                        border: isTop3 ? Border.all(color: corDestaque, width: 1.5) : null
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        _getInitials(stats.name),
                                        style: TextStyle(
                                          color: isTop3 
                                            ? (isDark ? corDestaque : Colors.black87)
                                            : corAvatarPadraoTxt, 
                                          fontSize: 11, 
                                          fontWeight: FontWeight.bold
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => const Color(0xFF2D3440),
                          tooltipPadding: const EdgeInsets.all(8),
                          tooltipMargin: 8,
                          rotateAngle: -90,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final stats = _data[groupIndex];
                            // CORREÇÃO: O rank no tooltip também é o índice
                            final int rank = groupIndex;
                            return BarTooltipItem(
                              "#${rank + 1} - ${stats.name}",
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
                      
                      barGroups: _data.asMap().entries.map((entry) {
                        final index = entry.key;
                        final stats = entry.value;
                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: stats.cubagens.toDouble(),
                              color: corCubagem,
                              width: 14,
                              borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                            ),
                            BarChartRodData(
                              toY: stats.amostras.toDouble(),
                              color: corAmostra,
                              width: 14,
                              borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                            ),
                          ],
                          barsSpace: 6, 
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, Color textColor) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: textColor, fontSize: 12)),
      ],
    );
  }
}
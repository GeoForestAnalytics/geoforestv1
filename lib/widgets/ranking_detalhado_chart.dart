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
    required this.cubagens,
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
    for (final p in widget.parcelas) {
      if (p.status == StatusParcela.concluida || p.status == StatusParcela.exportada) {
        final lider = p.nomeLider ?? 'Desconhecido';
        amostrasMap[lider] = (amostrasMap[lider] ?? 0) + 1;
      }
    }
    final Map<String, int> cubagensMap = {};
    for (final c in widget.cubagens) {
      if (c.alturaTotal > 0) {
        final lider = c.nomeLider ?? 'Desconhecido';
        cubagensMap[lider] = (cubagensMap[lider] ?? 0) + 1;
      }
    }
    final Set<String> todos = {...amostrasMap.keys, ...cubagensMap.keys};
    _data = todos
        .map((l) => LeaderStats(l, amostrasMap[l] ?? 0, cubagensMap[l] ?? 0))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length > 1) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.length > 1 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();
  }

  String _firstName(String name) => name.trim().split(' ').first;

  Color _rankColor(int rank) => const [
        Color(0xFFFFD700),
        Color(0xFFC0C0C0),
        Color(0xFFCD7F32),
      ][rank < 3 ? rank : 2];

  Widget? _rankIcon(int rank) {
    switch (rank) {
      case 0:
        return const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 15);
      case 1:
        return const Icon(Icons.looks_two, color: Color(0xFFC0C0C0), size: 15);
      case 2:
        return const Icon(Icons.looks_3, color: Color(0xFFCD7F32), size: 15);
      default:
        return Text(
          '${rank + 1}',
          style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bgCard = isDark ? const Color(0xFF1C2533) : Colors.white;
    final Color textPrimary = isDark ? Colors.white : const Color(0xFF023853);
    final Color textSecondary = isDark ? Colors.white60 : Colors.black54;

    const Color corAmostra = Color(0xFFFFC107);   // amber
    const Color corCubagem = Color(0xFF00838F);    // teal

    final maxTotal = _data.isEmpty
        ? 1
        : _data.map((s) => s.total).reduce(math.max);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        decoration: BoxDecoration(
          color: bgCard,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ranking Completo (${_data.length})',
                  style: TextStyle(color: textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: textSecondary),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            // Legenda
            Row(
              children: [
                _legendItem(corAmostra, 'Amostras', textSecondary),
                const SizedBox(width: 16),
                _legendItem(corCubagem, 'Cubagens', textSecondary),
              ],
            ),
            const SizedBox(height: 14),
            // Lista
            Flexible(
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final barAreaWidth = constraints.maxWidth - 116.0; // 108 nome + 8 gap
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: _data.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _buildRow(
                      i, _data[i], barAreaWidth, maxTotal,
                      isDark, textSecondary, corAmostra, corCubagem,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    int rank,
    LeaderStats stats,
    double barAreaWidth,
    int maxTotal,
    bool isDark,
    Color textSecondary,
    Color corAmostra,
    Color corCubagem,
  ) {
    final isTop3 = rank < 3;
    final rankCol = isTop3 ? _rankColor(rank) : textSecondary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Coluna de nome (fixa 108px)
        SizedBox(
          width: 108,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(width: 18, child: Center(child: _rankIcon(rank))),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _firstName(stats.name),
                  style: TextStyle(
                    color: isTop3 ? rankCol : textSecondary,
                    fontSize: 12,
                    fontWeight: isTop3 ? FontWeight.bold : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: isTop3
                      ? rankCol.withValues(alpha: isDark ? 0.25 : 0.15)
                      : (isDark ? Colors.white12 : Colors.grey.shade200),
                  shape: BoxShape.circle,
                  border: isTop3 ? Border.all(color: rankCol, width: 1.5) : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(stats.name),
                  style: TextStyle(
                    color: isTop3 ? rankCol : (isDark ? Colors.white70 : Colors.black87),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Coluna de barras
        SizedBox(
          width: barAreaWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stats.amostras > 0)
                _bar(stats.amostras, maxTotal, barAreaWidth, corAmostra, isDark),
              if (stats.amostras > 0 && stats.cubagens > 0) const SizedBox(height: 3),
              if (stats.cubagens > 0)
                _bar(stats.cubagens, maxTotal, barAreaWidth, corCubagem, isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bar(int value, int maxTotal, double maxWidth, Color color, bool isDark) {
    const barH = 22.0;
    const minInsideWidth = 38.0;
    final barW = (value / maxTotal) * maxWidth;
    final labelInside = barW >= minInsideWidth;

    // Texto dentro da barra: sempre escuro (amarelo/teal são claros e escuros respectivamente)
    final labelColor = labelInside
        ? (color == const Color(0xFFFFC107) ? Colors.black87 : Colors.white)
        : (isDark ? Colors.white70 : Colors.black54);

    return SizedBox(
      width: maxWidth,
      height: barH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Barra
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: math.max(barW, 4),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          // Valor
          Positioned(
            left: labelInside ? math.max(0, barW - 34) : barW + 5,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$value',
                style: TextStyle(
                  color: labelColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label, Color textColor) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: textColor, fontSize: 12)),
      ],
    );
  }
}

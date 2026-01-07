// lib/widgets/grafico_dispersao_cap_altura.dart (VERSÃO FINAL DINÂMICA - SEM OVERFLOW)

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:collection/collection.dart';

enum EixoYDispersao { alturaTotal, alturaDano }

class GraficoDispersaoCapAltura extends StatefulWidget {
  final List<Arvore> arvores;

  const GraficoDispersaoCapAltura({super.key, required this.arvores});

  @override
  State<GraficoDispersaoCapAltura> createState() => _GraficoDispersaoCapAlturaState();
}

class _GraficoDispersaoCapAlturaState extends State<GraficoDispersaoCapAltura> {
  // Agora usamos String para os códigos
  late Set<String> _codigosVisiveis;
  late List<String> _codigosUnicos;
  EixoYDispersao _eixoYSelecionado = EixoYDispersao.alturaTotal;

  @override
  void initState() {
    super.initState();
    // Extrai todos os códigos únicos (Strings) das árvores fornecidas
    _codigosUnicos = widget.arvores.map((a) => a.codigo).toSet().toList();
    _codigosUnicos.sort();
    _codigosVisiveis = _codigosUnicos.toSet();
  }

  // Mapeamento de cores baseado nos IDs da sua planilha Excel
  Color _getColorForCodigo(String codigo) {
    switch (codigo) {
      case '101': return Colors.blue;          // Normal
      case '107': return Colors.redAccent;    // Falha
      case '114': return Colors.grey;         // Morta
      case '102':                             // Bifurcada A
      case '103': return Colors.purpleAccent; // Bifurcada B
      case '117': return Colors.orangeAccent; // Quebrada
      case '104':                             // Caída
      case '105': return Colors.brown;        // Caída Raiz
      case '106': return Colors.cyanAccent;   // Dominada
      default: 
        // Para qualquer outro código vindo do Excel, gera uma cor baseada no texto
        return Colors.primaries[codigo.hashCode % Colors.primaries.length];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBackgroundColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color corTextoEixo = isDark ? Colors.white54 : Colors.black54;

    // Filtra as árvores para o gráfico
    final arvoresFiltradas = widget.arvores.where((arvore) {
      final hasData = arvore.cap > 0 &&
          (_eixoYSelecionado == EixoYDispersao.alturaTotal
              ? (arvore.altura ?? 0) > 0
              : (arvore.alturaDano ?? 0) > 0);
      return _codigosVisiveis.contains(arvore.codigo) && hasData;
    }).toList();

    return Card(
      elevation: 4,
      color: cardBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Dispersão CAP vs. Altura', 
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 18,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownButton<EixoYDispersao>(
                  value: _eixoYSelecionado,
                  dropdownColor: cardBackgroundColor,
                  underline: const SizedBox(),
                  icon: Icon(Icons.swap_vert, color: isDark ? Colors.cyanAccent : Colors.blue),
                  style: TextStyle(
                    color: isDark ? Colors.cyanAccent : Colors.blue, 
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  onChanged: (EixoYDispersao? newValue) {
                    if (newValue != null) setState(() => _eixoYSelecionado = newValue);
                  },
                  items: const [
                    DropdownMenuItem(value: EixoYDispersao.alturaTotal, child: Text("Alt. Total")),
                    DropdownMenuItem(value: EixoYDispersao.alturaDano, child: Text("Alt. Dano")),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Filtros de Códigos (Chips Dinâmicos)
            Wrap(
              spacing: 6.0,
              runSpacing: 4.0,
              children: _codigosUnicos.map((codigo) {
                final isSelected = _codigosVisiveis.contains(codigo);
                final color = _getColorForCodigo(codigo);
                return FilterChip(
                  label: Text(codigo),
                  labelStyle: TextStyle(
                    fontSize: 10,
                    color: isSelected ? (isDark ? Colors.black : Colors.white) : (isDark ? Colors.white54 : Colors.black54),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) _codigosVisiveis.add(codigo);
                      else _codigosVisiveis.remove(codigo);
                    });
                  },
                  backgroundColor: Colors.transparent,
                  selectedColor: color,
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            
            // O Gráfico
            AspectRatio(
              aspectRatio: 1.4,
              child: arvoresFiltradas.isEmpty
                  ? const Center(child: Text("Selecione os códigos para visualizar."))
                  : ScatterChart(
                      ScatterChartData(
                        scatterSpots: arvoresFiltradas.mapIndexed((index, arvore) {
                          return ScatterSpot(
                            arvore.cap, 
                            _eixoYSelecionado == EixoYDispersao.alturaTotal ? arvore.altura! : arvore.alturaDano!,
                            dotPainter: FlDotCirclePainter(
                              radius: 6, 
                              color: _getColorForCodigo(arvore.codigo).withOpacity(0.6), 
                              strokeWidth: 0,
                            ),
                          );
                        }).toList(),
                        
                        titlesData: FlTitlesData(
                          show: true,
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              getTitlesWidget: (value, meta) => Padding(
                                padding: const EdgeInsets.only(top: 6.0),
                                child: Text(value.toInt().toString(), style: TextStyle(color: corTextoEixo, fontSize: 10)),
                              ),
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: TextStyle(color: corTextoEixo, fontSize: 10)),
                            ),
                          ),
                        ),
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        scatterTouchData: ScatterTouchData(
                          enabled: true,
                          handleBuiltInTouches: true,
                          touchTooltipData: ScatterTouchTooltipData(
                            getTooltipColor: (_) => const Color(0xFF0F172A),
                            getTooltipItems: (touchedSpot) {
                              // Busca a árvore exata que foi tocada para mostrar no balão
                              final arvoreTocada = arvoresFiltradas.firstWhereOrNull((a) => a.cap == touchedSpot.x);
                              if (arvoreTocada == null) return null;
                              return ScatterTooltipItem(
                                'Código: ${arvoreTocada.codigo}\nCAP: ${arvoreTocada.cap}\nAlt: ${touchedSpot.y}',
                                textStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              );
                            },
                          ),
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
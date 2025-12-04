// lib/widgets/grafico_dispersao_cap_altura.dart (VERSÃO CORRIGIDA - SEM OVERFLOW)

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:collection/collection.dart';

// Enum para controlar o que é exibido no eixo Y
enum EixoYDispersao { alturaTotal, alturaDano }

class GraficoDispersaoCapAltura extends StatefulWidget {
  final List<Arvore> arvores;

  const GraficoDispersaoCapAltura({super.key, required this.arvores});

  @override
  State<GraficoDispersaoCapAltura> createState() => _GraficoDispersaoCapAlturaState();
}

class _GraficoDispersaoCapAlturaState extends State<GraficoDispersaoCapAltura> {
  // Estado para controlar os filtros
  late Set<Codigo> _codigosVisiveis;
  late List<Codigo> _codigosUnicos;
  EixoYDispersao _eixoYSelecionado = EixoYDispersao.alturaTotal;

  @override
  void initState() {
    super.initState();
    // Encontra todos os códigos únicos presentes nos dados e os ativa por padrão
    _codigosUnicos = widget.arvores.map((a) => a.codigo).toSet().toList();
    _codigosUnicos.sort((a, b) => a.name.compareTo(b.name));
    _codigosVisiveis = _codigosUnicos.toSet();
  }

  // Cores Neon/Vibrantes para o modo escuro
  Color _getColorForCodigo(Codigo codigo) {
    switch (codigo) {
      case Codigo.Normal: return Colors.blue; 
      case Codigo.Falha: return Colors.redAccent;
      case Codigo.MortaOuSeca: return Colors.grey;
      case Codigo.Bifurcada: return Colors.purpleAccent;
      case Codigo.Quebrada: return Colors.orangeAccent;
      case Codigo.Caida: return Colors.brown;
      case Codigo.Multipla: return Colors.yellowAccent;
      case Codigo.Dominada: return Colors.cyanAccent;
      default: return Colors.tealAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- CORES DO TEMA ---
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final Color cardBackgroundColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color corTextoEixo = isDark ? Colors.white54 : Colors.black54;

    // Filtra as árvores
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
            // --- CABEÇALHO CORRIGIDO (SEM OVERFLOW) ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Expanded força o texto a ocupar só o espaço disponível
                Expanded(
                  child: Text(
                    'Dispersão CAP vs. Altura', 
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 18, // Tamanho levemente reduzido para segurança
                    ),
                    overflow: TextOverflow.ellipsis, // Adiciona ... se for muito longo
                  ),
                ),
                const SizedBox(width: 8),
                // Dropdown compacto
                DropdownButton<EixoYDispersao>(
                  value: _eixoYSelecionado,
                  dropdownColor: cardBackgroundColor,
                  underline: const SizedBox(),
                  icon: Icon(Icons.swap_vert, color: isDark ? Colors.cyanAccent : Colors.blue),
                  style: TextStyle(
                    color: isDark ? Colors.cyanAccent : Colors.blue, 
                    fontWeight: FontWeight.bold,
                    fontSize: 12, // Fonte menor para caber
                  ),
                  onChanged: (EixoYDispersao? newValue) {
                    if (newValue != null) {
                      setState(() => _eixoYSelecionado = newValue);
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: EixoYDispersao.alturaTotal, child: Text("Alt. Total")),
                    DropdownMenuItem(value: EixoYDispersao.alturaDano, child: Text("Alt. Dano")),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // FILTROS DE CÓDIGO
            Wrap(
              spacing: 6.0,
              runSpacing: 6.0, // Adicionado espaçamento vertical para evitar colisão
              children: _codigosUnicos.map((codigo) {
                final isSelected = _codigosVisiveis.contains(codigo);
                final color = _getColorForCodigo(codigo);
                return FilterChip(
                  label: Text(codigo.name),
                  labelStyle: TextStyle(
                    fontSize: 10,
                    color: isSelected 
                        ? (isDark ? Colors.black : Colors.white) 
                        : (isDark ? Colors.white54 : Colors.black54),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _codigosVisiveis.add(codigo);
                      } else {
                        _codigosVisiveis.remove(codigo);
                      }
                    });
                  },
                  backgroundColor: Colors.transparent,
                  selectedColor: color,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: isSelected ? Colors.transparent : (isDark ? Colors.white24 : Colors.black12)
                    )
                  ),
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            
            // GRÁFICO
            AspectRatio(
              aspectRatio: 1.3,
              child: arvoresFiltradas.isEmpty
                  ? const Center(child: Text("Nenhum dado para exibir."))
                  : ScatterChart(
                      ScatterChartData(
                        scatterSpots: arvoresFiltradas.mapIndexed((index, arvore) {
                          return ScatterSpot(
                            arvore.cap, // Eixo X
                            _eixoYSelecionado == EixoYDispersao.alturaTotal
                                ? arvore.altura!
                                : arvore.alturaDano!, // Eixo Y
                            dotPainter: FlDotCirclePainter(
                              radius: 8, 
                              color: _getColorForCodigo(arvore.codigo).withOpacity(0.5), 
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
                                child: Text(
                                  value.toInt().toString(),
                                  style: TextStyle(color: corTextoEixo, fontSize: 10),
                                ),
                              ),
                            ),
                          ),
                          
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              getTitlesWidget: (value, meta) => Text(
                                value.toInt().toString(),
                                style: TextStyle(color: corTextoEixo, fontSize: 10),
                              ),
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
                              final spots = arvoresFiltradas.mapIndexed((index, arvore) {
                                return ScatterSpot(
                                  arvore.cap,
                                  _eixoYSelecionado == EixoYDispersao.alturaTotal ? arvore.altura! : arvore.alturaDano!,
                                );
                              }).toList();
                              
                              final spotIndex = spots.indexWhere((spot) => spot.x == touchedSpot.x && spot.y == touchedSpot.y);
                              if (spotIndex < 0) return null;
                              
                              final arvoreTocada = arvoresFiltradas[spotIndex];
                              return ScatterTooltipItem(
                                '${arvoreTocada.codigo.name}\nCAP: ${arvoreTocada.cap}\nAlt: ${touchedSpot.y}',
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
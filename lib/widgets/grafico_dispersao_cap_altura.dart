// lib/widgets/grafico_dispersao_cap_altura.dart (VERSÃO COMPLETA E CORRIGIDA)

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
  // Estado para controlar os filtros (agora usando String)
  late Set<String> _codigosVisiveis;
  late List<String> _codigosUnicos;
  EixoYDispersao _eixoYSelecionado = EixoYDispersao.alturaTotal;

  @override
  void initState() {
    super.initState();
    // Encontra todos os códigos únicos (Strings) presentes nos dados
    _codigosUnicos = widget.arvores.map((a) => a.codigo).toSet().toList();
    _codigosUnicos.sort(); // Ordena alfabeticamente
    _codigosVisiveis = _codigosUnicos.toSet();
  }

  // Cores dinâmicas baseadas na sigla
  Color _getColorForCodigo(String codigo) {
    // Padronização para maiúsculas para evitar erros
    final cod = codigo.toUpperCase();
    
    // Mapeamento visual para as siglas mais comuns
    if (cod == "N") return Colors.blue;          // Normal
    if (cod == "F") return Colors.redAccent;     // Falha
    if (cod == "M") return Colors.grey;          // Morta
    if (cod == "A") return Colors.purpleAccent;  // Bifurcada Acima
    if (cod == "B" || cod == "BF") return Colors.pinkAccent; // Bifurcada Abaixo
    if (cod == "Q") return Colors.orangeAccent;  // Quebrada
    if (cod == "CA") return Colors.brown;        // Caída
    if (cod == "D") return Colors.cyanAccent;    // Dominada
    
    // Cores genéricas para outros códigos dinâmicos
    // Usa o hashCode para garantir que o mesmo código sempre tenha a mesma cor
    return Colors.primaries[cod.hashCode % Colors.primaries.length];
  }

  @override
  Widget build(BuildContext context) {
    // --- CORES DO TEMA ---
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final Color cardBackgroundColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color corTextoEixo = isDark ? Colors.white54 : Colors.black54;

    // Filtra as árvores (agora comparando Strings)
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
            // --- CABEÇALHO ---
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
                const SizedBox(width: 8),
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
            
            // FILTROS DE CÓDIGO (Chips Dinâmicos)
            Wrap(
              spacing: 6.0,
              runSpacing: 6.0,
              children: _codigosUnicos.map((codigo) {
                final isSelected = _codigosVisiveis.contains(codigo);
                final color = _getColorForCodigo(codigo);
                return FilterChip(
                  label: Text(codigo), // Exibe a Sigla
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
                              
                              // Encontra qual árvore corresponde ao ponto tocado
                              final spotIndex = spots.indexWhere((spot) => spot.x == touchedSpot.x && spot.y == touchedSpot.y);
                              if (spotIndex < 0) return null;
                              
                              final arvoreTocada = arvoresFiltradas[spotIndex];
                              return ScatterTooltipItem(
                                '${arvoreTocada.codigo}\nCAP: ${arvoreTocada.cap}\nAlt: ${touchedSpot.y}',
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
// lib/widgets/grafico_dispersao_cap_altura.dart (VERSÃO DEFINITIVA PARA FL_CHART ^1.0.0)

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

  // Mapeia cada código para uma cor específica
  Color _getColorForCodigo(Codigo codigo) {
    switch (codigo) {
      case Codigo.Normal: return Colors.green;
      case Codigo.Quebrada: return Colors.orange;
      case Codigo.Bifurcada: return Colors.blue;
      case Codigo.MortaOuSeca: return Colors.black54;
      case Codigo.Caida: return Colors.brown;
      case Codigo.Fogo: return Colors.red;
      case Codigo.AtaqueMacaco: return Colors.purple;
      case Codigo.Multipla: return const Color.fromRGBO(214, 200, 5, 1);
      case Codigo.AtaqueFormiga: return const Color.fromARGB(255, 6, 7, 80);
      case Codigo.PragasOuDoencas: return Colors.teal;
      case Codigo.Dominada: return Colors.cyan;
      case Codigo.Geada: return Colors.lightBlueAccent;
      case Codigo.VespaMadeira: return Colors.amber;
      case Codigo.Rebrota: return Colors.lightGreen;
      case Codigo.Torta: return Colors.indigo;
      case Codigo.FoxTail: return Colors.pink;
      case Codigo.FeridaBase: return Colors.grey;
      case Codigo.PonteiraSeca: return Colors.lime;
      case Codigo.Outro: return const Color.fromARGB(255, 219, 132, 1);
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filtra as árvores com base nos filtros ativos e no eixo Y selecionado
    final arvoresFiltradas = widget.arvores.where((arvore) {
      final hasData = arvore.cap > 0 &&
          (_eixoYSelecionado == EixoYDispersao.alturaTotal
              ? (arvore.altura ?? 0) > 0
              : (arvore.alturaDano ?? 0) > 0);
      return _codigosVisiveis.contains(arvore.codigo) && hasData;
    }).toList();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dispersão CAP vs. Altura', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),

            // SELETOR DO EIXO Y
            SegmentedButton<EixoYDispersao>(
              segments: const [
                ButtonSegment(value: EixoYDispersao.alturaTotal, label: Text('Altura Total'), icon: Icon(Icons.height)),
                ButtonSegment(value: EixoYDispersao.alturaDano, label: Text('Altura Dano'), icon: Icon(Icons.warning_amber_outlined)),
              ],
              selected: {_eixoYSelecionado},
              onSelectionChanged: (newSelection) {
                setState(() => _eixoYSelecionado = newSelection.first);
              },
            ),
            const SizedBox(height: 16),
            
            // FILTROS DE CÓDIGO
            Text('Filtrar por Código:', style: Theme.of(context).textTheme.titleSmall),
            Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: _codigosUnicos.map((codigo) {
                return FilterChip(
                  label: Text(codigo.name),
                  selected: _codigosVisiveis.contains(codigo),
                  onSelected: (isSelected) {
                    setState(() {
                      if (isSelected) {
                        _codigosVisiveis.add(codigo);
                      } else {
                        _codigosVisiveis.remove(codigo);
                      }
                    });
                  },
                  backgroundColor: _getColorForCodigo(codigo).withOpacity(0.1),
                  selectedColor: _getColorForCodigo(codigo).withOpacity(0.4),
                  checkmarkColor: Colors.black,
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            
            // GRÁFICO
            AspectRatio(
              aspectRatio: 1.5,
              child: arvoresFiltradas.isEmpty
                  ? const Center(child: Text("Nenhum dado para exibir com os filtros atuais."))
                  : ScatterChart(
                      ScatterChartData(
                        scatterSpots: arvoresFiltradas.mapIndexed((index, arvore) {
                          return ScatterSpot(
                            arvore.cap, // Eixo X
                            _eixoYSelecionado == EixoYDispersao.alturaTotal
                                ? arvore.altura!
                                : arvore.alturaDano!, // Eixo Y
                            dotPainter: FlDotCirclePainter(
                              radius: 4,
                              color: _getColorForCodigo(arvore.codigo),
                            ),
                          );
                        }).toList(),
                        
                        // Títulos dos eixos
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            axisNameWidget: const Text("CAP (cm)"),
                            sideTitles: SideTitles(showTitles: true, reservedSize: 30, interval: 20),
                          ),
                          leftTitles: AxisTitles(
                            axisNameWidget: Text(_eixoYSelecionado == EixoYDispersao.alturaTotal ? "Altura (m)" : "Altura Dano (m)"),
                            sideTitles: SideTitles(showTitles: true, reservedSize: 40, interval: 5),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        
                        // Grid e Bordas
                        gridData: FlGridData(
                          show: true,
                          drawHorizontalLine: true,
                          drawVerticalLine: true,
                          horizontalInterval: 5,
                          verticalInterval: 20,
                          getDrawingHorizontalLine: (value) => const FlLine(color: Colors.black12, strokeWidth: 1),
                          getDrawingVerticalLine: (value) => const FlLine(color: Colors.black12, strokeWidth: 1),
                        ),
                        borderData: FlBorderData(show: true, border: Border.all(color: Colors.black26)),
                        
                        // <<< INÍCIO DA CORREÇÃO FINAL >>>
                        scatterTouchData: ScatterTouchData(
                          enabled: true,
                          handleBuiltInTouches: true,
                          touchTooltipData: ScatterTouchTooltipData(
                            getTooltipColor: (_) => Colors.black,
                            getTooltipItems: (touchedSpot) {
                              // Encontra o índice do ponto tocado comparando com a lista de spots
                              final spots = arvoresFiltradas.mapIndexed((index, arvore) {
                                return ScatterSpot(
                                  arvore.cap,
                                  _eixoYSelecionado == EixoYDispersao.alturaTotal
                                      ? arvore.altura!
                                      : arvore.alturaDano!,
                                  dotPainter: FlDotCirclePainter(
                                    radius: 4,
                                    color: _getColorForCodigo(arvore.codigo),
                                  ),
                                );
                              }).toList();
                              
                              final spotIndex = spots.indexWhere((spot) => 
                                spot.x == touchedSpot.x && spot.y == touchedSpot.y);
                              
                              if (spotIndex < 0 || spotIndex >= arvoresFiltradas.length) {
                                return null;
                              }
                              
                              final arvoreTocada = arvoresFiltradas[spotIndex];
                              final yValue = _eixoYSelecionado == EixoYDispersao.alturaTotal
                                  ? arvoreTocada.altura!.toStringAsFixed(1)
                                  : arvoreTocada.alturaDano!.toStringAsFixed(1);

                              return ScatterTooltipItem(
                                'CAP: ${arvoreTocada.cap.toStringAsFixed(1)}\n'
                                '${_eixoYSelecionado == EixoYDispersao.alturaTotal ? "Altura" : "A. Dano"}: $yValue\n'
                                'Código: ${arvoreTocada.codigo.name}',
                                textStyle: const TextStyle(color: Colors.white, fontSize: 12),
                                bottomMargin: 10,
                              );
                            },
                          ),
                        ),
                        // <<< FIM DA CORREÇÃO FINAL >>>
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
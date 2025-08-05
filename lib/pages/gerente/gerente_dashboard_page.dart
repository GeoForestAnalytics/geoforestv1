// lib/pages/gerente/gerente_dashboard_page.dart (VERSÃO COMPLETA COM TODAS AS TABELAS)

import 'package:flutter/material.dart';
// O import do parcela_model não é mais necessário aqui diretamente
import 'package:geoforestv1/models/parcela_model.dart'; 
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

class GerenteDashboardPage extends StatefulWidget {
  const GerenteDashboardPage({super.key});

  @override
  State<GerenteDashboardPage> createState() => _GerenteDashboardPageState();
}

class _GerenteDashboardPageState extends State<GerenteDashboardPage> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GerenteProvider>().iniciarMonitoramento();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GerenteProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.error != null) {
          return Center(child: Text('Ocorreu um erro:\n${provider.error}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)));
        }
        
        final totalPlanejado = provider.parcelasFiltradas.length;
        final concluidas = provider.parcelasFiltradas.where((p) => p.status == StatusParcela.concluida).length;
        final progressoGeral = totalPlanejado > 0 ? concluidas / totalPlanejado : 0.0;
        
        return Scaffold(
          body: RefreshIndicator(
            onRefresh: () async => context.read<GerenteProvider>().iniciarMonitoramento(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 90.0),
              children: [
                _buildMultiSelectProjectFilter(context, provider),
                const SizedBox(height: 16),
                
                _buildSummaryCard(
                  context: context,
                  title: 'Progresso Inventário',
                  value: '${(progressoGeral * 100).toStringAsFixed(0)}%',
                  subtitle: '$concluidas de $totalPlanejado parcelas concluídas',
                  progress: progressoGeral,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),

                if (provider.progressoPorEquipe.isNotEmpty)
                  _buildRadarChartCard(context, provider.progressoPorEquipe),
                const SizedBox(height: 24),
                
                if (provider.coletasPorMes.isNotEmpty)
                  _buildBarChartWithTrendLineCard(context, provider.coletasPorMes),
                const SizedBox(height: 24),
                
                if (provider.desempenhoPorFazenda.isNotEmpty)
                  _buildFazendaDataTableCard(context, provider.desempenhoPorFazenda),
                
                // Adiciona a nova tabela de cubagem, se houver dados
                if (provider.desempenhoPorCubagem.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildCubagemDataTableCard(context, provider.desempenhoPorCubagem),
                ],
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.pushNamed(context, '/gerente_map'),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Mapa Geral'),
          ),
        );
      },
    );
  }

  // ===================================================================
  // MÉTODOS AUXILIARES DE CONSTRUÇÃO DE WIDGETS
  // ===================================================================

  Widget _buildMultiSelectProjectFilter(BuildContext context, GerenteProvider provider) {
    String displayText;
    if (provider.selectedProjetoIds.isEmpty) {
      displayText = 'Todos os Projetos';
    } else if (provider.selectedProjetoIds.length == 1) {
      try {
        displayText = provider.projetosDisponiveis.firstWhere((p) => p.id == provider.selectedProjetoIds.first).nome;
      } catch (e) {
        displayText = '1 projeto selecionado';
      }
    } else {
      displayText = '${provider.selectedProjetoIds.length} projetos selecionados';
    }
    
    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (dialogContext) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  title: const Text('Filtrar por Projeto'),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: ListView(
                      shrinkWrap: true,
                      children: provider.projetosDisponiveis.map((projeto) {
                        return CheckboxListTile(
                          title: Text(projeto.nome),
                          value: provider.selectedProjetoIds.contains(projeto.id),
                          onChanged: (bool? value) {
                            provider.toggleProjetoSelection(projeto.id!);
                            setDialogState(() {});
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        provider.clearProjetoSelection();
                        Navigator.of(dialogContext).pop();
                      },
                      child: const Text('Limpar (Todos)'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Aplicar'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Expanded(child: Text(displayText, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({required BuildContext context, required String title, required String value, required String subtitle, required double progress, required Color color}) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Flexible(child: Text(title, style: Theme.of(context).textTheme.titleLarge, overflow: TextOverflow.ellipsis)),
              Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress, minHeight: 6, borderRadius: BorderRadius.circular(3), backgroundColor: color.withOpacity(0.2), valueColor: AlwaysStoppedAnimation<Color>(color)),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarChartCard(BuildContext context, Map<String, int> data) {
    if (data.length < 3) {
      return Card(
        elevation: 2,
        child: Container(
          padding: const EdgeInsets.all(16.0),
          height: 350,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Desempenho por Equipe", style: Theme.of(context).textTheme.titleLarge),
              const Expanded(
                child: Center(
                  child: Text(
                    'Dados insuficientes para gerar o gráfico.\n(São necessárias no mínimo 3 equipes com dados)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final entries = data.entries.toList();
    final dataSets = [
      RadarDataSet(
        fillColor: Colors.teal.withOpacity(0.4),
        borderColor: Colors.teal,
        borderWidth: 2,
        entryRadius: 3,
        dataEntries: entries.map((e) => RadarEntry(value: e.value.toDouble())).toList(),
      ),
    ];

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text("Desempenho por Equipe", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            SizedBox(
              height: 250,
              child: RadarChart(
                RadarChartData(
                  dataSets: dataSets,
                  radarBackgroundColor: Colors.transparent,
                  borderData: FlBorderData(show: false),
                  radarBorderData: const BorderSide(color: Colors.grey, width: 1),
                  getTitle: (index, angle) {
                    if (index >= entries.length) return const RadarChartTitle(text: '');
                    return RadarChartTitle(text: entries[index].key);
                  },
                  titleTextStyle: const TextStyle(color: Colors.black, fontSize: 12),
                  tickCount: 5,
                  ticksTextStyle: const TextStyle(color: Colors.grey, fontSize: 10),
                  tickBorderData: const BorderSide(color: Colors.grey, width: 1),
                  gridBorderData: const BorderSide(color: Colors.grey, width: 1),
                  radarShape: RadarShape.polygon,
                ),
                swapAnimationDuration: const Duration(milliseconds: 400),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChartWithTrendLineCard(BuildContext context, Map<String, int> data) {
    final entries = data.entries.toList();
    final barGroups = entries.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [BarChartRodData(toY: entry.value.value.toDouble(), color: Colors.indigo, borderRadius: BorderRadius.circular(4))],
      );
    }).toList();

    final double media = data.values.isEmpty ? 0 : data.values.reduce((a, b) => a + b) / data.values.length;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text("Coletas Concluídas por Mês", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  barGroups: barGroups,
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (double value, TitleMeta meta) {
                          if (value.toInt() >= entries.length) return const SizedBox.shrink();
                          final String text = entries[value.toInt()].key;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(text, style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                  ),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: media,
                        color: Colors.red.withOpacity(0.8),
                        strokeWidth: 2,
                        dashArray: [10, 5],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          padding: const EdgeInsets.only(right: 5, bottom: 5),
                          labelResolver: (line) => 'Média: ${line.y.toStringAsFixed(1)}',
                          style: TextStyle(color: Colors.red.withOpacity(0.8), fontWeight: FontWeight.bold),
                        )
                      ),
                    ],
                  )
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFazendaDataTableCard(BuildContext context, List<DesempenhoFazenda> data) {
    return Card(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: Text("Desempenho por Fazenda (Inventário)", style: Theme.of(context).textTheme.titleLarge),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 20.0,
              headingRowColor: MaterialStateProperty.all(Colors.grey.shade200),
              columns: const [
                DataColumn(label: Text('Fazenda', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Pendentes'), numeric: true),
                DataColumn(label: Text('Iniciadas'), numeric: true),
                DataColumn(label: Text('Concluídas'), numeric: true),
                DataColumn(label: Text('Exportadas'), numeric: true),
                DataColumn(label: Text('Total', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
              ],
              rows: data.map((d) => DataRow(
                cells: [
                  DataCell(Text(d.nome, style: const TextStyle(fontWeight: FontWeight.w500))),
                  DataCell(Text(d.pendentes.toString())),
                  DataCell(Text(d.emAndamento.toString())),
                  DataCell(Text(d.concluidas.toString())),
                  DataCell(Text(d.exportadas.toString())),
                  DataCell(Text(d.total.toString(), style: const TextStyle(fontWeight: FontWeight.w500))),
                ]
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCubagemDataTableCard(BuildContext context, List<DesempenhoCubagem> data) {
  return Card(
    elevation: 2,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
          child: Text("Produção de Cubagem por Talhão", style: Theme.of(context).textTheme.titleLarge),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 20.0,
            headingRowColor: MaterialStateProperty.all(Colors.grey.shade200),
            columns: const [
              DataColumn(label: Text('Fazenda / Talhão', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Pendentes'), numeric: true),
              DataColumn(label: Text('Concluídas'), numeric: true),
              DataColumn(label: Text('Exportadas'), numeric: true),
              DataColumn(label: Text('Total', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            ],
            rows: data.map((d) => DataRow(
              cells: [
                DataCell(Text(d.nome, style: const TextStyle(fontWeight: FontWeight.w500))),
                DataCell(Text(d.pendentes.toString())),
                DataCell(Text(d.concluidas.toString())),
                DataCell(Text(d.exportadas.toString())),
                DataCell(Text(d.total.toString(), style: const TextStyle(fontWeight: FontWeight.w500))),
              ]
            )).toList(),
          ),
        ),
      ],
    ),
  );
}
}
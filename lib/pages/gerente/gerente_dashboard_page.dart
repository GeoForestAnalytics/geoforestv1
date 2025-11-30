// lib/pages/gerente/gerente_dashboard_page.dart (VERSÃO FINAL E COMPLETA)

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geoforestv1/services/export_service.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:geoforestv1/providers/dashboard_filter_provider.dart';
import 'package:geoforestv1/providers/dashboard_metrics_provider.dart';

class GerenteDashboardPage extends StatefulWidget {
  const GerenteDashboardPage({super.key});

  @override
  State<GerenteDashboardPage> createState() => _GerenteDashboardPageState();
}

class _GerenteDashboardPageState extends State<GerenteDashboardPage> {
  final _exportService = ExportService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GerenteProvider>().iniciarMonitoramento();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<GerenteProvider, DashboardFilterProvider, DashboardMetricsProvider>(
      builder: (context, gerenteProvider, filterProvider, metricsProvider, child) {
        
        if (gerenteProvider.isLoading && metricsProvider.parcelasFiltradas.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (gerenteProvider.error != null) {
          return Center(
              child: Text('Ocorreu um erro:\n${gerenteProvider.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)));
        }
        
        // Aplica o filtro de fazenda aqui para os cálculos visuais do dashboard
        final parcelasParaDashboard = filterProvider.selectedFazendaNomes.isNotEmpty
            ? metricsProvider.parcelasFiltradas.where((p) => p.nomeFazenda != null && filterProvider.selectedFazendaNomes.contains(p.nomeFazenda!)).toList()
            : metricsProvider.parcelasFiltradas;
            
        final totalPlanejado = parcelasParaDashboard.length;
        final concluidas = parcelasParaDashboard
            .where((p) => p.status == StatusParcela.concluida || p.status == StatusParcela.exportada)
            .length;
        final progressoGeral =
            totalPlanejado > 0 ? concluidas / totalPlanejado : 0.0;
        
        final projetosDisponiveis = filterProvider.projetosDisponiveis.where((p) => p.status == 'ativo').toList();

        return RefreshIndicator(
          onRefresh: () async => context.read<GerenteProvider>().iniciarMonitoramento(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0),
            children: [
              _buildMultiSelectProjectFilter(context, filterProvider, projetosDisponiveis),
              const SizedBox(height: 8),
              _buildMultiSelectFazendaFilter(context, filterProvider),
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
              if (metricsProvider.progressoPorEquipe.isNotEmpty)
                _buildRadialGaugesCard(context, metricsProvider.progressoPorEquipe),
              const SizedBox(height: 24),
              if (metricsProvider.coletasPorMes.isNotEmpty)
                _buildBarChartWithTrendLineCard(context, metricsProvider.coletasPorMes),
              const SizedBox(height: 24),
              if (metricsProvider.desempenhoPorFazenda.isNotEmpty)
                _buildFazendaDataTableCard(context, metricsProvider.desempenhoPorFazenda),
              if (metricsProvider.desempenhoPorCubagem.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildCubagemDataTableCard(context, metricsProvider.desempenhoPorCubagem),
              ],
              const SizedBox(height: 32),
              ElevatedButton.icon(
                // <<< CORREÇÃO: Passa os filtros de projeto para a função de exportação >>>
                onPressed: () {
                  final Set<int> projetosFiltrados = filterProvider.selectedProjetoIds;
                  _exportService.exportarDesenvolvimentoEquipes(context,
                      projetoIdsFiltrados: projetosFiltrados.isNotEmpty ? projetosFiltrados : null);
                },
                icon: const Icon(Icons.download_outlined),
                label: const Text('Exportar Desenvolvimento das Equipes'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/gerente_map'),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Mapa Geral'),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMultiSelectProjectFilter(BuildContext context,
      DashboardFilterProvider provider, List<Projeto> projetosDisponiveis) {
    String displayText;
    if (provider.selectedProjetoIds.isEmpty) {
      displayText = 'Todos os Projetos';
    } else if (provider.selectedProjetoIds.length == 1) {
      try {
        displayText = projetosDisponiveis
            .firstWhere((p) => p.id == provider.selectedProjetoIds.first)
            .nome;
      } catch (e) {
        displayText = '1 projeto selecionado';
      }
    } else {
      displayText =
          '${provider.selectedProjetoIds.length} projetos selecionados';
    }

    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (dialogContext) {
            return Consumer<DashboardFilterProvider>(
              builder: (context, filterProvider, _) {
                return AlertDialog(
                  title: const Text('Filtrar por Projeto'),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: ListView(
                      shrinkWrap: true,
                      children: projetosDisponiveis.map((projeto) {
                        return CheckboxListTile(
                          title: Text(projeto.nome),
                          value: filterProvider.selectedProjetoIds
                              .contains(projeto.id),
                          onChanged: (bool? value) {
                            context
                                .read<DashboardFilterProvider>()
                                .toggleProjetoSelection(projeto.id!);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        context
                            .read<DashboardFilterProvider>()
                            .clearProjetoSelection();
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

  Widget _buildMultiSelectFazendaFilter(BuildContext context, DashboardFilterProvider provider) {
    if (provider.fazendasDisponiveis.isEmpty) {
      return const SizedBox.shrink();
    }

    String displayText;
    if (provider.selectedFazendaNomes.isEmpty) {
      displayText = 'Todas as Fazendas';
    } else if (provider.selectedFazendaNomes.length == 1) {
      displayText = provider.selectedFazendaNomes.first;
    } else {
      displayText = '${provider.selectedFazendaNomes.length} fazendas selecionadas';
    }

    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (dialogContext) {
            return Consumer<DashboardFilterProvider>(
              builder: (context, filterProvider, _) {
                return AlertDialog(
                  title: const Text('Filtrar por Fazenda'),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: ListView(
                      shrinkWrap: true,
                      children: filterProvider.fazendasDisponiveis.map((nomeFazenda) {
                        return CheckboxListTile(
                          title: Text(nomeFazenda),
                          value: filterProvider.selectedFazendaNomes.contains(nomeFazenda),
                          onChanged: (bool? value) {
                            context.read<DashboardFilterProvider>().toggleFazendaSelection(nomeFazenda);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        context.read<DashboardFilterProvider>().clearFazendaSelection();
                        Navigator.of(dialogContext).pop();
                      },
                      child: const Text('Limpar (Todas)'),
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

  Widget _buildSummaryCard(
      {required BuildContext context,
      required String title,
      required String value,
      required String subtitle,
      required double progress,
      required Color color}) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Flexible(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis)),
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: color, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                backgroundColor: color.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(color)),
          ],
        ),
      ),
    );
  }

  Widget _buildRadialGaugesCard(BuildContext context, Map<String, int> data) {
    if (data.isEmpty) {
      return Card(
        elevation: 2,
        child: Container(
          padding: const EdgeInsets.all(16.0),
          height: 200,
          alignment: Alignment.center,
          child: Text(
            'Não há dados de desempenho por equipe para exibir.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    final maxValue = data.values.reduce((a, b) => a > b ? a : b).toDouble();
    if (maxValue == 0) return const SizedBox.shrink();
    final entries = data.entries.toList();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Desempenho por Equipe",
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.8,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final value = entry.value.toDouble();
                final percentage = (value / maxValue * 100);

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PieChart(
                            PieChartData(
                              startDegreeOffset: -90,
                              sectionsSpace: 0,
                              centerSpaceRadius: 25,
                              sections: [
                                PieChartSectionData(
                                  value: percentage,
                                  color: Theme.of(context).colorScheme.primary,
                                  radius: 8,
                                  showTitle: false,
                                ),
                                PieChartSectionData(
                                  value: 100 - percentage,
                                  color: Colors.grey.shade300,
                                  radius: 8,
                                  showTitle: false,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            entry.value.toString(),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entry.key,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChartWithTrendLineCard(
      BuildContext context, Map<String, int> data) {
    final entries = data.entries.toList();
    final barGroups = entries.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
              toY: entry.value.value.toDouble(),
              color: Colors.indigo,
              borderRadius: BorderRadius.circular(4))
        ],
      );
    }).toList();

    final double media = data.values.isEmpty
        ? 0
        : data.values.reduce((a, b) => a + b) / data.values.length;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text("Coletas Concluídas por Mês",
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                    barGroups: barGroups,
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          getTitlesWidget: (double value, TitleMeta meta) {
                            if (value.toInt() >= entries.length) {
                              return const SizedBox.shrink();
                            }
                            final String text = entries[value.toInt()].key;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(text,
                                  style: const TextStyle(fontSize: 10)),
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
                              padding:
                                  const EdgeInsets.only(right: 5, bottom: 5),
                              labelResolver: (line) =>
                                  'Média: ${line.y.toStringAsFixed(1)}',
                              style: TextStyle(
                                  color: Colors.red.withOpacity(0.8),
                                  fontWeight: FontWeight.bold),
                            )),
                      ],
                    )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFazendaDataTableCard(
      BuildContext context, List<DesempenhoFazenda> data) {
    return Card(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: Text("Desempenho por Fazenda (Inventário)",
                style: Theme.of(context).textTheme.titleLarge),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18.0,
              headingRowColor: MaterialStateProperty.all(Colors.grey.shade200),
              columns: const [
                DataColumn(
                    label: Text('Atividade',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Fazenda',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Pendentes'), numeric: true),
                DataColumn(label: Text('Iniciadas'), numeric: true),
                DataColumn(label: Text('Concluídas'), numeric: true),
                DataColumn(label: Text('Exportadas'), numeric: true),
                DataColumn(
                    label: Text('Total',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    numeric: true),
              ],
              rows: data
                  .map((d) => DataRow(cells: [
                        DataCell(Text(d.nomeAtividade)),
                        DataCell(Text(d.nomeFazenda,
                            style:
                                const TextStyle(fontWeight: FontWeight.w500))),
                        DataCell(Text(d.pendentes.toString())),
                        DataCell(Text(d.emAndamento.toString())),
                        DataCell(Text(d.concluidas.toString())),
                        DataCell(Text(d.exportadas.toString())),
                        DataCell(Text(d.total.toString(),
                            style:
                                const TextStyle(fontWeight: FontWeight.w500))),
                      ]))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCubagemDataTableCard(
      BuildContext context, List<DesempenhoFazenda> data) {
    return Card(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: Text("Desempenho por Fazenda (Cubagem)", // Título corrigido
                style: Theme.of(context).textTheme.titleLarge),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18.0,
              headingRowColor: MaterialStateProperty.all(Colors.grey.shade200),
              // Colunas idênticas à tabela de inventário
              columns: const [
                DataColumn(
                    label: Text('Atividade',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Fazenda',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Pendentes'), numeric: true),
                DataColumn(label: Text('Iniciadas'), numeric: true),
                DataColumn(label: Text('Concluídas'), numeric: true),
                DataColumn(label: Text('Exportadas'), numeric: true),
                DataColumn(
                    label: Text('Total',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    numeric: true),
              ],
              // Mapeamento dos dados para as células da tabela
              rows: data
                  .map((d) => DataRow(cells: [
                        DataCell(Text(d.nomeAtividade)),
                        DataCell(Text(d.nomeFazenda,
                            style:
                                const TextStyle(fontWeight: FontWeight.w500))),
                        DataCell(Text(d.pendentes.toString())),
                        DataCell(Text(d.emAndamento.toString())), // Será sempre 0
                        DataCell(Text(d.concluidas.toString())),
                        DataCell(Text(d.exportadas.toString())),
                        DataCell(Text(d.total.toString(),
                            style:
                                const TextStyle(fontWeight: FontWeight.w500))),
                      ]))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
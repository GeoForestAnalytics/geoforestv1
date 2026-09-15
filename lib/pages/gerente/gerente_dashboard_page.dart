// lib/pages/gerente/gerente_dashboard_page.dart (VERSÃO FINAL E COMPLETA)

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geoforestv1/services/export_service.dart';
import 'package:intl/intl.dart';
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
      context.read<GerenteProvider>().iniciarMonitoramentoEstrutural;
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
            
        final totalParc = parcelasParaDashboard.length;
        final concluidasParc = parcelasParaDashboard
            .where((p) => p.status == StatusParcela.concluida || p.status == StatusParcela.exportada)
            .length;
        final cubTotais = metricsProvider.desempenhoCubagemTotais;
        final totalGeral = totalParc + cubTotais.total;
        final concluidasGeral = concluidasParc + cubTotais.concluidas + cubTotais.exportadas;
        final progressoGeral = totalGeral > 0 ? concluidasGeral / totalGeral : 0.0;
        
        final projetosDisponiveis = filterProvider.projetosDisponiveis.where((p) => p.status == 'ativo').toList();

        return RefreshIndicator(
          onRefresh: () async => context.read<GerenteProvider>().iniciarMonitoramentoEstrutural,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0),
            children: [
              _buildFiltros(context, filterProvider, projetosDisponiveis),
              const SizedBox(height: 12),
              _buildAtividadeCards(context, filterProvider, metricsProvider),
              const SizedBox(height: 12),
              _buildSummaryCard(
                context: context,
                title: 'Progresso Inventário',
                value: '${(progressoGeral * 100).toStringAsFixed(0)}%',
                subtitle: '$concluidasGeral de $totalGeral atividades concluídas',
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

  Widget _buildFiltros(BuildContext context, DashboardFilterProvider fp, List<Projeto> projetosDisponiveis) {
    return Column(children: [
      Row(children: [
        Expanded(child: _buildProjetoChip(context, fp, projetosDisponiveis)),
        const SizedBox(width: 8),
        Expanded(child: _buildChip(
          context: context,
          label: 'Fazenda',
          disponiveis: fp.fazendasDisponiveis,
          selecionados: fp.selectedFazendaNomes,
          onApply: (s) => context.read<DashboardFilterProvider>().setSelectedFazendas(s),
          onClear: () => context.read<DashboardFilterProvider>().clearFazendaSelection(),
        )),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: _buildChip(
          context: context,
          label: 'Talhão',
          disponiveis: fp.talhoesDisponiveis,
          selecionados: fp.selectedTalhaoNomes,
          onApply: (s) => context.read<DashboardFilterProvider>().setSelectedTalhoes(s),
          onClear: () => context.read<DashboardFilterProvider>().clearTalhaoSelection(),
        )),
        const SizedBox(width: 8),
        Expanded(child: _buildPeriodoChip(context, fp)),
      ]),
      const SizedBox(height: 6),
      _buildChip(
        context: context,
        label: 'Líder',
        disponiveis: fp.lideresDisponiveis,
        selecionados: fp.lideresSelecionados,
        onApply: (s) => context.read<DashboardFilterProvider>().setSelectedLideres(s),
        onClear: () => context.read<DashboardFilterProvider>().clearLideresSelection(),
      ),
    ]);
  }

  Widget _buildAtividadeCards(BuildContext context, DashboardFilterProvider fp, DashboardMetricsProvider mp) {
    final atividades = fp.atividadesDisponiveis;
    if (atividades.isEmpty) return const SizedBox.shrink();

    final descrToTipo = <String, String>{
      for (final a in atividades) (a.descricao.isNotEmpty ? a.descricao : a.tipo): a.tipo,
    };

    // Contadores separados: inventário (parcelas) e cubagem
    final totalInvPorTipo = <String, int>{};
    final conclInvPorTipo = <String, int>{};
    for (final d in mp.desempenhoPorFazenda) {
      final tipo = descrToTipo[d.nomeAtividade] ?? d.nomeAtividade;
      totalInvPorTipo[tipo] = (totalInvPorTipo[tipo] ?? 0) + d.total;
      conclInvPorTipo[tipo] = (conclInvPorTipo[tipo] ?? 0) + d.concluidas + d.exportadas;
    }
    final totalCubPorTipo = <String, int>{};
    final conclCubPorTipo = <String, int>{};
    for (final d in mp.desempenhoPorCubagem) {
      final tipo = descrToTipo[d.nomeAtividade] ?? d.nomeAtividade;
      totalCubPorTipo[tipo] = (totalCubPorTipo[tipo] ?? 0) + d.total;
      conclCubPorTipo[tipo] = (conclCubPorTipo[tipo] ?? 0) + d.concluidas + d.exportadas;
    }

    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: atividades.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final a = atividades[i];
          final tipo = a.tipo;
          final nome = a.descricao.isNotEmpty ? a.descricao : a.tipo;
          final totalInv = totalInvPorTipo[tipo] ?? 0;
          final conclInv = conclInvPorTipo[tipo] ?? 0;
          final totalCub = totalCubPorTipo[tipo] ?? 0;
          final conclCub = conclCubPorTipo[tipo] ?? 0;
          final total = totalInv + totalCub;
          final concluidas = conclInv + conclCub;
          final pct = total > 0 ? (concluidas / total).clamp(0.0, 1.0) : null;
          final subLabel = total == 0
              ? '—'
              : totalCub > 0 && totalInv == 0
                  ? '$conclCub / $totalCub árv.'
                  : '$conclInv / $totalInv parc.';
          final sel = fp.selectedAtividadeTipos.contains(tipo);
          return GestureDetector(
            onTap: () {
              final novo = Set<String>.from(fp.selectedAtividadeTipos);
              sel ? novo.remove(tipo) : novo.add(tipo);
              context.read<DashboardFilterProvider>().setSelectedAtividadeTipos(novo);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 148,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: sel ? color.withValues(alpha: 0.14) : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? color : Colors.transparent, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(children: [
                    Icon(Icons.forest_outlined, size: 13, color: color),
                    const SizedBox(width: 4),
                    Expanded(child: Text(nome, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (sel) Icon(Icons.check_circle, size: 12, color: color),
                  ]),
                  const SizedBox(height: 3),
                  Text(subLabel, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  if (pct != null) ...[
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(value: pct, minHeight: 5, backgroundColor: Colors.grey.shade200, color: color),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChip({
    required BuildContext context,
    required String label,
    required List<String> disponiveis,
    required Set<String> selecionados,
    required void Function(Set<String>) onApply,
    required VoidCallback onClear,
  }) {
    if (disponiveis.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          isDense: true,
        ),
        child: const Row(children: [
          Expanded(child: Text('Todos', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13))),
          Icon(Icons.arrow_drop_down, size: 20),
        ]),
      );
    }
    final txt = selecionados.isEmpty
        ? 'Todos'
        : selecionados.length == 1
            ? selecionados.first
            : '${selecionados.length} selecionados';
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        final tmp = Set<String>.from(selecionados);
        showDialog<void>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDlg) => AlertDialog(
              title: Text('Filtrar por $label'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    CheckboxListTile(
                      title: const Text('Todos', style: TextStyle(fontWeight: FontWeight.bold)),
                      value: tmp.isEmpty,
                      onChanged: (_) => setDlg(() => tmp.clear()),
                    ),
                    const Divider(height: 1),
                    ...disponiveis.map((v) => CheckboxListTile(
                          title: Text(v),
                          value: tmp.contains(v),
                          onChanged: (on) => setDlg(() => on == true ? tmp.add(v) : tmp.remove(v)),
                        )),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () { onClear(); Navigator.pop(ctx); }, child: const Text('Limpar')),
                FilledButton(onPressed: () { onApply(tmp); Navigator.pop(ctx); }, child: const Text('Aplicar')),
              ],
            ),
          ),
        );
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          isDense: true,
        ),
        child: Row(children: [
          Expanded(child: Text(txt, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          const Icon(Icons.arrow_drop_down, size: 20),
        ]),
      ),
    );
  }

  Widget _buildProjetoChip(BuildContext context, DashboardFilterProvider fp, List<Projeto> projetosDisponiveis) {
    final txt = fp.selectedProjetoIds.isEmpty
        ? 'Todos'
        : fp.selectedProjetoIds.length == 1
            ? (projetosDisponiveis.where((p) => p.id == fp.selectedProjetoIds.first).firstOrNull?.nome ?? '1 projeto')
            : '${fp.selectedProjetoIds.length} projetos';
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        final tmp = Set<int>.from(fp.selectedProjetoIds);
        showDialog<void>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDlg) => AlertDialog(
              title: const Text('Filtrar por Projeto'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    CheckboxListTile(
                      title: const Text('Todos', style: TextStyle(fontWeight: FontWeight.bold)),
                      value: tmp.isEmpty,
                      onChanged: (_) => setDlg(() => tmp.clear()),
                    ),
                    const Divider(height: 1),
                    ...projetosDisponiveis.map((p) => CheckboxListTile(
                          title: Text(p.nome),
                          value: tmp.contains(p.id),
                          onChanged: (on) => setDlg(() => on == true ? tmp.add(p.id!) : tmp.remove(p.id)),
                        )),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () { context.read<DashboardFilterProvider>().clearProjetoSelection(); Navigator.pop(ctx); },
                  child: const Text('Limpar'),
                ),
                FilledButton(
                  onPressed: () { context.read<DashboardFilterProvider>().setSelectedProjetos(tmp); Navigator.pop(ctx); },
                  child: const Text('Aplicar'),
                ),
              ],
            ),
          ),
        );
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Projeto',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          isDense: true,
        ),
        child: Row(children: [
          Expanded(child: Text(txt, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          const Icon(Icons.arrow_drop_down, size: 20),
        ]),
      ),
    );
  }

  Widget _buildPeriodoChip(BuildContext context, DashboardFilterProvider fp) {
    String label = fp.periodo.displayName;
    if (fp.periodo == PeriodoFiltro.personalizado && fp.periodoPersonalizado != null) {
      final fmt = DateFormat('dd/MM');
      label = '${fmt.format(fp.periodoPersonalizado!.start)} – ${fmt.format(fp.periodoPersonalizado!.end)}';
    }
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final picked = await showModalBottomSheet<PeriodoFiltro>(
          context: context,
          builder: (_) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Período', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              for (final p in PeriodoFiltro.values)
                ListTile(
                  title: Text(p.displayName),
                  trailing: fp.periodo == p ? const Icon(Icons.check, color: Colors.green) : null,
                  onTap: () => Navigator.pop(context, p),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
        if (picked == null || !context.mounted) return;
        if (picked == PeriodoFiltro.personalizado) {
          final range = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2020),
            lastDate: DateTime.now(),
            initialDateRange: fp.periodoPersonalizado,
          );
          if (range != null && context.mounted) {
            context.read<DashboardFilterProvider>().setPeriodo(PeriodoFiltro.personalizado, personalizado: range);
          }
        } else {
          context.read<DashboardFilterProvider>().setPeriodo(picked);
        }
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Período',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          isDense: true,
        ),
        child: Row(children: [
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
          const Icon(Icons.arrow_drop_down, size: 20),
        ]),
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
                backgroundColor: color.withValues(alpha: 0.2),
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
                            color: Colors.red.withValues(alpha: 0.8),
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
                                  color: Colors.red.withValues(alpha: 0.8),
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
              headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
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
              headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
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
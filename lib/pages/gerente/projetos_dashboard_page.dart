// lib/pages/gerente/projetos_dashboard_page.dart

import 'dart:math'; 
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/providers/dashboard_filter_provider.dart';
import 'package:geoforestv1/providers/dashboard_metrics_provider.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geoforestv1/providers/operacoes_provider.dart';
import 'package:geoforestv1/services/export_service.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:geoforestv1/widgets/ranking_detalhado_chart.dart'; // Import do widget do gráfico

class ProjetosDashboardPage extends StatefulWidget {
  const ProjetosDashboardPage({super.key});

  @override
  State<ProjetosDashboardPage> createState() => _ProjetosDashboardPageState();
}

class _ProjetosDashboardPageState extends State<ProjetosDashboardPage> {
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
    return Consumer4<GerenteProvider, DashboardFilterProvider,
        DashboardMetricsProvider, OperacoesProvider>(
      builder: (context, gerenteProvider, filterProvider, metricsProvider,
          operacoesProvider, child) {
        if (gerenteProvider.isLoading &&
            metricsProvider.parcelasFiltradas.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (gerenteProvider.error != null) {
          return Center(
              child: Text('Ocorreu um erro:\n${gerenteProvider.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)));
        }

        final totalPlanejado = metricsProvider.parcelasFiltradas.length;
        final concluidas = metricsProvider.parcelasFiltradas
            .where((p) =>
                p.status == StatusParcela.concluida ||
                p.status == StatusParcela.exportada)
            .length;
        final progressoGeral =
            totalPlanejado > 0 ? concluidas / totalPlanejado : 0.0;

        return RefreshIndicator(
          onRefresh: () async =>
              context.read<GerenteProvider>().iniciarMonitoramento(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0),
            children: [
              _buildFiltros(context),
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
              _buildKpiGrid(context, metricsProvider),
              const SizedBox(height: 24),
              
              // Mantemos o ranking textual caso queira ver mais detalhes rápidos
              if (metricsProvider.progressoPorEquipe.isNotEmpty)
                _buildRankingCard(context, metricsProvider.progressoPorEquipe),
              
              const SizedBox(height: 24),
              if (metricsProvider.coletasPorAtividade.isNotEmpty)
                _buildColetasPorAtividadeChartCard(
                    context, metricsProvider.coletasPorAtividade),
              const SizedBox(height: 24),
              if (metricsProvider.desempenhoPorFazenda.isNotEmpty)
                _buildFazendaDataTableCard(
                    context,
                    metricsProvider.desempenhoPorFazenda,
                    metricsProvider.desempenhoInventarioTotais),
              if (metricsProvider.desempenhoPorCubagem.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildCubagemDataTableCard(
                    context,
                    metricsProvider.desempenhoPorCubagem,
                    metricsProvider.desempenhoCubagemTotais),
              ],
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  final Set<int> projetosFiltrados =
                      filterProvider.selectedProjetoIds;
                  _exportService.exportarDesenvolvimentoEquipes(context,
                      projetoIdsFiltrados:
                          projetosFiltrados.isNotEmpty ? projetosFiltrados : null);
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
                onPressed: () {
                  context.read<DashboardFilterProvider>().clearAllFilters();
                  context.push('/gerente_map'); 
                },
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

  // --- FILTROS ---

  Widget _buildFiltros(BuildContext context) {
    final filterProvider = context.watch<DashboardFilterProvider>();
    return Card(
      margin: EdgeInsets.zero,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildMultiSelectProjectFilter(context, filterProvider),
            const SizedBox(height: 8),
            _buildMultiSelectAtividadeFilter(context, filterProvider),
            const SizedBox(height: 8),
            _buildMultiSelectFazendaFilter(context, filterProvider),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16.0, 
              runSpacing: 12.0, 
              children: [
                _buildPeriodoDropdown(context),
                _buildLiderDropdown(context),
              ],
            ),
            if (filterProvider.periodo == PeriodoFiltro.personalizado)
              _buildDatePicker(context),
          ],
        ),
      ),
    );
  }

  Widget _buildMultiSelectProjectFilter(
      BuildContext context, DashboardFilterProvider provider) {
    final projetosDisponiveis =
        provider.projetosDisponiveis.where((p) => p.status == 'ativo').toList();
    String displayText;
    if (provider.selectedProjetoIds.isEmpty) {
      displayText = 'Todos os Projetos';
    } else if (provider.selectedProjetoIds.length == 1) {
      displayText = projetosDisponiveis.firstWhere(
          (p) => p.id == provider.selectedProjetoIds.first,
          orElse: () => Projeto(
              nome: '1 projeto',
              empresa: '',
              responsavel: '',
              dataCriacao: DateTime.now())).nome;
    } else {
      displayText = '${provider.selectedProjetoIds.length} projetos selecionados';
    }

    return InkWell(
      onTap: () => _showMultiSelectDialog(
        context: context,
        title: 'Filtrar por Projeto',
        items: projetosDisponiveis.map((p) => {'id': p.id, 'label': p.nome}).toList(),
        selectedItems: provider.selectedProjetoIds.map((id) => id as dynamic).toSet(),
        onConfirm: (selected) =>
            context.read<DashboardFilterProvider>().setSelectedProjetos(selected.cast<int>()),
        onClear: () =>
            context.read<DashboardFilterProvider>().clearProjetoSelection(),
      ),
      child: InputDecorator(
        decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0)),
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

  Widget _buildMultiSelectAtividadeFilter(
      BuildContext context, DashboardFilterProvider provider) {
    final tiposDisponiveis = provider.atividadesTiposDisponiveis;
    if (tiposDisponiveis.isEmpty) return const SizedBox.shrink();

    String displayText;
    if (provider.selectedAtividadeTipos.isEmpty) {
      displayText = 'Todas as Atividades';
    } else if (provider.selectedAtividadeTipos.length == 1) {
      displayText = provider.selectedAtividadeTipos.first;
    } else {
      displayText =
          '${provider.selectedAtividadeTipos.length} atividades selecionadas';
    }

    return InkWell(
      onTap: () => _showMultiSelectDialog(
        context: context,
        title: 'Filtrar por Atividade',
        items: tiposDisponiveis
            .map((tipo) => {'id': tipo, 'label': tipo})
            .toList(),
        selectedItems: provider.selectedAtividadeTipos,
        onConfirm: (selected) => context
            .read<DashboardFilterProvider>()
            .setSelectedAtividadeTipos(selected.cast<String>()),
        onClear: () =>
            context.read<DashboardFilterProvider>().clearAtividadeTipoSelection(),
      ),
      child: InputDecorator(
        decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0)),
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

  Widget _buildMultiSelectFazendaFilter(
      BuildContext context, DashboardFilterProvider provider) {
    if (provider.fazendasDisponiveis.isEmpty) return const SizedBox.shrink();

    String displayText;
    if (provider.selectedFazendaNomes.isEmpty) {
      displayText = 'Todas as Fazendas';
    } else if (provider.selectedFazendaNomes.length == 1) {
      displayText = provider.selectedFazendaNomes.first;
    } else {
      displayText =
          '${provider.selectedFazendaNomes.length} fazendas selecionadas';
    }

    return InkWell(
      onTap: () => _showMultiSelectDialog(
        context: context,
        title: 'Filtrar por Fazenda',
        items: provider.fazendasDisponiveis
            .map((nome) => {'id': nome, 'label': nome})
            .toList(),
        selectedItems: provider.selectedFazendaNomes,
        onConfirm: (selected) => context
            .read<DashboardFilterProvider>()
            .setSelectedFazendas(selected.cast<String>()),
        onClear: () =>
            context.read<DashboardFilterProvider>().clearFazendaSelection(),
      ),
      child: InputDecorator(
        decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0)),
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

  Widget _buildPeriodoDropdown(BuildContext context) {
    final filterProvider = context.watch<DashboardFilterProvider>();
    return DropdownButtonFormField<PeriodoFiltro>(
      value: filterProvider.periodo,
      decoration: const InputDecoration(
          labelText: 'Período', border: OutlineInputBorder()),
      items: PeriodoFiltro.values
          .map((p) => DropdownMenuItem(value: p, child: Text(p.displayName)))
          .toList(),
      onChanged: (value) {
        if (value != null) {
          if (value == PeriodoFiltro.personalizado) {
            _selecionarDataPersonalizada(context);
          } else {
            context.read<DashboardFilterProvider>().setPeriodo(value);
          }
        }
      },
    );
  }

  Widget _buildLiderDropdown(BuildContext context) {
    final filterProvider = context.watch<DashboardFilterProvider>();
    final lideresDisponiveis = filterProvider.lideresDisponiveis;

    return DropdownButtonFormField<String>(
      decoration:
          const InputDecoration(labelText: 'Líder', border: OutlineInputBorder()),
      value: filterProvider.lideresSelecionados.isEmpty
          ? null
          : filterProvider.lideresSelecionados.first,
      hint: const Text("Todos"),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text("Todos")),
        ...lideresDisponiveis.map((l) => DropdownMenuItem(value: l, child: Text(l))),
      ],
      onChanged: (value) {
        context.read<DashboardFilterProvider>().setSingleLider(value);
      },
    );
  }

  Future<void> _selecionarDataPersonalizada(BuildContext context) async {
    final filterProvider = context.read<DashboardFilterProvider>();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: filterProvider.periodoPersonalizado,
    );
    if (range != null) {
      filterProvider.setPeriodo(PeriodoFiltro.personalizado,
          personalizado: range);
    }
  }

  Widget _buildDatePicker(BuildContext context) {
    final filterProvider = context.watch<DashboardFilterProvider>();
    final format = DateFormat('dd/MM/yyyy');
    final rangeText = filterProvider.periodoPersonalizado == null
        ? 'Selecione um intervalo'
        : '${format.format(filterProvider.periodoPersonalizado!.start)} - ${format.format(filterProvider.periodoPersonalizado!.end)}';

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: TextButton.icon(
        icon: const Icon(Icons.calendar_today_outlined, size: 16),
        label: Text(rangeText),
        onPressed: () => _selecionarDataPersonalizada(context),
      ),
    );
  }

  void _showMultiSelectDialog({
    required BuildContext context,
    required String title,
    required List<Map<String, dynamic>> items,
    required Set<dynamic> selectedItems,
    required Function(Set<dynamic>) onConfirm,
    required VoidCallback onClear,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final tempSelected = Set.from(selectedItems);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: items.map((item) {
                    return CheckboxListTile(
                      title: Text(item['label']),
                      value: tempSelected.contains(item['id']),
                      onChanged: (bool? value) {
                        setDialogState(() {
                          if (value == true) {
                            tempSelected.add(item['id']);
                          } else {
                            tempSelected.remove(item['id']);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    onClear();
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Limpar (Todos)'),
                ),
                FilledButton(
                  onPressed: () {
                    onConfirm(tempSelected);
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- CARDS E WIDGETS AUXILIARES ---

  Widget _buildSummaryCard({
    required BuildContext context,
    required String title,
    required String value,
    required String subtitle,
    required double progress,
    required Color color,
  }) {
    // <<< CORREÇÃO DE COR PARA O MODO ESCURO >>>
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final valueColor = isDark ? Colors.cyanAccent : color;

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
                      ?.copyWith(color: valueColor, fontWeight: FontWeight.bold)), // Cor ajustada
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

  // Grade de KPIs (2x2)
  Widget _buildKpiGrid(BuildContext context, DashboardMetricsProvider metrics) {
    // <<< CORREÇÃO DE TAMANHO DOS CARDS >>>
    // Usamos SizedBox com altura fixa para forçar uniformidade nas linhas
    const double cardHeight = 160.0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: cardHeight,
                child: _buildTop3KpiCard(context, metrics, Colors.teal),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: cardHeight,
                child: _buildKpiCard(
                  'Amostras Concluídas',
                  metrics.totalAmostrasConcluidas.toString(),
                  Icons.checklist,
                  Colors.blue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: cardHeight,
                child: _buildKpiCard(
                  'Cubagens Concluídas',
                  metrics.totalCubagensConcluidas.toString(),
                  Icons.architecture,
                  Colors.orange,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: cardHeight,
                child: _buildKpiCard(
                  'Média Diária',
                  '${metrics.mediaDiariaColetas.toStringAsFixed(1)} coletas',
                  Icons.show_chart,
                  Colors.purple,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTop3KpiCard(BuildContext context, DashboardMetricsProvider metrics, Color color) {
    final progressoPorEquipe = metrics.progressoPorEquipe;
    final top3 = progressoPorEquipe.entries.take(3).toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => RankingDetalhadoChart(
              parcelas: metrics.parcelasFiltradas,
              cubagens: metrics.cubagensFiltradasRaw,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withOpacity(0.15),
                child: Icon(Icons.military_tech, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Top 3 Equipes',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                          fontSize: 14)),
                  const SizedBox(width: 4),
                  const Icon(Icons.bar_chart, size: 16, color: Colors.grey),
                ],
              ),
              
              const SizedBox(height: 8),
              
              if (top3.isEmpty)
                const Text("-", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))
              else
                Expanded( // Expanded para ocupar o espaço restante uniformemente
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: top3.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final nome = item.key.split(' ').first; 
                      return Text(
                        '${index + 1}. $nome (${item.value})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: index == 0 ? FontWeight.bold : FontWeight.normal,
                          color: index == 0 ? Colors.black87 : Colors.grey[700]
                        ),
                        overflow: TextOverflow.ellipsis,
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color.withOpacity(0.15),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                    fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankingCard(BuildContext context, Map<String, int> data) {
    final entries = data.entries.take(3).toList();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Detalhes do Ranking", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ...entries.asMap().entries.map((entry) {
              final index = entry.key;
              final lider = entry.value.key;
              final contagem = entry.value.value;

              IconData medalIcon;
              Color medalColor;
              switch (index) {
                case 0:
                  medalIcon = Icons.military_tech;
                  medalColor = const Color(0xFFFFD700);
                  break;
                case 1:
                  medalIcon = Icons.military_tech;
                  medalColor = const Color(0xFFC0C0C0);
                  break;
                case 2:
                  medalIcon = Icons.military_tech;
                  medalColor = const Color(0xFFCD7F32);
                  break;
                default:
                  medalIcon = Icons.person;
                  medalColor = Colors.grey;
              }

              return ListTile(
                leading: Icon(medalIcon, color: medalColor, size: 40),
                title: Text(lider,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                trailing: Text('$contagem Coletas',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500)),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildColetasPorAtividadeChartCard(
      BuildContext context, Map<String, int> data) {
    final entries = data.entries.toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final Color corTexto = isDark ? Colors.white70 : const Color(0xFF023853);

    final LinearGradient gradienteBarras = LinearGradient(
      colors: [Colors.cyan.shade300, Colors.blue.shade900],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
    
    double maxY = 0.0;
    if (entries.isNotEmpty) {
      maxY = entries.map((e) => e.value.toDouble()).reduce(max);
    }
    if (maxY == 0) maxY = 1.0;

    final barGroups = entries.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
              toY: entry.value.value.toDouble(),
              gradient: gradienteBarras, 
              width: 18,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6), 
                topRight: Radius.circular(6)
              ),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxY * 1.2,
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200,
              )
          )
        ],
      );
    }).toList();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text("Coletas Concluídas por Atividade",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY * 1.2,
                  barGroups: barGroups,
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (double value, TitleMeta meta) {
                          if (value.toInt() >= entries.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              entries[value.toInt()].key,
                              style: TextStyle(fontSize: 10, color: corTexto, fontWeight: FontWeight.bold),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF1E293B),
                      tooltipMargin: 8,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final atividade = entries[groupIndex].key;
                        final total = entries[groupIndex].value;
                        return BarTooltipItem(
                          '$atividade\n',
                          const TextStyle(
                              color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
                          children: <TextSpan>[
                            TextSpan(
                              text: total.toString(),
                              style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
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

  Widget _buildFazendaDataTableCard(BuildContext context,
      List<DesempenhoFazenda> data, DesempenhoFazendaTotais totais) {
    
    final headerColor = Theme.of(context).colorScheme.primary.withOpacity(0.8);
    final rowColorTotal = Theme.of(context).colorScheme.secondary.withOpacity(0.2);

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
              headingRowColor: MaterialStateProperty.all(headerColor),
              columns: const [
                DataColumn(label: Text('Atividade', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Fazenda', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Pendentes', style: TextStyle(color: Colors.white)), numeric: true),
                DataColumn(label: Text('Iniciadas', style: TextStyle(color: Colors.white)), numeric: true),
                DataColumn(label: Text('Concluídas', style: TextStyle(color: Colors.white)), numeric: true),
                DataColumn(label: Text('Exportadas', style: TextStyle(color: Colors.white)), numeric: true),
                DataColumn(label: Text('Total', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), numeric: true),
              ],
              rows: [
                ...data.map((d) => DataRow(cells: [
                      DataCell(Text(d.nomeAtividade)),
                      DataCell(Text(d.nomeFazenda,
                          style: const TextStyle(fontWeight: FontWeight.w500))),
                      DataCell(Text(d.pendentes.toString())),
                      DataCell(Text(d.emAndamento.toString())),
                      DataCell(Text(d.concluidas.toString())),
                      DataCell(Text(d.exportadas.toString())),
                      DataCell(Text(d.total.toString(),
                          style: const TextStyle(fontWeight: FontWeight.w500))),
                    ])),
                DataRow(
                    color: MaterialStateProperty.all(rowColorTotal),
                    cells: [
                      const DataCell(Text('TOTAL',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                      const DataCell(Text('')),
                      DataCell(Text(totais.pendentes.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(totais.emAndamento.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(totais.concluidas.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(totais.exportadas.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(totais.total.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                    ])
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCubagemDataTableCard(BuildContext context,
      List<DesempenhoFazenda> data, DesempenhoFazendaTotais totais) {
        
    final headerColor = Theme.of(context).colorScheme.primary.withOpacity(0.8);
    final rowColorTotal = Theme.of(context).colorScheme.secondary.withOpacity(0.2);

    return Card(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: Text("Desempenho por Fazenda (Cubagem)",
                style: Theme.of(context).textTheme.titleLarge),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18.0,
              headingRowColor: MaterialStateProperty.all(headerColor),
              columns: const [
                DataColumn(label: Text('Atividade', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Fazenda', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Pendentes', style: TextStyle(color: Colors.white)), numeric: true),
                DataColumn(label: Text('Iniciadas', style: TextStyle(color: Colors.white)), numeric: true),
                DataColumn(label: Text('Concluídas', style: TextStyle(color: Colors.white)), numeric: true),
                DataColumn(label: Text('Exportadas', style: TextStyle(color: Colors.white)), numeric: true),
                DataColumn(label: Text('Total', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), numeric: true),
              ],
              rows: [
                ...data.map((d) => DataRow(cells: [
                      DataCell(Text(d.nomeAtividade)),
                      DataCell(Text(d.nomeFazenda,
                          style: const TextStyle(fontWeight: FontWeight.w500))),
                      DataCell(Text(d.pendentes.toString())),
                      DataCell(Text(d.emAndamento.toString())),
                      DataCell(Text(d.concluidas.toString())),
                      DataCell(Text(d.exportadas.toString())),
                      DataCell(Text(d.total.toString(),
                          style: const TextStyle(fontWeight: FontWeight.w500))),
                    ])),
                DataRow(
                    color: MaterialStateProperty.all(rowColorTotal),
                    cells: [
                      const DataCell(Text('TOTAL',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                      const DataCell(Text('')),
                      DataCell(Text(totais.pendentes.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(totais.emAndamento.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(totais.concluidas.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(totais.exportadas.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(totais.total.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                    ])
              ],
            ),
          ),
        ],
      ),
    );
  }
}
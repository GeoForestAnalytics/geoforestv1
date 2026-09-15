// lib/pages/gerente/projetos_dashboard_page.dart

import 'dart:math'; 
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/models/parcela_model.dart';
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
      // 1. Carrega nomes de projetos e talhões (estrutura)
      context.read<GerenteProvider>().iniciarMonitoramentoEstrutural();
      
      // 2. CARREGA OS DADOS REAIS (Visão Global) para o Dashboard funcionar
      context.read<GerenteProvider>().carregarVisaoGlobalGerente();
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

        final totalParc = metricsProvider.parcelasFiltradas.length;
        final concluidasParc = metricsProvider.parcelasFiltradas
            .where((p) =>
                p.status == StatusParcela.concluida ||
                p.status == StatusParcela.exportada)
            .length;
        final cubTotais = metricsProvider.desempenhoCubagemTotais;
        final totalGeral = totalParc + cubTotais.total;
        final concluidasGeral = concluidasParc + cubTotais.concluidas + cubTotais.exportadas;
        final progressoGeral = totalGeral > 0 ? concluidasGeral / totalGeral : 0.0;

        return RefreshIndicator(
          onRefresh: () async =>
              context.read<GerenteProvider>().iniciarMonitoramentoEstrutural,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0),
            children: [
              _buildFiltros(context),
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
    final fp = context.watch<DashboardFilterProvider>();
    return Column(children: [
      Row(children: [
        Expanded(child: _buildProjetoChip(context, fp)),
        const SizedBox(width: 8),
        Expanded(child: _buildChip(
          context: context, label: 'Fazenda',
          disponiveis: fp.fazendasDisponiveis,
          selecionados: fp.selectedFazendaNomes,
          onApply: (s) => context.read<DashboardFilterProvider>().setSelectedFazendas(s),
          onClear: () => context.read<DashboardFilterProvider>().clearFazendaSelection(),
        )),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: _buildChip(
          context: context, label: 'Talhão',
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
        context: context, label: 'Líder',
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

  Widget _buildProjetoChip(BuildContext context, DashboardFilterProvider fp) {
    final projetos = fp.projetosDisponiveis.where((p) => p.status == 'ativo').toList();
    final txt = fp.selectedProjetoIds.isEmpty
        ? 'Todos'
        : fp.selectedProjetoIds.length == 1
            ? (projetos.where((p) => p.id == fp.selectedProjetoIds.first).firstOrNull?.nome ?? '1 projeto')
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
                child: ListView(shrinkWrap: true, children: [
                  CheckboxListTile(
                    title: const Text('Todos', style: TextStyle(fontWeight: FontWeight.bold)),
                    value: tmp.isEmpty,
                    onChanged: (_) => setDlg(() => tmp.clear()),
                  ),
                  const Divider(height: 1),
                  ...projetos.map((p) => CheckboxListTile(
                    title: Text(p.nome),
                    value: tmp.contains(p.id),
                    onChanged: (on) => setDlg(() => on == true ? tmp.add(p.id!) : tmp.remove(p.id)),
                  )),
                ]),
              ),
              actions: [
                TextButton(onPressed: () { context.read<DashboardFilterProvider>().clearProjetoSelection(); Navigator.pop(ctx); }, child: const Text('Limpar')),
                FilledButton(onPressed: () { context.read<DashboardFilterProvider>().setSelectedProjetos(tmp); Navigator.pop(ctx); }, child: const Text('Aplicar')),
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
                child: ListView(shrinkWrap: true, children: [
                  CheckboxListTile(
                    title: const Text('Todos', style: TextStyle(fontWeight: FontWeight.bold)),
                    value: tmp.isEmpty,
                    onChanged: (_) => setDlg(() => tmp.clear()),
                  ),
                  const Divider(height: 1),
                  ...disponiveis.map((item) => CheckboxListTile(
                    title: Text(item),
                    value: tmp.contains(item),
                    onChanged: (on) => setDlg(() => on == true ? tmp.add(item) : tmp.remove(item)),
                  )),
                ]),
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

  // Grade de KPIs (2x2 + linha de disponibilidade)
  Widget _buildKpiGrid(BuildContext context, DashboardMetricsProvider metrics) {
    const double cardHeight = 160.0;

    final totalNuvem = metrics.parcelasFiltradas.length;
    final paraColeta = metrics.parcelasFiltradas
        .where((p) => p.status == StatusParcela.pendente)
        .length;

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
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: cardHeight,
                child: _buildKpiCard(
                  'Total na Nuvem',
                  totalNuvem.toString(),
                  Icons.cloud,
                  Colors.indigo,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: cardHeight,
                child: _buildKpiCard(
                  'Para Coletar',
                  paraColeta.toString(),
                  Icons.forest,
                  Colors.green,
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
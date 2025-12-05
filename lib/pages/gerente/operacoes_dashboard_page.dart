// lib/pages/gerente/operacoes_dashboard_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
 

import 'package:geoforestv1/providers/operacoes_provider.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:geoforestv1/providers/operacoes_filter_provider.dart';
import 'package:geoforestv1/services/export_service.dart';

class OperacoesDashboardPage extends StatefulWidget {
  const OperacoesDashboardPage({super.key});

  @override
  State<OperacoesDashboardPage> createState() => _OperacoesDashboardPageState();
}

class _OperacoesDashboardPageState extends State<OperacoesDashboardPage> {
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$ ');
  final NumberFormat _numberFormat = NumberFormat.decimalPattern('pt_BR');
  final ExportService _exportService = ExportService();

  String _abbreviate(String key) {
    switch (key) {
      case 'Abastecimento': return 'Abast.';
      case 'Alimentação': return 'Alim.';
      case 'Pedágio': return 'Pedágio';
      case 'Outros': return 'Outros';
      default: return key.length > 5 ? key.substring(0, 5) : key;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<OperacoesProvider>(
      builder: (context, provider, child) {
        final gerenteProvider = context.watch<GerenteProvider>();
        if (gerenteProvider.isLoading && gerenteProvider.diariosSincronizados.isEmpty) {
           return const Center(child: CircularProgressIndicator());
        }
        
        Widget bodyContent;
        if (provider.diariosFiltrados.isEmpty && gerenteProvider.diariosSincronizados.isNotEmpty) {
          bodyContent = const Center(child: Text("Nenhum diário encontrado para os filtros selecionados.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16)));
        } else if (gerenteProvider.diariosSincronizados.isEmpty) {
          bodyContent = const Center(child: Text("Nenhum diário de campo foi sincronizado ainda.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)));
        } else {
           bodyContent = ListView(
            padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
            children: [
              _buildKpiCards(context, provider.kpis),
              const SizedBox(height: 24),
              _buildDespesasChart(context, provider.composicaoDespesas),
              const SizedBox(height: 24),
              _buildCustoVeiculoTable(context, provider.custosPorVeiculo),
              const SizedBox(height: 24),
              // Tabela corrigida (sem Qtd e Unitário)
              _buildHistoricoDiariosTable(context, provider.diariosFiltrados),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.download_outlined),
                label: const Text('Exportar Relatório de Operações'),
                onPressed: () => _showExportOperacoesDialog(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
            ],
          );
        }
        
        return Column(
          children: [
            _buildFiltros(context),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => gerenteProvider.iniciarMonitoramento(),
                child: bodyContent,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFiltros(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 380) {
              return Column(
                children: [
                  _buildPeriodoDropdown(context),
                  const SizedBox(height: 16),
                  _buildLiderDropdown(context),
                  if (context.watch<OperacoesFilterProvider>().periodo == PeriodoFiltro.personalizado)
                    _buildDatePicker(context),
                ],
              );
            } else {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildPeriodoDropdown(context)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildLiderDropdown(context)),
                    ],
                  ),
                  if (context.watch<OperacoesFilterProvider>().periodo == PeriodoFiltro.personalizado)
                    _buildDatePicker(context),
                ],
              );
            }
          },
        ),
      ),
    );
  }
  
  Widget _buildPeriodoDropdown(BuildContext context) {
    final filterProvider = context.watch<OperacoesFilterProvider>();
    return DropdownButtonFormField<PeriodoFiltro>(
      value: filterProvider.periodo,
      decoration: const InputDecoration(labelText: 'Período', border: OutlineInputBorder()),
      items: PeriodoFiltro.values.map((p) => DropdownMenuItem(value: p, child: Text(p.displayName))).toList(),
      onChanged: (value) {
        if (value != null) {
          if (value == PeriodoFiltro.personalizado) {
            _selecionarDataPersonalizada(context);
          } else {
            context.read<OperacoesFilterProvider>().setPeriodo(value);
          }
        }
      },
    );
  }

  Widget _buildLiderDropdown(BuildContext context) {
    final filterProvider = context.watch<OperacoesFilterProvider>();
    final lideresDisponiveis = filterProvider.lideresDisponiveis;
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(labelText: 'Líder', border: OutlineInputBorder()),
      value: filterProvider.lideresSelecionados.isEmpty ? null : filterProvider.lideresSelecionados.first,
      hint: const Text("Todos"),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text("Todos")),
        ...lideresDisponiveis.map((l) => DropdownMenuItem(value: l, child: Text(l))),
      ],
      onChanged: (value) {
        context.read<OperacoesFilterProvider>().setSingleLider(value);
      },
    );
  }

  Future<void> _selecionarDataPersonalizada(BuildContext context) async {
      final filterProvider = context.read<OperacoesFilterProvider>();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange: filterProvider.periodoPersonalizado,
      );
      if (range != null) {
        filterProvider.setPeriodo(PeriodoFiltro.personalizado, personalizado: range);
      }
  }

  Widget _buildDatePicker(BuildContext context) {
    final filterProvider = context.watch<OperacoesFilterProvider>();
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

  Widget _buildKpiCards(BuildContext context, KpiData kpis) {
    return Column(
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildKpiCard('Custo Total', _currencyFormat.format(kpis.custoTotalCampo), Icons.monetization_on, Colors.green)),
            const SizedBox(width: 16),
            Expanded(child: _buildKpiCard('KM Rodados', '${_numberFormat.format(kpis.kmRodados)} km', Icons.directions_car, Colors.blue)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            // Exibe as strings formatadas "150/250"
            Expanded(child: _buildKpiCard('Amostras (Feito/Total)', kpis.progressoAmostras, Icons.checklist, Colors.orange)),
            const SizedBox(width: 16),
            Expanded(child: _buildKpiCard('Cubagens (Feito/Total)', kpis.progressoCubagens, Icons.architecture, Colors.teal)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
           children: [
             Expanded(child: _buildKpiCard('Custo / Coleta Realizada', _currencyFormat.format(kpis.custoPorColeta), Icons.attach_money, Colors.red)),
           ]
        )
      ],
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
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
            Text(
              title, 
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w500, fontSize: 14)
            ),
            const SizedBox(height: 4),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDespesasChart(BuildContext context, Map<String, double> composicaoDespesas) {
    final despesasValidas = Map.fromEntries(
      composicaoDespesas.entries.where((entry) => entry.value > 0)
    );

    if (despesasValidas.isEmpty) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: SizedBox(height: 200, child: Center(child: Text("Nenhuma despesa registrada no período."))),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color corTextoEixo = isDark ? Colors.white70 : const Color(0xFF023853);

    final LinearGradient gradienteBarras = LinearGradient(
      colors: [Colors.cyan.shade300, Colors.blue.shade900],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    double maxY = 0.0;
    if (despesasValidas.isNotEmpty) {
      maxY = despesasValidas.values.reduce((a, b) => a > b ? a : b);
    }
    if (maxY == 0) maxY = 1.0;

    int index = 0;
    final barGroups = despesasValidas.entries.map((entry) {
      final barData = BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: entry.value,
            gradient: gradienteBarras,
            width: 22,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(6),
            ),
            backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxY * 1.2,
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200,
            ),
          ),
        ],
      );
      index++;
      return barData;
    }).toList();
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Composição das Despesas",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY * 1.2,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF1E293B),
                      tooltipMargin: 8,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        String key = despesasValidas.keys.elementAt(group.x.toInt());
                        return BarTooltipItem(
                          '$key\n',
                          const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14),
                          children: <TextSpan>[
                            TextSpan(
                              text: _currencyFormat.format(rod.toY),
                              style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (double value, TitleMeta meta) {
                          if (value.toInt() < despesasValidas.keys.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                _abbreviate(despesasValidas.keys.elementAt(value.toInt())),
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: corTextoEixo),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  barGroups: barGroups,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCustoVeiculoTable(BuildContext context, List<CustoPorVeiculo> custos) {
    if (custos.isEmpty) return const SizedBox.shrink();
    final kpis = context.watch<OperacoesProvider>().kpis;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Custos por Veículo", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Placa')),
                  DataColumn(label: Text('KM Rodados'), numeric: true),
                  DataColumn(label: Text('Custo (R\$)'), numeric: true),
                  DataColumn(label: Text('R\$/KM'), numeric: true),
                ],
                rows: [
                  ...custos.map((c) => DataRow(cells: [
                    DataCell(Text(c.placa)),
                    DataCell(Text(_numberFormat.format(c.kmRodados))),
                    DataCell(Text(_currencyFormat.format(c.custoAbastecimento))),
                    DataCell(Text(_currencyFormat.format(c.custoMedioPorKm))),
                  ])).toList(),
                  DataRow(
                    color: MaterialStateProperty.all(Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5)),
                    cells: [
                      const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(_numberFormat.format(kpis.kmRodados), style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(_currencyFormat.format(kpis.custoTotalAbastecimento), style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(_currencyFormat.format(kpis.custoMedioKmGeral), style: const TextStyle(fontWeight: FontWeight.bold))),
                    ]
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- TABELA ATUALIZADA: REMOVIDO QTD e UNITÁRIO ---
  Widget _buildHistoricoDiariosTable(
    BuildContext context, 
    List<DiarioDeCampo> diarios, 
    // Map<int, int> producaoPorDiario // Não precisa mais deste parâmetro aqui se não for usar
  ) {
    if (diarios.isEmpty) return const SizedBox.shrink();
    final kpis = context.watch<OperacoesProvider>().kpis;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Histórico Diário", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 20.0,
                columns: const [
                  DataColumn(label: Text('Data')),
                  DataColumn(label: Text('Líder')),
                  DataColumn(label: Text('Destino')),
                  // REMOVIDO: DataColumn(label: Text('Qtd'), numeric: true),
                  DataColumn(label: Text('Custo Total'), numeric: true),
                  // REMOVIDO: DataColumn(label: Text('R\$/Unid'), numeric: true),
                ],
                rows: [
                  ...diarios.map((d) {
                    final custoTotalDiario = (d.abastecimentoValor ?? 0) + (d.pedagioValor ?? 0) + (d.alimentacaoRefeicaoValor ?? 0) + (d.outrasDespesasValor ?? 0);
                    
                    return DataRow(cells: [
                      DataCell(Text(DateFormat('dd/MM/yy').format(DateTime.parse(d.dataRelatorio)))),
                      DataCell(Text(d.nomeLider)),
                      DataCell(Text(d.localizacaoDestino ?? '')),
                      // REMOVIDO: Célula de Qtd
                      DataCell(Text(_currencyFormat.format(custoTotalDiario))),
                      // REMOVIDO: Célula de Custo Unitário
                    ]);
                  }).toList(),
                  
                  // LINHA DE TOTAL
                  DataRow(
                    color: MaterialStateProperty.all(Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5)),
                    cells: [
                      DataCell(Text('${diarios.length} DIAS', style: const TextStyle(fontWeight: FontWeight.bold))),
                      const DataCell(Text('')),
                      const DataCell(Text('TOTAL', style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                      
                      // REMOVIDO: Total de Coletas
                      
                      DataCell(Text(_currencyFormat.format(kpis.custoTotalCampo), style: const TextStyle(fontWeight: FontWeight.bold))),
                      
                      // REMOVIDO: Média Geral por Coleta
                    ]
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showExportOperacoesDialog(BuildContext context) async {
    final operacoesProvider = context.read<OperacoesProvider>();
    final gerenteProvider = context.read<GerenteProvider>();

    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Wrap(
          children: [
            const ListTile(title: Text("Exportar Relatório de Operações", style: TextStyle(fontWeight: FontWeight.bold))),
            ListTile(
              leading: const Icon(Icons.filter_alt_outlined),
              title: const Text("Exportar Relatório Filtrado"),
              subtitle: Text("Exporta os dados atualmente exibidos no dashboard (${operacoesProvider.diariosFiltrados.length} registros)."),
              onTap: () {
                Navigator.of(ctx).pop();
                _exportService.exportarOperacoesCsv(
                  context: context,
                  diarios: operacoesProvider.diariosFiltrados,
                  tipoRelatorio: "Filtrado"
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.all_inclusive_outlined),
              title: const Text("Exportar Relatório Completo"),
              subtitle: Text("Exporta todos os diários sincronizados (${gerenteProvider.diariosSincronizados.length} registros)."),
              onTap: () {
                Navigator.of(ctx).pop();
                _exportService.exportarOperacoesCsv(
                  context: context,
                  diarios: gerenteProvider.diariosSincronizados,
                  tipoRelatorio: "Completo"
                );
              },
            ),
          ],
        );
      }
    );
  }
}
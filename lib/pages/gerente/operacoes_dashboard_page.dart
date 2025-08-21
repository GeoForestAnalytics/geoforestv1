// lib/pages/gerente/operacoes_dashboard_page.dart (VERSÃO CORRIGIDA)

import 'package:flutter/material.dart';
import 'package:geoforestv1/providers/gerente_provider.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import 'package:geoforestv1/providers/operacoes_provider.dart';
// <<< CORREÇÃO 1: ADICIONANDO O IMPORT QUE FALTAVA >>>
import 'package:geoforestv1/models/diario_de_campo_model.dart';

/// O novo Dashboard focado na gestão operacional e financeira das equipes de campo.
class OperacoesDashboardPage extends StatefulWidget {
  const OperacoesDashboardPage({super.key});

  @override
  State<OperacoesDashboardPage> createState() => _OperacoesDashboardPageState();
}

class _OperacoesDashboardPageState extends State<OperacoesDashboardPage> {
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final NumberFormat _numberFormat = NumberFormat.decimalPattern('pt_BR');

  @override
  Widget build(BuildContext context) {
    return Consumer<OperacoesProvider>(
      builder: (context, provider, child) {
        
        if (provider.diariosFiltrados.isEmpty && provider.kpis.coletasRealizadas == 0) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Aguardando diários de campo sincronizados..."),
              ],
            ),
          );
        }

        return RefreshIndicator(
          // <<< LÓGICA DO 'TODO' IMPLEMENTADA AQUI >>>
          onRefresh: () => context.read<GerenteProvider>().iniciarMonitoramento(),
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildFiltros(context),
              const SizedBox(height: 16),
              _buildKpiGrid(context, provider.kpis),
              const SizedBox(height: 24),
              _buildDespesasChart(context, provider.composicaoDespesas),
              const SizedBox(height: 24),
              _buildCustoVeiculoTable(context, provider.custosPorVeiculo),
              const SizedBox(height: 24),
              _buildHistoricoDiariosTable(context, provider.diariosFiltrados),
            ],
          ),
        );
      },
    );
  }

  /// Constrói a seção de filtros no topo da tela.
  Widget _buildFiltros(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: const Text("Este Mês"),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Filtro de data a ser implementado.")));
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.groups_outlined),
                label: const Text("Todas as Equipes"),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Filtro de equipe a ser implementado.")));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Constrói a grade de KPIs principais.
  Widget _buildKpiGrid(BuildContext context, KpiData kpis) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildKpiCard(
          context,
          title: "Custo Total",
          value: _currencyFormat.format(kpis.custoTotalCampo),
          icon: Icons.monetization_on_outlined,
          color: Colors.green,
        ),
        _buildKpiCard(
          context,
          title: "KM Rodados",
          value: "${_numberFormat.format(kpis.kmRodados)} km",
          icon: Icons.directions_car_outlined,
          color: Colors.blue,
        ),
        _buildKpiCard(
          context,
          title: "Coletas Realizadas",
          value: _numberFormat.format(kpis.coletasRealizadas),
          icon: Icons.checklist_rtl_outlined,
          color: Colors.orange,
        ),
        _buildKpiCard(
          context,
          title: "Custo / Coleta",
          value: _currencyFormat.format(kpis.custoPorColeta),
          icon: Icons.attach_money_outlined,
          color: Colors.red,
        ),
      ],
    );
  }

  /// Constrói um card de KPI individual.
  Widget _buildKpiCard(BuildContext context, {required String title, required String value, required IconData icon, required Color color}) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)),
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  /// Constrói o gráfico de pizza com a composição das despesas.
  Widget _buildDespesasChart(BuildContext context, Map<String, double> data) {
    final List<PieChartSectionData> sections = [];
    final colors = [Colors.blue, Colors.orange, Colors.red, Colors.purple];
    int colorIndex = 0;

    data.forEach((key, value) {
      if (value > 0) {
        sections.add(PieChartSectionData(
          value: value,
          title: _currencyFormat.format(value),
          color: colors[colorIndex % colors.length],
          radius: 50,
          titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
        ));
        colorIndex++;
      }
    });

    if (sections.isEmpty) return const SizedBox.shrink(); // Não mostra o card se não houver despesas

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Composição das Despesas", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            SizedBox(
              height: 150,
              child: PieChart(PieChartData(sections: sections)),
            ),
            const SizedBox(height: 16),
            ...data.entries.map((entry) {
              if(entry.value <= 0) return const SizedBox.shrink();
              final color = colors[data.keys.toList().indexOf(entry.key) % colors.length];
              return Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Row(
                  children: [
                    Container(width: 12, height: 12, color: color),
                    const SizedBox(width: 8),
                    Text(entry.key),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  /// Constrói a tabela com a análise de custos por veículo.
  Widget _buildCustoVeiculoTable(BuildContext context, List<CustoPorVeiculo> data) {
    if (data.isEmpty) return const SizedBox.shrink(); // Não mostra o card se não houver dados

    return Card(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text("Análise de Custos por Veículo", style: Theme.of(context).textTheme.titleLarge),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Veículo (Placa)')),
                DataColumn(label: Text('KM Rodados'), numeric: true),
                DataColumn(label: Text('Custo Combustível'), numeric: true),
                DataColumn(label: Text('Custo/KM'), numeric: true),
              ],
              rows: data.map((d) => DataRow(
                cells: [
                  DataCell(Text(d.placa)),
                  DataCell(Text(_numberFormat.format(d.kmRodados))),
                  DataCell(Text(_currencyFormat.format(d.custoAbastecimento))),
                  DataCell(Text(_currencyFormat.format(d.custoMedioPorKm))),
                ]
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// Constrói a tabela com o histórico dos últimos diários recebidos.
  Widget _buildHistoricoDiariosTable(BuildContext context, List<DiarioDeCampo> data) {
    if (data.isEmpty) return const SizedBox.shrink(); // Não mostra o card se não houver dados

    return Card(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text("Últimos Relatórios Recebidos", style: Theme.of(context).textTheme.titleLarge),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Data')),
                DataColumn(label: Text('Líder')),
                DataColumn(label: Text('Custo Total'), numeric: true),
                DataColumn(label: Text('Ações')),
              ],
              rows: data.take(10).map((d) {
                // <<< CORREÇÃO 2: Adicionado '?? 0' para segurança contra nulos >>>
                final custoTotal = (d.abastecimentoValor ?? 0) + (d.pedagioValor ?? 0) + (d.alimentacaoRefeicaoValor ?? 0);
                return DataRow(
                  cells: [
                    DataCell(Text(DateFormat('dd/MM/yy').format(DateTime.parse(d.dataRelatorio)))),
                    DataCell(Text(d.nomeLider)),
                    DataCell(Text(_currencyFormat.format(custoTotal))),
                    DataCell(IconButton(
                      icon: const Icon(Icons.visibility_outlined, color: Colors.grey),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Visualização de detalhes a ser implementada.")));
                      },
                    )),
                  ]
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
// lib/pages/dashboard/dashboard_page.dart (VERSÃO COMPLETA E REFATORADA)Text

import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

// --- NOVO IMPORT DO REPOSITÓRIO ---
import 'package:geoforestv1/data/repositories/analise_repository.dart';
// ------------------------------------

// O import do database_helper foi removido.
// import 'package:geoforestv1/data/datasources/local/database_helper.dart';

class DashboardPage extends StatefulWidget {
  final int parcelaId;
  const DashboardPage({super.key, required this.parcelaId});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // --- INSTÂNCIA DO NOVO REPOSITÓRIO ---
  final _analiseRepository = AnaliseRepository();
  // ---------------------------------------

  bool _isLoading = true;
  String _errorMessage = '';

  Map<String, double> _distribuicaoPorCodigo = {};
  List<Map<String, dynamic>> _dadosCAP = []; 

  int _totalFustes = 0; 
  int _totalCovas = 0;
  double _mediaCAP = 0.0;
  double _minCAP = 0.0;
  double _maxCAP = 0.0;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  // --- MÉTODO ATUALIZADO ---
  Future<void> _loadDashboardData() async {
    setState(() { _isLoading = true; _errorMessage = ''; });
    try {
      // Usa o AnaliseRepository
      final results = await Future.wait([
        _analiseRepository.getDistribuicaoPorCodigo(widget.parcelaId),
        _analiseRepository.getValoresCAP(widget.parcelaId),
      ]);

      final codigoData = results[0] as Map<String, double>;
      final capData = results[1] as List<Map<String, dynamic>>;

      if (mounted) {
        setState(() {
          _distribuicaoPorCodigo = codigoData;
          _dadosCAP = capData;
          _calculateKPIs();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao carregar dados do relatório: $e';
          _isLoading = false;
        });
      }
    }
  }

  // O restante do arquivo (lógica de cálculo e widgets de build)
  // não precisa de alterações.

  void _calculateKPIs() {
    _totalFustes = 0;
    _distribuicaoPorCodigo.forEach((key, value) {
      if (key != 'falha' && key != 'caida') {
        _totalFustes += value.toInt();
      }
    });

    _totalCovas = _distribuicaoPorCodigo.values.fold(0, (prev, element) => prev + element.toInt());

    final valoresValidos = _dadosCAP
        .where((dado) => 
            dado['codigo'] != 'falha' && 
            dado['codigo'] != 'caida' && 
            dado['codigo'] != 'morta')
        .map((dado) => dado['cap'] as double)
        .toList();

    if (valoresValidos.isEmpty) {
      _mediaCAP = 0.0;
      _minCAP = 0.0;
      _maxCAP = 0.0;
    } else {
      _mediaCAP = valoresValidos.reduce((a, b) => a + b) / valoresValidos.length;
      _minCAP = valoresValidos.reduce(min);
      _maxCAP = valoresValidos.reduce(max);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Relatório da Parcela ${widget.parcelaId}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadDashboardData,
            tooltip: 'Atualizar Dados',
          )
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage.isNotEmpty) {
      return Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)));
    }
    if (_distribuicaoPorCodigo.isEmpty) {
      return const Center(child: Text("Nenhuma árvore coletada para gerar relatório."));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildKPIs(),
          const SizedBox(height: 24),
          _buildSectionTitle("Distribuição por Código"),
          SizedBox(height: 250, child: _buildCodeBarChart()), 
          const SizedBox(height: 24),
          _buildSectionTitle("Histograma de CAP"),
          SizedBox(height: 300, child: _buildHistogram()),
        ],
      ),
    );
  }
  
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildKPIs() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Wrap(
          alignment: WrapAlignment.spaceAround,
          spacing: 16.0,
          runSpacing: 16.0,
          children: [
            _kpiCard('Total de Covas', _totalCovas.toString(), Icons.grid_on),
            _kpiCard('Total de Fustes', _totalFustes.toString(), Icons.park),
            _kpiCard('Média CAP', '${_mediaCAP.toStringAsFixed(1)} cm', Icons.straighten),
            _kpiCard('Min CAP', '${_minCAP.toStringAsFixed(1)} cm', Icons.arrow_downward),
            _kpiCard('Max CAP', '${_maxCAP.toStringAsFixed(1)} cm', Icons.arrow_upward),
          ],
        ),
      ),
    );
  }

  Widget _kpiCard(String title, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Theme.of(context).primaryColor, size: 28),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        Text(title, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildCodeBarChart() {
    if (_distribuicaoPorCodigo.isEmpty) return const SizedBox.shrink();
    final entries = _distribuicaoPorCodigo.entries.toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color corTexto = isDark ? Colors.white70 : const Color(0xFF023853);
    
    // Gradiente Estilo "Sample 3"
    final LinearGradient gradienteBarras = LinearGradient(
      colors: [Colors.cyan.shade300, Colors.blue.shade900],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: (entries.map((e) => e.value).reduce(max)) * 1.2,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1E293B), // Fundo escuro fixo
            tooltipMargin: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${entries[groupIndex].key}\n',
                const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14),
                children: <TextSpan>[
                  TextSpan(
                    text: '${rod.toY.toInt()}',
                    style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                ],
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value.toInt() >= entries.length) return const SizedBox.shrink();
                final String text = entries[value.toInt()].key;
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    text,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: corTexto),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(entries.length, (index) {
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: entries[index].value,
                gradient: gradienteBarras, // Gradiente aplicado
                width: 22,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: (entries.map((e) => e.value).reduce(max)) * 1.2,
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200,
                ),
              )
            ],
          );
        }),
      ),
    );
  }

  // Substitua o método _buildHistogram antigo por este:
  Widget _buildHistogram() {
    final valoresValidos = _dadosCAP
        .where((dado) => 
            dado['codigo'] != 'falha' && 
            dado['codigo'] != 'caida' && 
            dado['codigo'] != 'morta')
        .map((dado) => dado['cap'] as double)
        .toList();

    if (valoresValidos.isEmpty) return const Center(child: Text("Sem dados de CAP válidos."));

    final double minVal = valoresValidos.reduce(min);
    double maxVal = valoresValidos.reduce(max);
    if (minVal == maxVal) maxVal = minVal + 10;

    final int numBins = min(10, (maxVal - minVal).floor() + 1);
    if (numBins <= 0) return const Center(child: Text("Dados insuficientes."));

    final double binSize = (maxVal - minVal) / numBins;
    List<int> bins = List.filled(numBins, 0);
    List<double> binStarts = List.generate(numBins, (i) => minVal + i * binSize);

    for (double val in valoresValidos) {
      int binIndex = binSize > 0 ? ((val - minVal) / binSize).floor() : 0;
      if (binIndex >= numBins) binIndex = numBins - 1;
      if (binIndex < 0) binIndex = 0;
      bins[binIndex]++;
    }

    final double maxY = bins.isEmpty ? 1 : (bins.reduce(max).toDouble()) * 1.2;
    
    // CORES E ESTILO
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color corTexto = isDark ? Colors.white70 : const Color(0xFF023853);
    final LinearGradient gradienteBarras = LinearGradient(
      colors: [Colors.cyan.shade300, Colors.blue.shade900],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1E293B),
            tooltipMargin: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final binStart = binStarts[group.x.toInt()];
              final binEnd = binStart + binSize;
              return BarTooltipItem(
                '${binStart.toStringAsFixed(0)}-${binEnd.toStringAsFixed(0)} cm\n',
                const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                children: <TextSpan>[
                  TextSpan(
                    text: '${rod.toY.toInt()}',
                    style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                ],
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value.toInt() >= binStarts.length) return const SizedBox.shrink();
                final String text = binStarts[value.toInt()].toStringAsFixed(0);
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(text, style: TextStyle(fontSize: 10, color: corTexto, fontWeight: FontWeight.bold)),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(numBins, (index) {
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: bins[index].toDouble(),
                gradient: gradienteBarras, // Gradiente
                width: 16,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY,
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200,
                ),
              )
            ],
          );
        }),
      ),
    );
  }
}
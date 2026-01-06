// lib/pages/dashboard/relatorio_comparativo_page.dart (CORREÇÃO BOTÃO ESCURO)

import 'package:flutter/material.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/pages/dashboard/talhao_dashboard_page.dart';
import 'package:geoforestv1/pages/talhoes/form_talhao_page.dart';
import 'package:geoforestv1/services/pdf_service.dart';
import 'package:geoforestv1/models/enums.dart';
import 'package:geoforestv1/services/analysis_service.dart';
import 'package:geoforestv1/services/export_service.dart';

// Classe de configuração (Mantida igual)
class PlanoConfig {
  final MetodoDistribuicaoCubagem metodoDistribuicao;
  final int quantidade;
  final String metodoCubagem;
  final MetricaDistribuicao metricaDistribuicao;
  final bool isIntervaloManual;
  final double? intervaloManual;

  PlanoConfig({
    required this.metodoDistribuicao,
    required this.quantidade,
    required this.metodoCubagem,
    required this.metricaDistribuicao,
    required this.isIntervaloManual,
    this.intervaloManual,
  });
}

class RelatorioComparativoPage extends StatefulWidget {
  final List<Talhao> talhoesSelecionados;
  const RelatorioComparativoPage({super.key, required this.talhoesSelecionados});

  @override
  State<RelatorioComparativoPage> createState() => _RelatorioComparativoPageState();
}

class _RelatorioComparativoPageState extends State<RelatorioComparativoPage> {
  late List<Talhao> _talhoesAtuais;
  late Map<String, List<Talhao>> _talhoesPorFazenda;
  final dbHelper = DatabaseHelper.instance;
  final pdfService = PdfService();
  final exportService = ExportService();

  @override
  void initState() {
    super.initState();
    _talhoesAtuais = List.from(widget.talhoesSelecionados);
    _agruparTalhoes();
  }

  void _agruparTalhoes() {
    final grouped = <String, List<Talhao>>{};
    for (var talhao in _talhoesAtuais) {
      final fazendaNome = talhao.fazendaNome ?? 'Fazenda Desconhecida';
      if (!grouped.containsKey(fazendaNome)) {
        grouped[fazendaNome] = [];
      }
      grouped[fazendaNome]!.add(talhao);
    }
    setState(() => _talhoesPorFazenda = grouped);
  }
  
  // (Métodos auxiliares mantidos iguais para brevidade: _verificarAreaEExportarPdf, _mostrarDialogoDeConfiguracaoLote, _gerarPlanosDeCubagemParaSelecionados)
  // ... Copie os métodos internos do seu código anterior ou mantenha se não mudaram ...
  // Vou incluir apenas o _mostrarDialogoDeConfiguracaoLote e _gerarPlanosDeCubagemParaSelecionados
  // para garantir que o arquivo fique funcional se você copiar tudo.

  Future<void> _verificarAreaEExportarPdf() async {
    bool dadosIncompletos = _talhoesAtuais.any((t) => t.areaHa == null || t.areaHa! <= 0);

    if (dadosIncompletos && mounted) {
      final bool? querEditar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Dados Incompletos'),
          content: const Text('Um ou mais talhões não possuem a área (ha) cadastrada. Deseja editá-los agora para um relatório mais completo?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Exportar Mesmo Assim')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Editar Agora')),
          ],
        ),
      );

      if (querEditar == true) {
        for (int i = 0; i < _talhoesAtuais.length; i++) {
          var talhao = _talhoesAtuais[i];
          if (talhao.areaHa == null || talhao.areaHa! <= 0) {
            final bool? foiEditado = await Navigator.push<bool>(
              context,
              MaterialPageRoute(builder: (context) => FormTalhaoPage(
                fazendaId: talhao.fazendaId,
                fazendaAtividadeId: talhao.fazendaAtividadeId,
                talhaoParaEditar: talhao,
              )),
            );
            if (foiEditado == true) {
              final talhaoAtualizado = await dbHelper.database.then((db) => db.query('talhoes', where: 'id = ?', whereArgs: [talhao.id]).then((maps) => Talhao.fromMap(maps.first)));
              _talhoesAtuais[i] = talhaoAtualizado;
            }
          }
        }
        _agruparTalhoes();
      }
    }
  
    await pdfService.gerarRelatorioUnificadoPdf(
      context: context,
      talhoes: _talhoesAtuais,
    );
  }

  Future<PlanoConfig?> _mostrarDialogoDeConfiguracaoLote() async {
    final quantidadeController = TextEditingController();
    final intervaloController = TextEditingController(); 
    final formKey = GlobalKey<FormState>();
    
    MetodoDistribuicaoCubagem metodoDistribuicao = MetodoDistribuicaoCubagem.fixoPorTalhao;
    String metodoCubagem = 'Fixas';
    MetricaDistribuicao metricaSelecionada = MetricaDistribuicao.dap; 
    bool isIntervaloManual = false;

    return showDialog<PlanoConfig>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Configurar Plano de Cubagem'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('1. Métrica Base para Distribuição', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SegmentedButton<MetricaDistribuicao>(
                        segments: const [
                          ButtonSegment(value: MetricaDistribuicao.dap, label: Text('DAP')),
                          ButtonSegment(value: MetricaDistribuicao.cap, label: Text('CAP')),
                        ],
                        selected: {metricaSelecionada},
                        onSelectionChanged: (newSelection) {
                          setDialogState(() => metricaSelecionada = newSelection.first);
                        },
                      ),
                      const Divider(height: 24),
                      const Text('2. Como distribuir as árvores?', style: TextStyle(fontWeight: FontWeight.bold)),
                      RadioListTile<MetodoDistribuicaoCubagem>(
                        title: const Text('Quantidade Fixa por Talhão'),
                        value: MetodoDistribuicaoCubagem.fixoPorTalhao,
                        groupValue: metodoDistribuicao,
                        onChanged: (v) => setDialogState(() => metodoDistribuicao = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<MetodoDistribuicaoCubagem>(
                        title: const Text('Total Proporcional à Área'),
                        value: MetodoDistribuicaoCubagem.proporcionalPorArea,
                        groupValue: metodoDistribuicao,
                        onChanged: (v) => setDialogState(() => metodoDistribuicao = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                      TextFormField(
                        controller: quantidadeController,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: metodoDistribuicao == MetodoDistribuicaoCubagem.fixoPorTalhao
                              ? 'Nº de árvores por talhão'
                              : 'Nº total de árvores para o lote',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Campo obrigatório';
                          final parsed = int.tryParse(v);
                          if (parsed == null || parsed <= 0) return 'Digite um número válido maior que zero';
                          return null;
                        },
                      ),
                      const Divider(height: 24),
                      const Text('3. Qual o método de medição?', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: metodoCubagem,
                        items: const [
                          DropdownMenuItem(value: 'Fixas', child: Text('Seções Fixas')),
                          DropdownMenuItem(value: 'Relativas', child: Text('Seções Relativas')),
                        ],
                        onChanged: (value) {
                          if (value != null) setDialogState(() => metodoCubagem = value);
                        },
                        decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                      ),
                      const Divider(height: 24),
                      const Text('4. Intervalo das Classes', style: TextStyle(fontWeight: FontWeight.bold)),
                      RadioListTile<bool>(
                        title: const Text('Automático (Padrão)'),
                        subtitle: Text(metricaSelecionada == MetricaDistribuicao.dap ? 'Classes de 5 em 5 cm' : 'Classes de 15 em 15 cm'),
                        value: false,
                        groupValue: isIntervaloManual,
                        onChanged: (v) => setDialogState(() => isIntervaloManual = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<bool>(
                        title: const Text('Manual'),
                        value: true,
                        groupValue: isIntervaloManual,
                        onChanged: (v) => setDialogState(() => isIntervaloManual = v!),
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (isIntervaloManual)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0),
                          child: TextFormField(
                            controller: intervaloController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Intervalo da classe (cm)',
                              border: const OutlineInputBorder(),
                              hintText: metricaSelecionada == MetricaDistribuicao.dap ? 'Ex: 2' : 'Ex: 5',
                            ),
                            validator: (v) {
                              if (!isIntervaloManual) return null; 
                              if (v == null || v.isEmpty) return 'Obrigatório';
                              final val = double.tryParse(v.replaceAll(',', '.'));
                              if (val == null || val <= 0) return 'Valor inválido';
                              return null;
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      // Valida novamente antes de parse (segurança extra)
                      final quantidadeParsed = int.tryParse(quantidadeController.text);
                      if (quantidadeParsed == null || quantidadeParsed <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('Quantidade inválida'),
                          backgroundColor: Colors.red,
                        ));
                        return;
                      }
                      
                      Navigator.of(ctx).pop(
                        PlanoConfig(
                          metodoDistribuicao: metodoDistribuicao,
                          quantidade: quantidadeParsed,
                          metodoCubagem: metodoCubagem,
                          metricaDistribuicao: metricaSelecionada,
                          isIntervaloManual: isIntervaloManual,
                          intervaloManual: isIntervaloManual
                              ? double.tryParse(intervaloController.text.replaceAll(',', '.'))
                              : null,
                        ),
                      );
                    }
                  },
                  child: const Text('Gerar Planos'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  Future<void> _gerarPlanosDeCubagemParaSelecionados() async {
    final PlanoConfig? config = await _mostrarDialogoDeConfiguracaoLote();
    if (config == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Gerando atividades e planos no banco de dados...'),
      backgroundColor: Colors.blue,
      duration: Duration(seconds: 15),
    ));
    
    final analysisService = AnalysisService();
    try {
      final planosGerados = await analysisService.criarMultiplasAtividadesDeCubagem(
        talhoes: _talhoesAtuais,
        metodo: config.metodoDistribuicao,
        quantidade: config.quantidade,
        metodoCubagem: config.metodoCubagem,
        metrica: config.metricaDistribuicao,
        isIntervaloManual: config.isIntervaloManual,
        intervaloManual: config.intervaloManual,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();

      if (planosGerados.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nenhum plano foi gerado. Verifique os dados dos talhões.'),
          backgroundColor: Colors.orange,
        ));
        return;
      }
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Atividades criadas! Gerando PDF dos planos...'),
        backgroundColor: Colors.green,
      ));

      await pdfService.gerarPdfUnificadoDePlanosDeCubagem(
        context: context, 
        planosPorTalhao: planosGerados,
        metrica: config.metricaDistribuicao,
      );

    } catch (e) {
       if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao gerar atividades: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatório Comparativo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined), 
            onPressed: () => exportService.exportarTudoComoZip(context: context, talhoes: _talhoesAtuais),
            tooltip: 'Exportar Pacote Completo (ZIP)',
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _verificarAreaEExportarPdf,
            tooltip: 'Exportar Análises (PDF Unificado)',
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: _talhoesPorFazenda.keys.length,
        itemBuilder: (context, index) {
          final fazendaNome = _talhoesPorFazenda.keys.elementAt(index);
          final talhoesDaFazenda = _talhoesPorFazenda[fazendaNome]!;
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: ExpansionTile(
              title: Text(fazendaNome, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              initiallyExpanded: true,
              children: talhoesDaFazenda.map((talhao) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Theme.of(context).dividerColor)),
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      title: Text('Talhão: ${talhao.nome}', style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text(talhao.areaHa != null ? 'Área: ${talhao.areaHa} ha' : 'Área não informada'),
                      children: [TalhaoDashboardContent(talhao: talhao)],
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
      
      // >>> CORREÇÃO DO BOTÃO AQUI <<<
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _gerarPlanosDeCubagemParaSelecionados,
        icon: const Icon(Icons.playlist_add_check_outlined),
        label: const Text('Gerar Planos de Cubagem'),
        tooltip: 'Gerar planos de cubagem para os talhões selecionados',
        // Fundo Dourado (do tema ou fixo)
        backgroundColor: Theme.of(context).colorScheme.secondary, 
        // Força a cor do texto para AZUL ESCURO
        foregroundColor: const Color(0xFF023853), 
      ),
    );
  }
}
// lib/pages/menu/visualizador_relatorio_page.dart (VERSÃO COM BOTÃO HOME)

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/services/export_service.dart';
import 'package:geoforestv1/services/pdf_service.dart';
import 'package:geoforestv1/services/sync_service.dart';
import 'package:geoforestv1/utils/navigation_helper.dart'; // <<< 1. IMPORT NECESSÁRIO

/// Tela de ações finais após a consolidação de um relatório diário.
class VisualizadorRelatorioPage extends StatefulWidget {
  final DiarioDeCampo diario;
  final List<Parcela> parcelas;
  final List<CubagemArvore> cubagens;

  const VisualizadorRelatorioPage({
    super.key,
    required this.diario,
    required this.parcelas,
    required this.cubagens,
  });

  @override
  State<VisualizadorRelatorioPage> createState() => _VisualizadorRelatorioPageState();
}

class _VisualizadorRelatorioPageState extends State<VisualizadorRelatorioPage> {
  final _pdfService = PdfService();
  final _exportService = ExportService();
  final _syncService = SyncService();

  bool _isSyncing = false;
  bool _hasSynced = false;

  /// Chama o serviço para gerar, salvar e abrir o relatório em PDF.
  Future<void> _visualizarPdf() async {
    await _pdfService.gerarRelatorioDiarioConsolidadoPdf(
      context: context,
      diario: widget.diario,
      parcelas: widget.parcelas,
      cubagens: widget.cubagens,
    );
  }

  /// Aciona a exportação dos dados brutos em formato CSV.
  Future<void> _exportarCsv() async {
    await _exportService.exportarRelatorioDiarioConsolidadoCsv(
      context: context,
      diario: widget.diario,
      parcelas: widget.parcelas,
      cubagens: widget.cubagens,
    );
  }

  /// Sincroniza o diário de campo com a nuvem (Firestore).
  Future<void> _sincronizarDiario() async {
    setState(() => _isSyncing = true);
    try {
      await _syncService.sincronizarDiarioDeCampo(widget.diario);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Diário sincronizado com sucesso com o dashboard!'),
          backgroundColor: Colors.green,
        ));
      }
      setState(() => _hasSynced = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao sincronizar: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finalizar Relatório'),
        // <<< 2. BOTÃO ADICIONADO AQUI >>>
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Voltar para o Início',
            // Ao clicar, chama a função do helper para voltar ao menu principal
            onPressed: () => NavigationHelper.goBackToHome(context),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
              const SizedBox(height: 24),
              const Text(
                'Relatório Consolidado',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Seu diário e coletas estão prontos. Use os botões abaixo para visualizar, exportar e sincronizar os dados.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 48),

              // Botões de Ação
              OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Visualizar PDF'),
                onPressed: _visualizarPdf,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.table_rows_outlined),
                label: const Text('Exportar Dados (CSV)'),
                onPressed: _exportarCsv,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: _isSyncing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Icon(_hasSynced ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined),
                label: Text(_isSyncing ? 'Sincronizando...' : (_hasSynced ? 'Sincronizado' : 'Sincronizar Diário')),
                onPressed: _isSyncing || _hasSynced ? null : _sincronizarDiario,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar Informações'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
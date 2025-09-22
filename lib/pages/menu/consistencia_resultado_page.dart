// ✅ NOVO ARQUIVO: lib/pages/menu/consistencia_resultado_page.dart (COM CORREÇÕES)

import 'package:flutter/material.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/pages/amostra/inventario_page.dart';
import 'package:geoforestv1/services/validation_service.dart';

class ConsistenciaResultadoPage extends StatelessWidget {
  final FullValidationReport report;
  final List<Parcela> parcelasVerificadas; // Para poder re-verificar

  const ConsistenciaResultadoPage({
    super.key,
    required this.report,
    required this.parcelasVerificadas,
  });

  @override
  Widget build(BuildContext context) {
    final issuesAgrupados = groupBy(report.issues, (ValidationIssue issue) => issue.tipo);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatório de Consistência'),
        actions: [
          TextButton.icon(
            onPressed: () {
              // TODO: Implementar lógica de exportação aqui
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Exportação iniciada com os dados consistidos.'))
              );
            },
            icon: const Icon(Icons.upload_file_outlined, color: Colors.white),
            label: const Text('Exportar CSV', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: report.isConsistent
          ? _buildSuccessView(context)
          : ListView(
              padding: const EdgeInsets.all(8),
              children: issuesAgrupados.entries.map((entry) {
                final tipo = entry.key;
                final issuesDoTipo = entry.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    title: Text('$tipo (${issuesDoTipo.length} problemas)', style: const TextStyle(fontWeight: FontWeight.bold)),
                    initiallyExpanded: true,
                    children: issuesDoTipo.map((issue) {
                      return ListTile(
                        leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                        // ✅ CORREÇÃO 1: Trocar 'identificadorParcela' por 'identificador'
                        title: Text(issue.identificador),
                        subtitle: Text(issue.mensagem),
                        onTap: () async {
                          // ✅ CORREÇÃO 2: Verificar se o ID não é nulo antes de usar
                          if (issue.parcelaId != null) {
                            // Navega para a tela de inventário para correção
                            final parcela = await ParcelaRepository().getParcelaById(issue.parcelaId!); // O '!' garante que não é nulo
                            if (parcela != null && context.mounted) {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => InventarioPage(parcela: parcela)
                              ));
                            }
                          }
                          // Adicionar lógica para cubagem aqui se necessário
                        },
                      );
                    }).toList(),
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildSuccessView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.green, size: 80),
          const SizedBox(height: 16),
          const Text('Nenhuma inconsistência encontrada!', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 8),
          // ✅ CORREÇÃO 3: Adicionar a contagem de cubagens verificadas
          Text('${report.parcelasVerificadas} amostras, ${report.arvoresVerificadas} árvores e ${report.cubagensVerificadas} cubagens verificadas.'),
        ],
      ),
    );
  }
}

// Função auxiliar para agrupar a lista (pode ficar no mesmo arquivo)
Map<T, List<S>> groupBy<S, T>(Iterable<S> values, T Function(S) key) {
  var map = <T, List<S>>{};
  for (var element in values) {
    (map[key(element)] ??= []).add(element);
  }
  return map;
}
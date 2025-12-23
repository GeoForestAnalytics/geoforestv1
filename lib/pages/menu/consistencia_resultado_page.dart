// lib/pages/menu/consistencia_resultado_page.dart (VERSÃO COM PULO DIRETO)

import 'package:flutter/material.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/pages/amostra/inventario_page.dart';
import 'package:geoforestv1/services/validation_service.dart';

class ConsistenciaResultadoPage extends StatelessWidget {
  final FullValidationReport report;
  final List<Parcela> parcelasVerificadas;

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
                        title: Text(issue.identificador),
                        subtitle: Text(issue.mensagem),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14), // Indicador de clique
                        onTap: () async {
                          if (issue.parcelaId != null) {
                            final parcelaRepo = ParcelaRepository();
                            
                            // 1. Busca a parcela (cabeçalho)
                            final Parcela? parcela = await parcelaRepo.getParcelaById(issue.parcelaId!);
                            
                            if (parcela != null && context.mounted) {
                              // 2. Busca as árvores associadas
                              final List<Arvore> arvoresDaParcela = await parcelaRepo.getArvoresDaParcela(parcela.dbId!);
                              
                              // 3. Anexa as árvores ao objeto
                              parcela.arvores = arvoresDaParcela;
                              
                              // 4. Navega passando o ID da árvore alvo para o Pulo Direto
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => InventarioPage(
                                  parcela: parcela,
                                  targetArvoreId: issue.arvoreId, // <--- AQUI A MÁGICA ACONTECE
                                )
                              ));
                            }
                          }
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
          Text('${report.parcelasVerificadas} amostras, ${report.arvoresVerificadas} árvores e ${report.cubagensVerificadas} cubagens verificadas.'),
        ],
      ),
    );
  }
}

// Função auxiliar para agrupar a lista
Map<T, List<S>> groupBy<S, T>(Iterable<S> values, T Function(S) key) {
  var map = <T, List<S>>{};
  for (var element in values) {
    (map[key(element)] ??= []).add(element);
  }
  return map;
}
// <<< INÍCIO: NOVOS IMPORTS ADICIONADOS >>>
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:geoforestv1/models/arvore_model.dart';
// <<< FIM: NOVOS IMPORTS ADICIONADOS >>>

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/sync_conflict_model.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:intl/intl.dart';

class ConflictResolutionPage extends StatefulWidget {
  final List<SyncConflict> conflicts;

  const ConflictResolutionPage({super.key, required this.conflicts});

  @override
  State<ConflictResolutionPage> createState() => _ConflictResolutionPageState();
}

class _ConflictResolutionPageState extends State<ConflictResolutionPage> {
  final ParcelaRepository _parcelaRepository = ParcelaRepository();
  late List<SyncConflict> _remainingConflicts;

  @override
  void initState() {
    super.initState();
    _remainingConflicts = List.from(widget.conflicts);
  }

  // <<< INÍCIO: MÉTODO _resolveConflict COMPLETAMENTE SUBSTITUÍDO >>>
  /// Função para resolver um conflito específico, agora com busca de árvores.
  Future<void> _resolveConflict(SyncConflict conflict, bool keepLocal) async {
    try {
      if (keepLocal) {
        // Lógica para manter a versão local (não foi alterada)
        if (conflict.type == ConflictType.parcela) {
          final Parcela localParcela = conflict.localData;
          final updatedParcela = localParcela.copyWith(
            isSynced: false,
            lastModified: DateTime.now().add(const Duration(seconds: 5)),
          );
          await _parcelaRepository.updateParcela(updatedParcela);
        }
        // Adicionar lógica para outros tipos de conflito aqui (ex: cubagem)
      } else {
        // Lógica para aceitar a versão do servidor (CORRIGIDA)
        if (conflict.type == ConflictType.parcela) {
          // 1. Obter os dados da parcela do servidor e o ID local
          final Parcela serverParcela = conflict.serverData;
          final Parcela localParcela = conflict.localData;

          // 2. Obter a licença para saber onde buscar os dados no Firestore
          // O `listen: false` é importante para ser usado dentro de uma função assíncrona.
          final licenseId = context.read<LicenseProvider>().licenseData?.id;
          if (licenseId == null) {
            throw Exception("Não foi possível identificar a licença para buscar as árvores.");
          }

          // 3. Buscar a subcoleção de árvores do servidor
          final arvoresSnapshot = await FirebaseFirestore.instance
              .collection('clientes')
              .doc(licenseId)
              .collection('dados_coleta')
              .doc(serverParcela.uuid)
              .collection('arvores')
              .get();

          // 4. Converter os documentos do Firestore para objetos Arvore
          final List<Arvore> serverArvores = arvoresSnapshot.docs
              .map((doc) => Arvore.fromMap(doc.data()))
              .toList();
          
          // 5. Preparar o objeto da parcela para ser salvo localmente
          final updatedParcela = serverParcela.copyWith(
            dbId: localParcela.dbId, // Mantém o ID do banco local
            isSynced: true,         // Marca como sincronizado
          );

          // 6. Usar o método `saveFullColeta`, que apaga as árvores antigas
          //    e salva a parcela com sua nova lista de árvores do servidor.
          await _parcelaRepository.saveFullColeta(updatedParcela, serverArvores);
        }
        // Adicionar lógica para outros tipos de conflito aqui (ex: cubagem)
      }
      // <<< FIM: MÉTODO _resolveConflict COMPLETAMENTE SUBSTITUÍDO >>>

      // Remove o conflito resolvido da lista
      setState(() {
        _remainingConflicts.remove(conflict);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conflito resolvido!'), backgroundColor: Colors.green),
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao resolver conflito: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resolver Conflitos'),
        automaticallyImplyLeading: _remainingConflicts.isEmpty,
      ),
      body: _remainingConflicts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 80),
                  const SizedBox(height: 16),
                  const Text('Todos os conflitos foram resolvidos!', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Voltar ao Menu'),
                  )
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _remainingConflicts.length,
              itemBuilder: (context, index) {
                final conflict = _remainingConflicts[index];
                return _buildConflictCard(conflict);
              },
            ),
    );
  }

  Widget _buildConflictCard(SyncConflict conflict) {
    if (conflict.type == ConflictType.parcela) {
      final Parcela local = conflict.localData;
      final Parcela server = conflict.serverData;
      return Card(
        elevation: 2,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(conflict.identifier, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Divider(height: 20),
              
              Table(
                columnWidths: const {
                  0: IntrinsicColumnWidth(),
                  1: FlexColumnWidth(),
                  2: FlexColumnWidth(),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: Colors.grey.shade200),
                    children: [
                      const Padding(padding: EdgeInsets.all(8), child: Text('Campo', style: TextStyle(fontWeight: FontWeight.bold))),
                      const Padding(padding: EdgeInsets.all(8), child: Text('Sua Versão (Local)', style: TextStyle(fontWeight: FontWeight.bold))),
                      const Padding(padding: EdgeInsets.all(8), child: Text('Versão do Servidor', style: TextStyle(fontWeight: FontWeight.bold))),
                    ]
                  ),
                  _buildComparisonRow('Status', local.status.name, server.status.name),
                  _buildComparisonRow('Líder', local.nomeLider ?? 'N/A', server.nomeLider ?? 'N/A'),
                  _buildComparisonRow('Observação', local.observacao ?? '', server.observacao ?? ''),
                  _buildComparisonRow('Modificado em', 
                    local.lastModified != null ? DateFormat('dd/MM HH:mm:ss').format(local.lastModified!) : 'N/A',
                    server.lastModified != null ? DateFormat('dd/MM HH:mm:ss').format(server.lastModified!) : 'N/A',
                  ),
                ],
              ),

              const SizedBox(height: 20),
              const Text('Qual versão você deseja manter?', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => _resolveConflict(conflict, false),
                    child: const Text('Manter do Servidor'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _resolveConflict(conflict, true),
                    child: const Text('Manter a Minha'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return Card(child: ListTile(title: Text('Conflito não suportado: ${conflict.identifier}')));
  }

  TableRow _buildComparisonRow(String label, String localValue, String serverValue) {
    final bool isDifferent = localValue != serverValue;
    return TableRow(
      decoration: BoxDecoration(
        color: isDifferent ? Colors.yellow.shade100 : Colors.transparent,
      ),
      children: [
        Padding(padding: const EdgeInsets.all(8.0), child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
        Padding(padding: const EdgeInsets.all(8.0), child: Text(localValue)),
        Padding(padding: const EdgeInsets.all(8.0), child: Text(serverValue)),
      ],
    );
  }
}
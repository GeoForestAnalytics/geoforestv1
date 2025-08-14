// lib/pages/menu/conflict_resolution_page.dart (NOVO ARQUIVO)

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/sync_conflict_model.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:intl/intl.dart';
// Adicione outros repositórios conforme necessário para outros tipos de conflito

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

  // Função para resolver um conflito específico
  Future<void> _resolveConflict(SyncConflict conflict, bool keepLocal) async {
    try {
      if (keepLocal) {
        // Se o usuário quer manter a versão local, precisamos "forçar" o upload.
        // Isso é feito marcando como não-sincronizado e com um timestamp futuro.
        if (conflict.type == ConflictType.parcela) {
          final Parcela localParcela = conflict.localData;
          final updatedParcela = localParcela.copyWith(
            isSynced: false,
            // Damos um "empurrão" no tempo para garantir que ela vença a próxima comparação
            lastModified: DateTime.now().add(const Duration(seconds: 5)),
          );
          await _parcelaRepository.updateParcela(updatedParcela);
        }
        // Adicionar lógica para outros tipos de conflito aqui (ex: cubagem)
      } else {
        // Se o usuário quer a versão do servidor, nós simplesmente sobrescrevemos
        // a versão local com os dados que vieram do servidor.
        if (conflict.type == ConflictType.parcela) {
          final Parcela serverParcela = conflict.serverData;
          final Parcela localParcela = conflict.localData;
          
          final updatedParcela = serverParcela.copyWith(
            dbId: localParcela.dbId, // Mantém o ID do banco local
            isSynced: true, // Já está sincronizada com a versão do servidor
          );
          
          // Precisamos buscar as árvores da parcela do servidor
          // (Lógica a ser implementada se necessário, por enquanto salvamos sem as árvores)
          await _parcelaRepository.saveFullColeta(updatedParcela, []);
        }
      }

      // Remove o conflito resolvido da lista
      setState(() {
        _remainingConflicts.remove(conflict);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conflito resolvido!'), backgroundColor: Colors.green),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao resolver conflito: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resolver Conflitos'),
        automaticallyImplyLeading: _remainingConflicts.isEmpty, // Esconde o botão voltar se não há mais conflitos
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
    // Aqui, construímos a UI para cada tipo de conflito. Começamos com Parcela.
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
              
              // Tabela de comparação
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
// lib/widgets/manager_export_dialog.dart (VERSÃO COM REFINAMENTO VISUAL)

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/projeto_model.dart';

// A classe ExportFilters continua a mesma
class ExportFilters {
  final bool isBackup;
  final Set<int> selectedProjetoIds;
  final Set<String> selectedLideres;

  ExportFilters({
    required this.isBackup,
    required this.selectedProjetoIds,
    required this.selectedLideres,
  });
}

class ManagerExportDialog extends StatefulWidget {
  final bool isBackup;
  final List<Projeto> projetosDisponiveis;
  final Set<String> lideresDisponiveis;

  const ManagerExportDialog({
    super.key,
    required this.isBackup,
    required this.projetosDisponiveis,
    required this.lideresDisponiveis,
  });

  @override
  State<ManagerExportDialog> createState() => _ManagerExportDialogState();
}

class _ManagerExportDialogState extends State<ManagerExportDialog> {
  late Set<int> _selectedProjetoIds;
  late Set<String> _selectedLideres;

  @override
  void initState() {
    super.initState();
    _selectedProjetoIds = {};
    _selectedLideres = {};
  }

  void _toggleAllProjetos(bool? selectAll) {
    setState(() {
      if (selectAll == true) {
        _selectedProjetoIds = widget.projetosDisponiveis.map((p) => p.id!).toSet();
      } else {
        _selectedProjetoIds.clear();
      }
    });
  }

  void _toggleAllLideres(bool? selectAll) {
    setState(() {
      if (selectAll == true) {
        _selectedLideres = widget.lideresDisponiveis;
      } else {
        _selectedLideres.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool allProjetosSelected = _selectedProjetoIds.length == widget.projetosDisponiveis.length && widget.projetosDisponiveis.isNotEmpty;
    final bool allLideresSelected = _selectedLideres.length == widget.lideresDisponiveis.length && widget.lideresDisponiveis.isNotEmpty;

    return AlertDialog(
      title: Text(widget.isBackup ? 'Filtros para Backup' : 'Filtros de Exportação'),
      // Adicionado padding ao content para dar um respiro
      contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Deixe em branco para incluir todos.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              
              // <<< INÍCIO DO REFINAMENTO VISUAL >>>
              // Seção de Projetos agrupada em um Card
              _buildFilterSection(
                title: 'Projetos',
                isEmpty: widget.projetosDisponiveis.isEmpty,
                emptyText: 'Nenhum projeto disponível.',
                allSelected: allProjetosSelected,
                onToggleAll: (value) => _toggleAllProjetos(value),
                children: widget.projetosDisponiveis.map((projeto) {
                  return CheckboxListTile(
                    title: Text(projeto.nome, overflow: TextOverflow.ellipsis),
                    value: _selectedProjetoIds.contains(projeto.id),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedProjetoIds.add(projeto.id!);
                        } else {
                          _selectedProjetoIds.remove(projeto.id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Seção de Equipes agrupada em um Card
              _buildFilterSection(
                title: 'Equipes',
                isEmpty: widget.lideresDisponiveis.isEmpty,
                emptyText: 'Nenhuma equipe com coletas encontradas.',
                allSelected: allLideresSelected,
                onToggleAll: (value) => _toggleAllLideres(value),
                children: widget.lideresDisponiveis.map((lider) {
                  return CheckboxListTile(
                    title: Text(lider, overflow: TextOverflow.ellipsis),
                    value: _selectedLideres.contains(lider),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedLideres.add(lider);
                        } else {
                          _selectedLideres.remove(lider);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              // <<< FIM DO REFINAMENTO VISUAL >>>
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final result = ExportFilters(
              isBackup: widget.isBackup,
              selectedProjetoIds: _selectedProjetoIds,
              selectedLideres: _selectedLideres,
            );
            Navigator.of(context).pop(result);
          },
          child: const Text('Exportar'),
        )
      ],
    );
  }

  // <<< WIDGET AUXILIAR PARA CRIAR AS SEÇÕES >>>
  Widget _buildFilterSection({
    required String title,
    required bool isEmpty,
    required String emptyText,
    required bool allSelected,
    required ValueChanged<bool?> onToggleAll,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                if (!isEmpty)
                  TextButton(onPressed: () => onToggleAll(!allSelected), child: Text(allSelected ? 'Limpar' : 'Todos')),
              ],
            ),
            const Divider(height: 1),
            if (isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(emptyText, style: const TextStyle(color: Colors.grey)),
              )
            else
              // Constrain the height to prevent the dialog from growing too large
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200), // Adjust height as needed
                child: ListView(
                  shrinkWrap: true,
                  children: children,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
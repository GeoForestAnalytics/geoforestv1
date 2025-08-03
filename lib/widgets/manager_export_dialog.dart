// lib/widgets/manager_export_dialog.dart (VERSÃO CORRIGIDA E MELHORADA)

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
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Deixe em branco para incluir todos.', style: TextStyle(color: Colors.grey)),
              const Divider(),
              
              // Seção de Projetos
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Projetos', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (widget.projetosDisponiveis.isNotEmpty)
                    TextButton(onPressed: () => _toggleAllProjetos(!allProjetosSelected), child: Text(allProjetosSelected ? 'Limpar' : 'Todos')),
                ],
              ),
              if (widget.projetosDisponiveis.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('Nenhum projeto disponível.', style: TextStyle(color: Colors.grey)),
                )
              else
                ...widget.projetosDisponiveis.map((projeto) {
                  return CheckboxListTile(
                    title: Text(projeto.nome),
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

              const Divider(),

              // <<< INÍCIO DA CORREÇÃO PRINCIPAL >>>
              // Seção de Equipes
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Equipes', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (widget.lideresDisponiveis.isNotEmpty)
                    TextButton(onPressed: () => _toggleAllLideres(!allLideresSelected), child: Text(allLideresSelected ? 'Limpar' : 'Todas')),
                ],
              ),
              // Verifica se a lista de líderes está vazia e mostra uma mensagem.
              if (widget.lideresDisponiveis.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('Nenhuma equipe com coletas encontradas.', style: TextStyle(color: Colors.grey)),
                )
              else
                // Constrói a lista de Checkboxes a partir do Set
                ...widget.lideresDisponiveis.map((lider) {
                  return CheckboxListTile(
                    title: Text(lider),
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
              // <<< FIM DA CORREÇÃO PRINCIPAL >>>
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
}
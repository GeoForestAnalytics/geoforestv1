// lib/pages/menu/historico_diarios_page.dart (NOVO ARQUIVO)

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:geoforestv1/data/repositories/diario_de_campo_repository.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:geoforestv1/providers/team_provider.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class HistoricoDiariosPage extends StatefulWidget {
  const HistoricoDiariosPage({super.key});

  @override
  State<HistoricoDiariosPage> createState() => _HistoricoDiariosPageState();
}

class _HistoricoDiariosPageState extends State<HistoricoDiariosPage> {
  final _diarioRepository = DiarioDeCampoRepository();
  Future<List<DiarioDeCampo>>? _diariosFuture;

  @override
  void initState() {
    super.initState();
    // Carrega os diários assim que a tela é construída
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _carregarDiarios();
    });
  }

  /// Carrega a lista de diários do líder logado.
  void _carregarDiarios() {
    final lider = context.read<TeamProvider>().lider;
    if (lider != null && lider.isNotEmpty) {
      setState(() {
        _diariosFuture = _diarioRepository.getDiariosPorLider(lider);
      });
    }
  }

  /// Mostra um diálogo de confirmação e, se confirmado, apaga o diário.
  Future<void> _deletarDiario(DiarioDeCampo diario) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text('Tem certeza que deseja apagar permanentemente o relatório do dia ${DateFormat('dd/MM/yyyy').format(DateTime.parse(diario.dataRelatorio))}?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (confirmar == true && mounted) {
      try {
        final licenseId = context.read<LicenseProvider>().licenseData?.id;
        if (licenseId == null) {
          throw Exception("Licença não encontrada para sincronizar a exclusão.");
        }
        await _diarioRepository.deleteDiario(diario, licenseId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Relatório apagado com sucesso.'),
            backgroundColor: Colors.green,
          ));
        }
        _carregarDiarios(); // Recarrega a lista
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro ao apagar: $e'),
            backgroundColor: Colors.red,
          ));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Diários'),
      ),
      body: FutureBuilder<List<DiarioDeCampo>>(
        future: _diariosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar histórico: ${snapshot.error}'));
          }
          final diarios = snapshot.data ?? [];
          if (diarios.isEmpty) {
            return const Center(
              child: Text(
                'Nenhum relatório diário foi salvo neste dispositivo.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: diarios.length,
            itemBuilder: (context, index) {
              final diario = diarios[index];
              return Slidable(
                key: ValueKey(diario.id),
                endActionPane: ActionPane(
                  motion: const StretchMotion(),
                  children: [
                    SlidableAction(
                      onPressed: (_) => _deletarDiario(diario),
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      icon: Icons.delete_forever,
                      label: 'Apagar',
                    ),
                  ],
                ),
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
                    title: Text('Relatório de ${DateFormat('dd/MM/yyyy').format(DateTime.parse(diario.dataRelatorio))}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Destino: ${diario.localizacaoDestino ?? 'Não informado'}'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
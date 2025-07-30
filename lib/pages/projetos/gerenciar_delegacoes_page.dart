// lib/pages/projetos/gerenciar_delegacoes_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:geoforestv1/providers/license_provider.dart';

class GerenciarDelegacoesPage extends StatefulWidget {
  const GerenciarDelegacoesPage({super.key});

  @override
  State<GerenciarDelegacoesPage> createState() => _GerenciarDelegacoesPageState();
}

class _GerenciarDelegacoesPageState extends State<GerenciarDelegacoesPage> {
  Future<QuerySnapshot>? _delegacoesFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _carregarDelegacoes();
    });
  }

  void _carregarDelegacoes() {
    final licenseId = context.read<LicenseProvider>().licenseData?.id;
    if (licenseId != null) {
      setState(() {
        _delegacoesFuture = FirebaseFirestore.instance
            .collection('clientes')
            .doc(licenseId)
            .collection('chavesDeDelegacao')
            .orderBy('dataCriacao', descending: true)
            .get();
      });
    }
  }

  Future<void> _revogarAcesso(DocumentSnapshot delegacaoDoc) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Revogar Acesso?"),
        content: const Text("Tem certeza que deseja revogar o acesso desta delegação? A empresa convidada não poderá mais sincronizar dados para este projeto."),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancelar")),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Revogar"),
          ),
        ],
      ),
    );

    if (confirmar == true && mounted) {
      try {
        await delegacaoDoc.reference.update({'status': 'revogada'});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Acesso revogado com sucesso."),
          backgroundColor: Colors.green,
        ));
        _carregarDelegacoes(); // Recarrega a lista para mostrar o novo status
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Erro ao revogar acesso: $e"),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Widget _buildStatusChip(String status) {
    Color cor;
    String texto;
    switch (status) {
      case 'ativa':
        cor = Colors.green;
        texto = 'ATIVA';
        break;
      case 'revogada':
        cor = Colors.red;
        texto = 'REVOGADA';
        break;
      default: // pendente
        cor = Colors.orange;
        texto = 'PENDENTE';
    }
    return Chip(
      label: Text(texto, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      backgroundColor: cor,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gerenciar Delegações"),
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: _delegacoesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Erro ao carregar dados: ${snapshot.error}"));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("Nenhuma delegação foi criada ainda."));
          }

          final delegacoes = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: delegacoes.length,
            itemBuilder: (context, index) {
              final doc = delegacoes[index];
              final data = doc.data() as Map<String, dynamic>;
              
              final projetosPermitidos = (data['projetosPermitidos'] as List<dynamic>?)?.join(', ') ?? 'N/A';
              final dataCriacao = (data['dataCriacao'] as Timestamp?)?.toDate();

              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  title: Text("Projetos: $projetosPermitidos", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Convidado: ${data['empresaConvidada']}"),
                      if (dataCriacao != null)
                        Text("Criado em: ${DateFormat('dd/MM/yyyy').format(dataCriacao)}"),
                      const SizedBox(height: 8),
                      _buildStatusChip(data['status']),
                    ],
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.lock_reset, color: Colors.red.shade700),
                    tooltip: "Revogar Acesso",
                    // Só pode revogar se não estiver revogada ainda
                    onPressed: data['status'] == 'revogada' ? null : () => _revogarAcesso(doc),
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
// lib/pages/gerente/gerenciar_equipe_page.dart (VERSÃO FINAL E CORRETA)

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'form_membro_equipe_page.dart';

class GerenciarEquipePage extends StatefulWidget {
  const GerenciarEquipePage({super.key});

  @override
  State<GerenciarEquipePage> createState() => _GerenciarEquipePageState();
}

class _GerenciarEquipePageState extends State<GerenciarEquipePage> {

  Future<void> _revogarAcesso(String uid, String nomeMembro) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Revogar Acesso?"),
        content: Text("Tem certeza que deseja remover o usuário '$nomeMembro' da sua equipe? Ele perderá o acesso imediatamente."),
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

    if (confirmar != true || !mounted) return;

    try {
      final licenseId = context.read<LicenseProvider>().licenseData?.id;
      if (licenseId == null) throw Exception("Licença não identificada.");

      await FirebaseFirestore.instance.collection('clientes').doc(licenseId).update({
        'usuariosPermitidos.$uid': FieldValue.delete(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Usuário removido com sucesso!"), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao remover usuário: $e"), backgroundColor: Colors.red)
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final licenseProvider = context.watch<LicenseProvider>();
    final licenseId = licenseProvider.licenseData?.id;

    if (licenseId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gerenciar Equipe')),
        body: const Center(child: Text('Erro: Licença do gerente não encontrada.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Equipe'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('clientes').doc(licenseId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Erro ao carregar dados da equipe: ${snapshot.error}"));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("Nenhum dado de equipe encontrado."));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final usuariosPermitidos = data['usuariosPermitidos'] as Map<String, dynamic>? ?? {};
          final uidGerente = licenseProvider.licenseData!.id;
          
          final membrosDaEquipe = usuariosPermitidos.entries
              .where((entry) => entry.key != uidGerente)
              .toList();
              
          if (membrosDaEquipe.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Nenhum membro na equipe ainda.\nUse o botão "+" para adicionar o primeiro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: membrosDaEquipe.length,
            itemBuilder: (context, index) {
              final membroEntry = membrosDaEquipe[index];
              final uid = membroEntry.key;
              
              // --- MUDANÇA PRINCIPAL AQUI ---
              // Converte o `value` para um mapa para acessar os campos internos.
              final membroData = membroEntry.value as Map<String, dynamic>;
              final nome = membroData['nome'] ?? 'Nome não disponível';
              final email = membroData['email'] ?? 'Email não disponível';
              final cargo = membroData['cargo'] ?? 'equipe';
              // -----------------------------
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(child: Icon(cargo == 'gerente' ? Icons.admin_panel_settings_outlined : Icons.person_outline)),
                  title: Text(nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Cargo: $cargo\nEmail: $email"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Revogar Acesso',
                    onPressed: () => _revogarAcesso(uid, nome),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const FormMembroEquipePage()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Novo Membro'),
      ),
    );
  }
}
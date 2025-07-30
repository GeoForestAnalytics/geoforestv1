// lib/pages/projetos/lista_projetos_page.dart (VERSÃO COM LÓGICA DE DELEGAÇÃO)

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Imports do projeto
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/pages/projetos/detalhes_projeto_page.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:geoforestv1/services/sync_service.dart';
import 'form_projeto_page.dart';

class ListaProjetosPage extends StatefulWidget {
  final String title;
  final bool isImporting;

  const ListaProjetosPage({
    super.key,
    required this.title,
    this.isImporting = false,
  });

  @override
  State<ListaProjetosPage> createState() => _ListaProjetosPageState();
}

class _ListaProjetosPageState extends State<ListaProjetosPage> {
  final dbHelper = DatabaseHelper.instance;
  List<Projeto> projetos = [];
  bool _isLoading = true;

  bool _isSelectionMode = false;
  final Set<int> _selectedProjetos = {};
  
  bool _isGerente = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUserRoleAndLoadProjects();
    });
  }

  Future<void> _checkUserRoleAndLoadProjects() async {
    final licenseProvider = context.read<LicenseProvider>();
    if (licenseProvider.licenseData == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _isGerente = licenseProvider.licenseData?.cargo == 'gerente';
      _isLoading = true;
    });

    List<Projeto> data;
    final licenseId = licenseProvider.licenseData!.id; 

    if (_isGerente) {
      data = await dbHelper.getTodosOsProjetosParaGerente();
    } else {
      data = await dbHelper.getTodosProjetos(licenseId);
    }

    if (mounted) {
      setState(() {
        projetos = data;
        _isLoading = false;
      });
    }
  }

  // <<< MUDANÇA 1: Nova função para DELEGAR um projeto (Ação do Gerente/Klabin) >>>
  Future<void> _delegarProjeto(Projeto projeto) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delegar Projeto"),
        content: Text("Você está prestes a gerar uma chave de delegação para o projeto '${projeto.nome}'. Esta chave pode ser compartilhada com uma empresa terceirizada para que ela realize a coleta de dados.\n\nDeseja continuar?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Gerar Chave")),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;
    setState(() => _isLoading = true);

    try {
      final licenseId = context.read<LicenseProvider>().licenseData!.id;
      final chaveId = const Uuid().v4();

      final chaveData = {
        "status": "pendente",
        "licenseIdConvidada": null,
        "empresaConvidada": "Aguardando Vínculo",
        "dataCriacao": FieldValue.serverTimestamp(),
        "projetosPermitidos": [projeto.id], // Armazena o ID numérico do projeto
      };

      await FirebaseFirestore.instance
          .collection('clientes').doc(licenseId)
          .collection('chavesDeDelegacao').doc(chaveId)
          .set(chaveData);
      
      if (!mounted) return;
      setState(() => _isLoading = false);

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("Chave Gerada com Sucesso!"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Envie esta chave para a empresa contratada:"),
              const SizedBox(height: 16),
              SelectableText(
                chaveId,
                style: const TextStyle(fontWeight: FontWeight.bold, backgroundColor: Colors.black12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: chaveId));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Chave copiada!")));
              },
              child: const Text("Copiar Chave"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Fechar"),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao gerar chave: $e"), backgroundColor: Colors.red));
      }
    }
  }

  // <<< MUDANÇA 2: Nova função para VINCULAR um projeto (Ação do Terceiro/Força) >>>
  Future<void> _vincularProjetoComChave(String chave) async {
    if (chave.trim().isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final query = FirebaseFirestore.instance.collectionGroup('chavesDeDelegacao').where(FieldPath.documentId, isEqualTo: chave.trim());
      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        throw Exception("Chave de delegação inválida ou não encontrada.");
      }

      final doc = snapshot.docs.first;
      if (doc.data()['status'] != 'pendente') {
        throw Exception("Esta chave já foi utilizada ou foi revogada.");
      }

      final licenseIdConvidada = context.read<LicenseProvider>().licenseData!.id;
      await doc.reference.update({
        'status': 'ativa',
        'licenseIdConvidada': licenseIdConvidada,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Projeto vinculado com sucesso! Sincronize para baixar os dados."),
        backgroundColor: Colors.green,
      ));
      
      // Aqui, você pode chamar a sincronização para baixar os novos projetos
      final syncService = SyncService();
      await syncService.sincronizarDados();
      await _checkUserRoleAndLoadProjects();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao vincular: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // <<< MUDANÇA 3: Diálogo para o Terceiro/Força inserir a chave >>>
  Future<void> _mostrarDialogoInserirChave() async {
    final controller = TextEditingController();
    final chave = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Vincular Projeto Delegado"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: "Cole a chave aqui"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text("Vincular")),
        ],
      ),
    );

    if (chave != null && chave.isNotEmpty && mounted) {
      Navigator.of(context).pop(); // Fecha o BottomSheet
      await _vincularProjetoComChave(chave);
    }
  }

  Future<void> _toggleArchiveStatus(Projeto projeto) async {
    // (Esta função permanece sem alterações)
    if (!_isGerente) return;

    final novoStatus = projeto.status == 'ativo' ? 'arquivado' : 'ativo';
    final acao = novoStatus == 'arquivado' ? 'Arquivar' : 'Reativar';

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$acao Projeto'),
        content: Text('Tem certeza que deseja $acao o projeto "${projeto.nome}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: novoStatus == 'arquivado' ? Colors.orange.shade700 : Colors.green.shade600,
            ),
            child: Text(acao),
          ),
        ],
      ),
    );

    if (confirmar == true && mounted) {
      setState(() => _isLoading = true);
      try {
        final projetoAtualizado = projeto.copyWith(status: novoStatus);
        final db = await dbHelper.database;
        await db.update('projetos', projetoAtualizado.toMap(), where: 'id = ?', whereArgs: [projeto.id]);

        final syncService = SyncService();
        await syncService.atualizarStatusProjetoNaFirebase(projeto.id!.toString(), novoStatus);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Projeto ${projeto.nome} foi atualizado para "$novoStatus".'), backgroundColor: Colors.green),
        );
        
        await _checkUserRoleAndLoadProjects();

      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao atualizar status: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _iniciarImportacao(Projeto projeto) async {
    // (Esta função permanece sem alterações)
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result == null || result.files.single.path == null) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Importação cancelada.')));
      return;
    }

    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text("Processando arquivo..."),
          ],
        ),
      ),
    );

    try {
      final file = File(result.files.single.path!);
      final csvContent = await file.readAsString();
      
      final message = await DatabaseHelper.instance.importarCsvUniversal(csvContent, projetoIdAlvo: projeto.id!);
      
      if (mounted) {
        Navigator.of(context).pop();
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Resultado da Importação'),
            content: SingleChildScrollView(child: Text(message)),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
          ),
        );
        Navigator.of(context).pop(); 
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao importar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _clearSelection() {
    // (Esta função permanece sem alterações)
    if (mounted) {
      setState(() {
        _selectedProjetos.clear();
        _isSelectionMode = false;
      });
    }
  }

  void _toggleSelection(int projetoId) {
    // (Esta função permanece sem alterações)
    if (mounted) {
      setState(() {
        if (_selectedProjetos.contains(projetoId)) {
          _selectedProjetos.remove(projetoId);
        } else {
          _selectedProjetos.add(projetoId);
        }
        _isSelectionMode = _selectedProjetos.isNotEmpty;
      });
    }
  }

  Future<void> _deletarProjetosSelecionados() async {
    // (Esta função permanece sem alterações)
    if (_selectedProjetos.isEmpty || !mounted) return;

    final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Confirmar Exclusão'),
              content: Text('Tem certeza que deseja apagar os ${_selectedProjetos.length} projetos selecionados e TODOS os seus dados? Esta ação é PERMANENTE.'),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Apagar')),
              ],
            ));
    if (confirmar == true && mounted) {
      for (final id in _selectedProjetos) {
        await dbHelper.deleteProjeto(id);
      }
      _clearSelection();
      await _checkUserRoleAndLoadProjects();
    }
  }

  void _navegarParaEdicao(Projeto projeto) async {
    // (Esta função permanece sem alterações)
    final bool? projetoEditado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FormProjetoPage(
          projetoParaEditar: projeto,
        ),
      ),
    );
    if (projetoEditado == true && mounted) {
      _checkUserRoleAndLoadProjects();
    }
  }
  
  void _navegarParaDetalhes(Projeto projeto) {
    // (Esta função permanece sem alterações)
    Navigator.push(context, MaterialPageRoute(builder: (context) => DetalhesProjetoPage(projeto: projeto)))
      .then((_) => _checkUserRoleAndLoadProjects());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : projetos.isEmpty
              ? _buildEmptyState()
              : _buildListView(),
      floatingActionButton: widget.isImporting ? null : _buildAddProjectButton(),
    );
  }
  
  Widget _buildListView() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: projetos.length,
      itemBuilder: (context, index) {
        final projeto = projetos[index];
        final isSelected = _selectedProjetos.contains(projeto.id!);
        final isArchived = projeto.status == 'arquivado';
        // <<< MUDANÇA 4: Adiciona a verificação se o projeto é delegado >>>
        final isDelegado = projeto.delegadoPorLicenseId != null;

        return Slidable(
          key: ValueKey(projeto.id),
          startActionPane: ActionPane(
            motion: const DrawerMotion(),
            // <<< MUDANÇA 5: O tamanho da action pane agora depende se tem o botão de delegar >>>
            extentRatio: _isGerente ? (isDelegado ? 0.25 : 0.75) : 0.25,
            children: [
              SlidableAction(
                onPressed: (_) => _navegarParaEdicao(projeto),
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                icon: Icons.edit_outlined,
                label: 'Editar',
              ),
              if (_isGerente)
                SlidableAction(
                  onPressed: (_) => _toggleArchiveStatus(projeto),
                  backgroundColor: isArchived ? Colors.green.shade600 : Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  icon: isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
                  label: isArchived ? 'Reativar' : 'Arquivar',
                ),
              // <<< MUDANÇA 6: O botão de delegar só aparece para o gerente e se não for um projeto já delegado >>>
              if (_isGerente && !isDelegado)
                SlidableAction(
                  onPressed: (_) => _delegarProjeto(projeto),
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  icon: Icons.handshake_outlined,
                  label: 'Delegar',
                ),
            ],
          ),
          child: Card(
            color: isArchived ? Colors.grey.shade300 : (isSelected ? Colors.lightBlue.shade100 : null),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              onTap: () {
                if (widget.isImporting) {
                  _iniciarImportacao(projeto);
                } else if (_isSelectionMode) {
                  _toggleSelection(projeto.id!);
                } else {
                  _navegarParaDetalhes(projeto);
                }
              },
              onLongPress: () => _toggleSelection(projeto.id!),
              // <<< MUDANÇA 7: Ícone e subtítulo dinâmicos baseados no status de delegação >>>
              leading: Icon(
                isSelected ? Icons.check_circle : 
                isArchived ? Icons.archive_rounded :
                isDelegado ? Icons.handshake_outlined : Icons.folder_outlined,
                color: isDelegado ? Colors.teal : (isArchived ? Colors.grey.shade700 : Theme.of(context).primaryColor),
              ),
              title: Text(projeto.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(isDelegado ? "Projeto Delegado" : 'Responsável: ${projeto.responsavel}'),
              trailing: Text(DateFormat('dd/MM/yy').format(projeto.dataCriacao)),
            ),
          ),
        );
      },
    );
  }

  AppBar _buildNormalAppBar() {
    return AppBar(
      title: Text(widget.title),
    );
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection),
      title: Text('${_selectedProjetos.length} selecionados'),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: _deletarProjetosSelecionados,
          tooltip: 'Apagar Selecionados',
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.folder_off_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Nenhum projeto encontrado.', style: TextStyle(fontSize: 18)),
          if (!widget.isImporting)
            const Text('Use o botão "+" para adicionar um novo.', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  // <<< MUDANÇA 8: O FAB agora mostra um menu de opções >>>
  Widget _buildAddProjectButton() {
    return FloatingActionButton(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          builder: (ctx) => Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Criar Novo Projeto'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const FormProjetoPage()))
                    .then((criado) {
                      if (criado == true) _checkUserRoleAndLoadProjects();
                    });
                },
              ),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('Vincular Projeto Delegado'),
                subtitle: const Text('Insira a chave fornecida pelo seu cliente'),
                onTap: () => _mostrarDialogoInserirChave(),
              ),
            ],
          ),
        );
      },
      tooltip: 'Adicionar',
      child: const Icon(Icons.add),
    );
  }
}
// lib/pages/projetos/lista_projetos_page.dart (VERSÃO COM SOFT DELETE)

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cloud_functions/cloud_functions.dart';

// Imports do projeto
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/pages/projetos/detalhes_projeto_page.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:geoforestv1/data/repositories/import_repository.dart';
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
  final _projetoRepository = ProjetoRepository();
  final _importRepository = ImportRepository();
  final _syncService = SyncService();
  
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
      data = await _projetoRepository.getTodosOsProjetosParaGerente();
    } else {
      data = await _projetoRepository.getTodosProjetos(licenseId);
    }
    
    final projetosVisiveis = data.where((p) => p.status != 'deletado').toList();

    if (mounted) {
      setState(() {
        projetos = projetosVisiveis;
        _isLoading = false;
      });
    }
  }

  Future<void> _deletarProjetosSelecionados() async {
    if (_selectedProjetos.isEmpty || !mounted) return;
    if (!_isGerente) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Apenas gerentes podem apagar projetos.')));
      return;
    }

    final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Confirmar Exclusão'),
              content: Text('Tem certeza que deseja apagar os ${_selectedProjetos.length} projetos selecionados? Eles serão movidos para a lixeira e não aparecerão mais no aplicativo.'),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Apagar')),
              ],
            ));
            
    if (confirmar != true) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enviando ordem de exclusão para o servidor...'),
          duration: Duration(seconds: 10)));
    }
    
    bool houveErro = false;
    for (final id in _selectedProjetos) {
      try {
        final functions = FirebaseFunctions.instanceFor(region: 'southamerica-east1');
        final callable = functions.httpsCallable('deletarProjeto' );
        await callable.call({'projetoId': id});
        
        final projetoLocal = await _projetoRepository.getProjetoById(id);
        if (projetoLocal != null) {
          await _projetoRepository.updateProjeto(projetoLocal.copyWith(status: 'deletado'));
        }

      } catch (e) {
        houveErro = true;
        debugPrint("Erro ao apagar projeto $id: $e");
        if(mounted) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(
             content: Text('Falha ao apagar o projeto $id: ${(e as FirebaseFunctionsException).message}'),
             backgroundColor: Colors.red,
           ));
        }
        break; 
      }
    }
    
    if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        if (!houveErro) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Projetos movidos para a lixeira com sucesso!'), backgroundColor: Colors.green));
        }
    }
    _clearSelection();
    await _checkUserRoleAndLoadProjects();
  }
  
  Future<void> _delegarProjeto(Projeto projeto) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delegar Projeto"),
        content: Text("Você gerará uma chave de acesso para o projeto '${projeto.nome}'. Compartilhe esta chave com a empresa contratada para que ela possa coletar e sincronizar os dados para você.\n\nDeseja continuar?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Gerar Chave")),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;
    setState(() => _isLoading = true);

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'southamerica-east1');
      final callable = functions.httpsCallable('delegarProjeto' );
      final result = await callable.call(<String, dynamic>{
        'projetoId': projeto.id,
        'nomeProjeto': projeto.nome,
      });

      final chave = result.data['chave'];
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
              SelectableText(chave, style: const TextStyle(fontWeight: FontWeight.bold, backgroundColor: Colors.black12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: chave));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Chave copiada!")));
              },
              child: const Text("Copiar Chave"),
            ),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Fechar")),
          ],
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro [${e.code}]: ${e.message}"), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro inesperado: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _vincularProjetoComChave(String chave) async {
    if (chave.trim().isEmpty) return;
    Navigator.of(context).pop();
    setState(() => _isLoading = true);

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'southamerica-east1');
      final callable = functions.httpsCallable('vincularProjetoDelegado' );
      await callable.call({'chave': chave.trim()});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Projeto vinculado! Sincronizando para baixar os dados..."),
        backgroundColor: Colors.green,
      ));
      
      await _syncService.sincronizarDados();
      await _checkUserRoleAndLoadProjects();

    } on FirebaseFunctionsException catch (e) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro [${e.code}]: ${e.message}"), backgroundColor: Colors.red));
      }
    } catch (e) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro inesperado: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
      await _vincularProjetoComChave(chave);
    }
  }

  Future<void> _toggleArchiveStatus(Projeto projeto) async {
    final novoStatus = projeto.status == 'ativo' ? 'arquivado' : 'ativo';
    final projetoAtualizado = projeto.copyWith(status: novoStatus);
    await _projetoRepository.updateProjeto(projetoAtualizado);
    await _syncService.atualizarStatusProjetoNaFirebase(projeto.id.toString(), novoStatus);
    _checkUserRoleAndLoadProjects();
  }

  Future<void> _iniciarImportacao(Projeto projeto) async {
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
      
      final message = await _importRepository.importarCsvUniversal(csvContent, projetoIdAlvo: projeto.id!);
      
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
    if (mounted) {
      setState(() {
        _selectedProjetos.clear();
        _isSelectionMode = false;
      });
    }
  }

  void _toggleSelection(int projetoId) {
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

  void _navegarParaEdicao(Projeto projeto) async {
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
        final isDelegado = projeto.delegadoPorLicenseId != null;

        return Slidable(
          key: ValueKey(projeto.id),
          startActionPane: ActionPane(
            motion: const DrawerMotion(),
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
    return AppBar(title: Text(widget.title));
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection),
      title: Text('${_selectedProjetos.length} selecionados'),
      actions: [
        IconButton(icon: const Icon(Icons.delete_outline), onPressed: _deletarProjetosSelecionados, tooltip: 'Apagar Selecionados'),
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

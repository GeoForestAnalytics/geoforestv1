// lib/pages/atividades/atividades_page.dart (VERSÃO FINAL COM GO_ROUTER CORRIGIDO)

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart'; // Importa o go_router
import 'package:intl/intl.dart';

// Imports de modelos e repositórios
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';

// Imports das páginas
// import 'detalhes_atividade_page.dart'; // Não é mais necessário navegar diretamente
import 'form_atividade_page.dart';


class AtividadesPage extends StatefulWidget {
  final int projetoId;

  const AtividadesPage({
    super.key,
    required this.projetoId,
  });

  @override
  State<AtividadesPage> createState() => _AtividadesPageState();
}

class _AtividadesPageState extends State<AtividadesPage> {
  final _atividadeRepository = AtividadeRepository();
  final _projetoRepository = ProjetoRepository();

  late Future<Projeto?> _projetoFuture;
  late Future<List<Atividade>> _atividadesFuture;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  void _carregarDados() {
    setState(() {
      _projetoFuture = _projetoRepository.getProjetoById(widget.projetoId);
      _atividadesFuture = _atividadeRepository.getAtividadesDoProjeto(widget.projetoId);
    });
  }

  Future<void> _mostrarDialogoDeConfirmacao(Atividade atividade) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar Exclusão'),
          content: Text('Tem certeza que deseja excluir a atividade "${atividade.tipo}" e todos os seus dados?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Excluir'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
    
    if (confirmar == true && mounted) {
      await _atividadeRepository.deleteAtividade(atividade.id!);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Atividade excluída com sucesso!'), backgroundColor: Colors.red),
      );
      _carregarDados();
    }
  }

  void _navegarParaFormularioAtividade() async {
    final bool? atividadeCriada = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FormAtividadePage(projetoId: widget.projetoId),
      ),
    );
    if (atividadeCriada == true && mounted) {
      _carregarDados();
    }
  }
  
  void _navegarParaEdicao(Atividade atividade) async {
    final bool? atividadeEditada = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FormAtividadePage(
          projetoId: atividade.projetoId,
          atividadeParaEditar: atividade,
        ),
      ),
    );
    if (atividadeEditada == true && mounted) {
      _carregarDados();
    }
  }
  
  // ✅ NAVEGAÇÃO FINALMENTE CORRIGIDA
  // Agora usa a rota hierárquica que definimos no app_router.dart
  void _navegarParaDetalhes(Atividade atividade) {
    context.go('/projetos/${widget.projetoId}/atividades/${atividade.id}');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Projeto?>(
      future: _projetoFuture,
      builder: (context, projetoSnapshot) {
        if (projetoSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        }
        if (projetoSnapshot.hasError || !projetoSnapshot.hasData || projetoSnapshot.data == null) {
          return Scaffold(appBar: AppBar(title: const Text('Erro')), body: const Center(child: Text('Não foi possível carregar o projeto.')));
        }

        final projeto = projetoSnapshot.data!;

        return Scaffold(
          appBar: AppBar(
            title: Text('Atividades de ${projeto.nome}'),
            centerTitle: true,
          ),
          body: FutureBuilder<List<Atividade>>(
            future: _atividadesFuture,
            builder: (context, atividadesSnapshot) {
              if (atividadesSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (atividadesSnapshot.hasError) {
                return Center(child: Text('Erro ao carregar atividades: ${atividadesSnapshot.error}'));
              }
              if (!atividadesSnapshot.hasData || atividadesSnapshot.data!.isEmpty) {
                return const Center(
                  child: Text(
                    'Nenhuma atividade encontrada.\nToque no botão + para adicionar a primeira!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                );
              }

              final atividades = atividadesSnapshot.data!;

              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: atividades.length,
                itemBuilder: (context, index) {
                  final atividade = atividades[index];
                  
                  return Slidable(
                    key: ValueKey(atividade.id),
                    startActionPane: ActionPane(
                      motion: const DrawerMotion(),
                      extentRatio: 0.25,
                      children: [
                        SlidableAction(
                          onPressed: (_) => _navegarParaEdicao(atividade),
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          icon: Icons.edit_outlined,
                          label: 'Editar',
                        ),
                      ],
                    ),
                    endActionPane: ActionPane(
                      motion: const StretchMotion(),
                      children: [
                        SlidableAction(
                          onPressed: (_) => _mostrarDialogoDeConfirmacao(atividade),
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          icon: Icons.delete_outline,
                          label: 'Excluir',
                        ),
                      ],
                    ),
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(child: Text((index + 1).toString())),
                        title: Text(
                          atividade.tipo,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${atividade.descricao.isNotEmpty ? atividade.descricao : 'Sem descrição'}\nCriado em: ${DateFormat('dd/MM/yyyy HH:mm').format(atividade.dataCriacao)}',
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                        onTap: () => _navegarParaDetalhes(atividade), // <-- A chamada correta está aqui
                      ),
                    ),
                  );
                },
              );
            },
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _navegarParaFormularioAtividade,
            icon: const Icon(Icons.add),
            label: const Text('Nova Atividade'),
            tooltip: 'Adicionar Nova Atividade',
          ),
        );
      },
    );
  }
}
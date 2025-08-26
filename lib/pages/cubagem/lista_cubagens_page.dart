// lib/pages/cubagem/lista_cubagens_page.dart (VERSÃO COMPLETA E REFATORADA)

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/pages/cubagem/cubagem_dados_page.dart';

// --- NOVO IMPORT DO REPOSITÓRIO ---
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
// ------------------------------------

class ListaCubagensPage extends StatefulWidget {
  final Talhao talhao;
  const ListaCubagensPage({super.key, required this.talhao});

  @override
  State<ListaCubagensPage> createState() => _ListaCubagensPageState();
}

class _ListaCubagensPageState extends State<ListaCubagensPage> {
  late Future<List<CubagemArvore>> _cubagensFuture;
  
  // --- INSTÂNCIA DO NOVO REPOSITÓRIO ---
  final _cubagemRepository = CubagemRepository();
  // ---------------------------------------

  @override
  void initState() {
    super.initState();
    _carregarCubagens();
  }

  // --- MÉTODO ATUALIZADO ---
  void _carregarCubagens() {
    setState(() {
      // Usa o CubagemRepository
      _cubagensFuture = _cubagemRepository.getTodasCubagensDoTalhao(widget.talhao.id!);
    });
  }

  Future<void> _navegarParaDadosCubagem(CubagemArvore arvore) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CubagemDadosPage(
          metodo: "Relativas", // Pode ser dinâmico se você tiver essa lógica
          arvoreParaEditar: arvore,
        ),
      ),
    );
    _carregarCubagens();
  }

  // O método build permanece o mesmo.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cubagem: ${widget.talhao.nome}'),
      ),
      body: FutureBuilder<List<CubagemArvore>>(
        future: _cubagensFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar plano: ${snapshot.error}'));
          }
          final cubagens = snapshot.data ?? [];
          if (cubagens.isEmpty) {
            return const Center(
              child: Text(
                'Nenhum plano de cubagem encontrado para este talhão.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.builder(
            itemCount: cubagens.length,
            itemBuilder: (context, index) {
              final arvore = cubagens[index];
              final isConcluida = arvore.alturaTotal > 0;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isConcluida ? Colors.green : Colors.grey,
                    child: Icon(
                      isConcluida ? Icons.check : Icons.pending_outlined,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(arvore.identificador),
                  subtitle: Text('Classe Diamétrica: ${arvore.classe ?? "N/A"}'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => _navegarParaDadosCubagem(arvore),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
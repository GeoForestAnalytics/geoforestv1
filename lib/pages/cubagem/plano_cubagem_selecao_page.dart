// lib/pages/cubagem/plano_cubagem_selecao_page.dart (VERSÃO COMPLETA E REFATORADA)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/services/analysis_service.dart';

// --- NOVOS IMPORTS DOS REPOSITÓRIOS ---
import 'package:geoforestv1/data/repositories/fazenda_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/data/repositories/analise_repository.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
// ------------------------------------

class PlanoCubagemSelecaoPage extends StatefulWidget {
  final Atividade atividadeDeOrigem;
  const PlanoCubagemSelecaoPage({super.key, required this.atividadeDeOrigem});

  @override
  State<PlanoCubagemSelecaoPage> createState() => _PlanoCubagemSelecaoPageState();
}

class _PlanoCubagemSelecaoPageState extends State<PlanoCubagemSelecaoPage> {
  // --- INSTÂNCIAS DOS NOVOS REPOSITÓRIOS ---
  final _fazendaRepository = FazendaRepository();
  final _talhaoRepository = TalhaoRepository();
  final _analiseRepository = AnaliseRepository();
  final _atividadeRepository = AtividadeRepository();
  final _cubagemRepository = CubagemRepository();
  // ---------------------------------------

  List<Fazenda> _fazendasDisponiveis = [];
  Map<String, List<Talhao>> _talhoesPorFazenda = {};
  
  final Set<String> _fazendasSelecionadas = {};
  final Set<int> _talhoesSelecionados = {};

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _isLoading = true);
    final fazendas = await _fazendaRepository.getFazendasDaAtividade(widget.atividadeDeOrigem.id!);
    final talhoesPorFazenda = <String, List<Talhao>>{};
    for (final fazenda in fazendas) {
      final talhoes = await _talhaoRepository.getTalhoesDaFazenda(fazenda.id, fazenda.atividadeId);
      final talhoesComDados = <Talhao>[];
      for (final talhao in talhoes) {
        final dadosAgregados = await _analiseRepository.getDadosAgregadosDoTalhao(talhao.id!);
        if ((dadosAgregados['parcelas'] as List).isNotEmpty) {
           talhoesComDados.add(talhao);
        }
      }
      if (talhoesComDados.isNotEmpty) {
        talhoesPorFazenda[fazenda.id] = talhoesComDados;
      }
    }
    
    if (mounted) {
      setState(() {
        _fazendasDisponiveis = fazendas.where((f) => talhoesPorFazenda.containsKey(f.id)).toList();
        _talhoesPorFazenda = talhoesPorFazenda;
        _isLoading = false;
      });
    }
  }

  void _toggleFazenda(String fazendaId, bool? isSelected) {
    setState(() {
      if (isSelected == true) {
        _fazendasSelecionadas.add(fazendaId);
        _talhoesPorFazenda[fazendaId]?.forEach((talhao) {
          _talhoesSelecionados.add(talhao.id!);
        });
      } else {
        _fazendasSelecionadas.remove(fazendaId);
        _talhoesPorFazenda[fazendaId]?.forEach((talhao) {
          _talhoesSelecionados.remove(talhao.id!);
        });
      }
    });
  }
  
  void _toggleTalhao(int talhaoId, bool? isSelected) {
    setState(() {
      if (isSelected == true) {
        _talhoesSelecionados.add(talhaoId);
      } else {
        _talhoesSelecionados.remove(talhaoId);
      }
    });
  }

  void _proximoPasso() async {
     if (_talhoesSelecionados.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Selecione pelo menos um talhão.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final totalParaCubarStr = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Definir Quantidade'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Nº total de árvores para cubar', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Gerar Plano')),
          ],
        );
      },
    );
    
    final int? totalParaCubar = int.tryParse(totalParaCubarStr ?? '');
    if (totalParaCubar == null || totalParaCubar <= 0) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gerando atividade de cubagem...'), duration: Duration(seconds: 5),));
    
    try {
      final novaAtividadeCubagem = Atividade(
        projetoId: widget.atividadeDeOrigem.projetoId, 
        tipo: 'Cubagem (Baseado em ${widget.atividadeDeOrigem.tipo})', 
        descricao: 'Plano gerado em ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', 
        dataCriacao: DateTime.now()
      );
      final novaAtividadeId = await _atividadeRepository.insertAtividade(novaAtividadeCubagem);

      for (final talhaoId in _talhoesSelecionados) {
        final talhaoOriginal = _talhoesPorFazenda.values.expand((t) => t).firstWhere((t) => t.id == talhaoId);
        await _cubagemRepository.gerarPlanoDeCubagemNoBanco(talhaoOriginal, totalParaCubar, novaAtividadeId, AnalysisService());
      }
      
      if(!mounted) return;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nova atividade de cubagem criada com sucesso!'), backgroundColor: Colors.green,));
      Navigator.of(context).popUntil((route) => route.isFirst);

    } catch (e) {
      if(!mounted) return;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao gerar plano: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gerar Plano: Seleção')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _fazendasDisponiveis.isEmpty
              ? const Center(child: Text('Nenhuma fazenda com dados de inventário encontrada nesta atividade.'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text('Selecione as fazendas e talhões que servirão de base para o plano de cubagem.', style: Theme.of(context).textTheme.titleMedium,),
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _fazendasDisponiveis.length,
                        itemBuilder: (context, index) {
                           final fazenda = _fazendasDisponiveis[index];
                           final talhoesDaFazenda = _talhoesPorFazenda[fazenda.id] ?? [];
                           return ExpansionTile(
                             leading: Checkbox(
                               value: _fazendasSelecionadas.contains(fazenda.id),
                               onChanged: (value) => _toggleFazenda(fazenda.id, value),
                             ),
                             title: Text(fazenda.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                             initiallyExpanded: true,
                             children: talhoesDaFazenda.map((talhao) {
                               return Padding(
                                 padding: const EdgeInsets.only(left: 32.0),
                                 child: CheckboxListTile(
                                   title: Text(talhao.nome),
                                   value: _talhoesSelecionados.contains(talhao.id!),
                                   onChanged: (value) => _toggleTalhao(talhao.id!, value),
                                   controlAffinity: ListTileControlAffinity.leading,
                                 ),
                               );
                             }).toList(),
                           );
                        },
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _proximoPasso,
        icon: const Icon(Icons.arrow_forward),
        label: const Text('Avançar'),
      ),
    );
  }
}
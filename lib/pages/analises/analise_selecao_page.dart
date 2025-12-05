// lib/pages/analises/analise_selecao_page.dart (VERSÃO ATUALIZADA COM FILTROS HIERÁRQUICOS)

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/pages/dashboard/relatorio_comparativo_page.dart';
import 'package:geoforestv1/pages/analises/analise_volumetrica_page.dart';
import 'package:geoforestv1/pages/dashboard/estrato_dashboard_page.dart';

// Repositórios
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/data/repositories/fazenda_repository.dart';

class AnaliseSelecaoPage extends StatefulWidget {
  const AnaliseSelecaoPage({super.key});

  @override
  State<AnaliseSelecaoPage> createState() => _AnaliseSelecaoPageState();
}

class _AnaliseSelecaoPageState extends State<AnaliseSelecaoPage> {
  // Repositórios
  final _projetoRepository = ProjetoRepository();
  final _atividadeRepository = AtividadeRepository();
  final _fazendaRepository = FazendaRepository();
  final _talhaoRepository = TalhaoRepository();

  // Listas para popular os dropdowns
  List<Projeto> _projetosDisponiveis = [];
  List<Atividade> _atividadesDisponiveis = [];
  List<Fazenda> _fazendasDisponiveis = [];
  List<Talhao> _talhoesDisponiveis = [];

  // Itens selecionados nos filtros
  Projeto? _projetoSelecionado;
  Atividade? _atividadeSelecionada;
  Fazenda? _fazendaSelecionada;

  // Lista final de talhões selecionados para a análise
  final Set<int> _talhoesSelecionados = {};

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarProjetos();
  }

  // --- LÓGICA DE CARREGAMENTO EM CASCATA ---

  Future<void> _carregarProjetos() async {
    setState(() => _isLoading = true);
    // Busca todos os projetos que são de inventário e têm dados concluídos
    final talhoesCompletos = await _talhaoRepository.getTalhoesComParcelasConcluidas();
    if (talhoesCompletos.isEmpty) {
       if(mounted) setState(() { _projetosDisponiveis = []; _isLoading = false; });
       return;
    }

    final todosProjetos = await _projetoRepository.getTodosOsProjetosParaGerente();
    final projetosIdsComDados = <int>{};

    for (var talhao in talhoesCompletos) {
      if(talhao.projetoId != null) {
        projetosIdsComDados.add(talhao.projetoId!);
      }
    }
    
    if (mounted) {
      setState(() {
        _projetosDisponiveis = todosProjetos.where((p) => projetosIdsComDados.contains(p.id)).toList();
        _isLoading = false;
      });
    }
  }
  
  void _gerarAnaliseEstrato() {
    if (_talhoesSelecionados.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Selecione pelo menos 2 talhões para formar um estrato.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    
    final talhoesParaAnalisar = _talhoesDisponiveis.where((t) => _talhoesSelecionados.contains(t.id)).toList();
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EstratoDashboardPage(talhoesSelecionados: talhoesParaAnalisar),
      ),
    );
  }

  Future<void> _onProjetoSelecionado(Projeto? projeto) async {
    setState(() {
      _projetoSelecionado = projeto;
      _atividadeSelecionada = null;
      _fazendaSelecionada = null;
      _atividadesDisponiveis = [];
      _fazendasDisponiveis = [];
      _talhoesDisponiveis = [];
      _talhoesSelecionados.clear();
      if (projeto == null) return;
      _isLoading = true;
    });

    final atividades = await _atividadeRepository.getAtividadesDoProjeto(projeto!.id!);
    // Filtra para mostrar apenas atividades de inventário
    final tiposInventario = ["IPC", "IFC", "IFS", "BIO", "IFQ"];
    _atividadesDisponiveis = atividades.where((a) => tiposInventario.any((tipo) => a.tipo.toUpperCase().contains(tipo))).toList();
    
    setState(() => _isLoading = false);
  }

  Future<void> _onAtividadeSelecionada(Atividade? atividade) async {
    setState(() {
      _atividadeSelecionada = atividade;
      _fazendaSelecionada = null;
      _fazendasDisponiveis = [];
      _talhoesDisponiveis = [];
      _talhoesSelecionados.clear();
      if (atividade == null) return;
      _isLoading = true;
    });
    
    _fazendasDisponiveis = await _fazendaRepository.getFazendasDaAtividade(atividade!.id!);
    setState(() => _isLoading = false);
  }

  Future<void> _onFazendaSelecionada(Fazenda? fazenda) async {
    setState(() {
      _fazendaSelecionada = fazenda;
      _talhoesDisponiveis = [];
      _talhoesSelecionados.clear();
      if (fazenda == null) return;
      _isLoading = true;
    });

    final todosTalhoesDaFazenda = await _talhaoRepository.getTalhoesDaFazenda(fazenda!.id, fazenda.atividadeId);
    final talhoesCompletosIds = (await _talhaoRepository.getTalhoesComParcelasConcluidas()).map((t) => t.id).toSet();

    _talhoesDisponiveis = todosTalhoesDaFazenda.where((t) => talhoesCompletosIds.contains(t.id)).toList();
    setState(() => _isLoading = false);
  }
  
  void _toggleTalhao(int talhaoId, bool? isSelected) {
    if (isSelected == null) return;
    setState(() {
      if (isSelected) {
        _talhoesSelecionados.add(talhaoId);
      } else {
        _talhoesSelecionados.remove(talhaoId);
      }
    });
  }

  void _gerarRelatorio() {
    if (_talhoesSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Selecione pelo menos um talhão para gerar a análise.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    final talhoesParaAnalisar = _talhoesDisponiveis.where((t) => _talhoesSelecionados.contains(t.id)).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RelatorioComparativoPage(talhoesSelecionados: talhoesParaAnalisar),
      ),
    );
  }

  void _navegarParaAnaliseVolumetrica() {
    // 1. Coleta os objetos Talhao baseados nos IDs selecionados
    final talhoesParaEnviar = _talhoesDisponiveis
        .where((t) => _talhoesSelecionados.contains(t.id))
        .toList();

    Navigator.push(
      context, 
      MaterialPageRoute(
        builder: (context) => AnaliseVolumetricaPage(
          // 2. Passa a lista (se estiver vazia, passa null ou lista vazia, a outra tela trata)
          talhoesPreSelecionados: talhoesParaEnviar.isNotEmpty ? talhoesParaEnviar : null,
        )
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GeoForest Analista')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- NOVOS DROPDOWNS HIERÁRQUICOS ---
            DropdownButtonFormField<Projeto>(
              value: _projetoSelecionado,
              hint: const Text('1. Selecione um Projeto'),
              isExpanded: true,
              items: _projetosDisponiveis.map((p) => DropdownMenuItem(value: p, child: Text(p.nome, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _onProjetoSelecionado,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<Atividade>(
              value: _atividadeSelecionada,
              hint: const Text('2. Selecione uma Atividade'),
              isExpanded: true,
              // Desabilita se o projeto não foi selecionado
              disabledHint: const Text('Selecione um projeto primeiro'),
              items: _atividadesDisponiveis.map((a) => DropdownMenuItem(value: a, child: Text(a.tipo, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _projetoSelecionado == null ? null : _onAtividadeSelecionada,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            
            DropdownButtonFormField<Fazenda>(
              value: _fazendaSelecionada,
              hint: const Text('3. Selecione uma Fazenda'),
              isExpanded: true,
              disabledHint: const Text('Selecione uma atividade primeiro'),
              items: _fazendasDisponiveis.map((f) => DropdownMenuItem(value: f, child: Text(f.nome, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _atividadeSelecionada == null ? null : _onFazendaSelecionada,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            const Text('4. Selecione os Talhões para Análise Comparativa', style: TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _talhoesDisponiveis.isEmpty
                      ? const Center(child: Text('Nenhum talhão com parcelas concluídas para os filtros selecionados.'))
                      : ListView(
                          children: _talhoesDisponiveis.map((talhao) {
                            return CheckboxListTile(
                              title: Text(talhao.nome),
                              value: _talhoesSelecionados.contains(talhao.id!),
                              onChanged: (value) => _toggleTalhao(talhao.id!, value),
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          }).toList(),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // BOTÃO 1: Equação de Volume
          FloatingActionButton.extended(
            onPressed: _navegarParaAnaliseVolumetrica,
            heroTag: 'analiseVolumetricaFab',
            label: const Text('Equação de Volume'),
            icon: const Icon(Icons.calculate_outlined),
            backgroundColor: const Color(0xFFEBE4AB), 
            foregroundColor: const Color(0xFF023853),
          ),
          const SizedBox(height: 16),

          // BOTÃO 2 (NOVO): Análise de Estrato (Aqui usamos a sua função!)
          FloatingActionButton.extended(
            onPressed: _gerarAnaliseEstrato, // <--- Chamando a função que estava parada
            heroTag: 'analiseEstratoFab',
            label: const Text('Análise de Estrato'),
            icon: const Icon(Icons.layers_outlined),
            // Cor verde para diferenciar (indica consolidação)
            backgroundColor: Colors.teal.shade700, 
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 16),

          // BOTÃO 3: Análise Comparativa
          FloatingActionButton.extended(
            onPressed: _gerarRelatorio,
            heroTag: 'analiseComparativaFab',
            label: const Text('Análise Comparativa'),
            icon: const Icon(Icons.analytics_outlined),
            backgroundColor: const Color(0xFF023853),
            foregroundColor: const Color(0xFFEBE4AB),
          ),
        ],
      ),
    );
  }
}
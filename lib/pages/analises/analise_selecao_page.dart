// lib/pages/analises/analise_selecao_page.dart (VERSÃO COMPLETA E FINAL)

import 'package:flutter/material.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/pages/dashboard/relatorio_comparativo_page.dart';
import 'package:geoforestv1/pages/analises/analise_volumetrica_page.dart'; // Import restaurado e usado
import 'package:geoforestv1/pages/dashboard/estrato_dashboard_page.dart';

// Repositórios
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/data/repositories/fazenda_repository.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/analise_repository.dart';

// Serviços
import 'package:geoforestv1/services/ai_validation_service.dart'; 
import 'package:geoforestv1/widgets/progress_dialog.dart';

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
  final _analiseRepository = AnaliseRepository();
  final _parcelaRepository = ParcelaRepository();

  // Listas para popular os dropdowns
  List<Projeto> _projetosDisponiveis = [];
  List<Atividade> _atividadesDisponiveis = [];
  List<Fazenda> _fazendasDisponiveis = [];
  List<Talhao> _talhoesDisponiveis = [];

  // Itens selecionados nos filtros
  Projeto? _projetoSelecionado;
  Atividade? _atividadeSelecionada;
  Fazenda? _fazendaSelecionada;

  // Lista final de talhões selecionados (Isso forma o ESTRATO)
  final Set<int> _talhoesSelecionados = {};

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarProjetos();
  }

  Future<void> _carregarProjetos() async {
    setState(() => _isLoading = true);
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

  // --- Lógica de Filtros ---
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

  // --- AÇÕES PRINCIPAIS ---

  // 1. Gera o Dashboard de Estrato (Média Ponderada dos Talhões Selecionados)
  void _gerarAnaliseEstrato() {
    if (_talhoesSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Selecione pelo menos um talhão para formar o estrato.'),
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

  // 2. Relatório Comparativo (Tabela lado a lado)
  void _gerarRelatorioComparativo() {
    if (_talhoesSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Selecione os talhões para comparar.'),
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

  // 3. Auditoria com IA (Verifica o Estrato Selecionado)
  Future<void> _executarAuditoriaIA() async {
    if (_talhoesSelecionados.isEmpty) return;

    ProgressDialog.show(context, 'A IA está auditando o estrato selecionado...');

    final aiService = AiValidationService();
    List<String> relatorioGeral = [];
    int totalProblemas = 0;

    try {
      for (int talhaoId in _talhoesSelecionados) {
        final talhao = _talhoesDisponiveis.firstWhere((t) => t.id == talhaoId);
        final dados = await _analiseRepository.getDadosAgregadosDoTalhao(talhaoId);
        final parcelas = dados['parcelas'] as List;
        
        for (var p in parcelas) {
          final arvores = await _parcelaRepository.getArvoresDaParcela(p.dbId);
          if (arvores.isNotEmpty) {
            final alertas = await aiService.validarParcelaInteligente(p, arvores);
            if (alertas.isNotEmpty) {
              totalProblemas += alertas.length;
              relatorioGeral.add("\n📍 ${talhao.nome} - P${p.idParcela}");
              relatorioGeral.addAll(alertas.map((a) => "  • $a"));
            }
          }
        }
      }

      if (!mounted) return;
      ProgressDialog.hide(context);

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(totalProblemas == 0 ? Icons.check_circle : Icons.auto_awesome, 
                   color: totalProblemas == 0 ? Colors.green : Colors.deepPurple),
              const SizedBox(width: 10),
              const Text("Auditoria do Estrato"),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: relatorioGeral.isEmpty 
              ? const Text("✅ Nenhuma inconsistência encontrada neste estrato.")
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Pontos de atenção no estrato ($totalProblemas):", style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Divider(),
                      ...relatorioGeral.map((linha) => Text(linha, style: TextStyle(
                        fontWeight: linha.startsWith("\n📍") ? FontWeight.bold : FontWeight.normal,
                        color: linha.startsWith("\n📍") ? Colors.blue[800] : Colors.black87
                      ))),
                    ],
                  ),
                ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Fechar"))],
        ),
      );

    } catch (e) {
      if (mounted) {
        ProgressDialog.hide(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro na IA: $e"), backgroundColor: Colors.red));
      }
    }
  }

  // 4. Navegar para Análise Volumétrica
  void _navegarParaAnaliseVolumetrica() {
    Navigator.push(
      context, 
      MaterialPageRoute(builder: (context) => const AnaliseVolumetricaPage())
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Análise de Estrato')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Filtros Hierárquicos
            DropdownButtonFormField<Projeto>(
              value: _projetoSelecionado,
              hint: const Text('1. Projeto'),
              isExpanded: true,
              items: _projetosDisponiveis.map((p) => DropdownMenuItem(value: p, child: Text(p.nome, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _onProjetoSelecionado,
              decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5)),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<Atividade>(
              value: _atividadeSelecionada,
              hint: const Text('2. Atividade'),
              isExpanded: true,
              items: _atividadesDisponiveis.map((a) => DropdownMenuItem(value: a, child: Text(a.tipo, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _projetoSelecionado == null ? null : _onAtividadeSelecionada,
              decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5)),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<Fazenda>(
              value: _fazendaSelecionada,
              hint: const Text('3. Fazenda'),
              isExpanded: true,
              items: _fazendasDisponiveis.map((f) => DropdownMenuItem(value: f, child: Text(f.nome, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _atividadeSelecionada == null ? null : _onFazendaSelecionada,
              decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5)),
            ),
            const SizedBox(height: 16),
            
            // Área de Seleção do Estrato
            Text('4. Selecione os Talhões do Estrato (${_talhoesSelecionados.length})', 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _talhoesDisponiveis.isEmpty
                      ? const Center(child: Text('Nenhum talhão disponível.'))
                      : ListView(
                          children: _talhoesDisponiveis.map((talhao) {
                            return CheckboxListTile(
                              title: Text(talhao.nome),
                              subtitle: Text('${talhao.areaHa?.toStringAsFixed(2) ?? "0"} ha'),
                              value: _talhoesSelecionados.contains(talhao.id!),
                              onChanged: (value) => _toggleTalhao(talhao.id!, value),
                              secondary: const Icon(Icons.park),
                            );
                          }).toList(),
                        ),
            ),
          ],
        ),
      ),
      // Botões de Ação
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 1. Botão IA para auditar o que foi selecionado
          if (_talhoesSelecionados.isNotEmpty)
            FloatingActionButton.extended(
              onPressed: _executarAuditoriaIA,
              heroTag: 'auditoriaIAFab',
              label: const Text('Auditar Estrato com IA'),
              icon: const Icon(Icons.auto_awesome),
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          const SizedBox(height: 12),
          
          // 2. Botão de Análise Volumétrica
          FloatingActionButton.extended(
            onPressed: _navegarParaAnaliseVolumetrica,
            heroTag: 'analiseVolumetricaFab',
            label: const Text('Equação de Volume'),
            icon: const Icon(Icons.calculate),
            backgroundColor: const Color(0xFFEBE4AB), // Dourado
            foregroundColor: const Color(0xFF023853), // Azul Escuro
          ),
          const SizedBox(height: 12),

          // 3. Botão Principal: Analisar o Estrato
          FloatingActionButton.extended(
            onPressed: _gerarAnaliseEstrato,
            heroTag: 'analiseEstratoFab',
            label: const Text('Dashboard do Estrato'),
            icon: const Icon(Icons.layers),
            backgroundColor: const Color(0xFF023853), // Azul Marinho
            foregroundColor: const Color(0xFFEBE4AB), // Dourado
          ),
          const SizedBox(height: 12),
          
          // 4. Botão Secundário: Tabela Comparativa
          FloatingActionButton.extended(
            onPressed: _gerarRelatorioComparativo,
            heroTag: 'analiseComparativaFab',
            label: const Text('Tabela Comparativa'),
            icon: const Icon(Icons.table_chart),
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
        ],
      ),
    );
  }
}
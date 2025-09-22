// lib/providers/gerente_provider.dart (VERSÃO FINAL PARA DELEGAÇÃO)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/talhao_repository.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/diario_de_campo_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/services/gerente_service.dart';
import 'package:geoforestv1/services/licensing_service.dart';
import 'package:intl/date_symbol_data_local.dart';

class GerenteProvider with ChangeNotifier {
  final GerenteService _gerenteService = GerenteService();
  final ProjetoRepository _projetoRepository = ProjetoRepository();
  final TalhaoRepository _talhaoRepository = TalhaoRepository();
  final AtividadeRepository _atividadeRepository = AtividadeRepository();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LicensingService _licensingService = LicensingService();

  StreamSubscription? _dadosColetaSubscription;
  StreamSubscription? _dadosCubagemSubscription;
  StreamSubscription? _dadosDiarioSubscription;

  List<Parcela> _parcelasSincronizadas = [];
  List<CubagemArvore> _cubagensSincronizadas = [];
  List<DiarioDeCampo> _diariosSincronizados = [];
  List<Projeto> _projetos = [];
  List<Atividade> _atividades = [];
  List<Talhao> _talhoes = [];

  Map<int, int> _talhaoToProjetoMap = {};
  Map<int, int> _talhaoToAtividadeMap = {};
  Map<int, String> _talhaoIdToNomeMap = {};
  Map<String, String> _fazendaIdToNomeMap = {};

  bool _isLoading = true;
  String? _error;
  
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Projeto> get projetos => _projetos;
  List<Atividade> get atividades => _atividades;
  List<Talhao> get talhoes => _talhoes;
  List<Parcela> get parcelasSincronizadas => _parcelasSincronizadas;
  List<CubagemArvore> get cubagensSincronizadas => _cubagensSincronizadas;
  List<DiarioDeCampo> get diariosSincronizados => _diariosSincronizados;
  Map<int, int> get talhaoToProjetoMap => _talhaoToProjetoMap;
  Map<int, int> get talhaoToAtividadeMap => _talhaoToAtividadeMap;

  GerenteProvider() {
    initializeDateFormatting('pt_BR', null);
  }

  /// Busca no banco de dados local por projetos que foram delegados e retorna os IDs das licenças dos clientes.
  Future<Set<String>> _getDelegatedLicenseIds() async {
    final projetosLocais = await _projetoRepository.getTodosOsProjetosParaGerente();
    return projetosLocais
        .where((p) => p.delegadoPorLicenseId != null)
        .map((p) => p.delegadoPorLicenseId!)
        .toSet();
  }

  Future<void> iniciarMonitoramento() async {
    // Cancela as inscrições antigas para evitar múltiplos listeners
    _dadosColetaSubscription?.cancel();
    _dadosCubagemSubscription?.cancel();
    _dadosDiarioSubscription?.cancel();

    // ✅ ETAPA 1: LIMPEZA COMPLETA DOS DADOS EM CACHE
    // Garante que a "mesa de trabalho" está vazia antes de começar.
    _parcelasSincronizadas = [];
    _cubagensSincronizadas = [];
    _diariosSincronizados = [];
    _projetos = [];
    _atividades = [];
    _talhoes = [];
    _talhaoToProjetoMap = {};
    _talhaoToAtividadeMap = {};
    _talhaoIdToNomeMap = {};
    _fazendaIdToNomeMap = {};
    // FIM DA LIMPEZA

    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      // ✅ ETAPA 2: O RESTO DA LÓGICA CONTINUA IGUAL
      // Agora ela vai popular as listas limpas apenas com os dados do usuário correto.
      final user = _auth.currentUser;
      if (user == null) throw Exception("Usuário não autenticado.");

      final licenseDoc = await _licensingService.findLicenseDocumentForUser(user);
      if (licenseDoc == null) throw Exception("Licença do usuário não encontrada.");
      
      // 1. Pega o ID da licença própria do usuário logado.
      final ownLicenseId = licenseDoc.id;
      
      // 2. Busca no banco de dados local por IDs de licenças de clientes (projetos delegados).
      final delegatedLicenseIds = await _getDelegatedLicenseIds();
      
      // 3. Combina as duas listas, removendo duplicatas, para criar a lista final de licenças a serem monitoradas.
      final allLicenseIdsToMonitor = {ownLicenseId, ...delegatedLicenseIds}.toList();
      
      debugPrint(">>> GerenteProvider INICIANDO MONITORAMENTO PARA AS LICENÇAS: $allLicenseIdsToMonitor");
      
      // Carrega a hierarquia local para referência (projetos, atividades, etc.)
      _projetos = await _projetoRepository.getTodosOsProjetosParaGerente();
      _projetos.sort((a, b) => a.nome.compareTo(b.nome));
      
      _atividades = await _atividadeRepository.getTodasAsAtividades();
      final Map<int, String> atividadeIdToTipoMap = { for (var a in _atividades) if (a.id != null) a.id!: a.tipo };
      
      await _buildAuxiliaryMaps();

      // 4. Passa a LISTA COMPLETA de IDs para os streams do GerenteService.
      // Agora, o stream ouvirá tanto a sua coleção no Firestore quanto as coleções dos seus clientes.
      _dadosColetaSubscription = _gerenteService.getDadosColetaStream(licenseIds: allLicenseIdsToMonitor).listen(
        (listaDeParcelas) async {
          await _buildAuxiliaryMaps();
          _parcelasSincronizadas = listaDeParcelas.map((p) {
            final nomeFazenda = _fazendaIdToNomeMap[p.idFazenda] ?? p.nomeFazenda;
            final nomeTalhao = _talhaoIdToNomeMap[p.talhaoId] ?? p.nomeTalhao;
            final projetoId = p.projetoId ?? _talhaoToProjetoMap[p.talhaoId];
            final atividadeId = _talhaoToAtividadeMap[p.talhaoId];
            final tipoAtividade = atividadeId != null ? atividadeIdToTipoMap[atividadeId] : null;
            return p.copyWith(
              nomeFazenda: nomeFazenda, 
              nomeTalhao: nomeTalhao,
              projetoId: projetoId,
              atividadeTipo: tipoAtividade,
            );
          }).toList();
          if (_isLoading) _isLoading = false;
          _error = null;
          notifyListeners();
        },
        onError: (e) {
          _error = "Erro ao buscar dados de coleta: $e";
          _isLoading = false;
          notifyListeners();
        },
      );

      _dadosCubagemSubscription = _gerenteService.getDadosCubagemStream(licenseIds: allLicenseIdsToMonitor).listen(
        (listaDeCubagens) {
          _cubagensSincronizadas = listaDeCubagens;
          notifyListeners();
        },
        onError: (e) => debugPrint("Erro no stream de cubagens: $e"),
      );

      _dadosDiarioSubscription = _gerenteService.getDadosDiarioStream(licenseIds: allLicenseIdsToMonitor).listen(
        (listaDeDiarios) {
          _diariosSincronizados = listaDeDiarios;
          notifyListeners();
        },
        onError: (e) => debugPrint("Erro no stream de diários de campo: $e"),
      );

    } catch (e) {
      _error = "Erro ao iniciar monitoramento: $e";
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _buildAuxiliaryMaps() async {
    _talhoes = await _talhaoRepository.getTodosOsTalhoes();
    _talhaoToProjetoMap = { for (var talhao in _talhoes) if (talhao.id != null && talhao.projetoId != null) talhao.id!: talhao.projetoId! };
    _talhaoToAtividadeMap = { for (var talhao in _talhoes) if (talhao.id != null) talhao.id!: talhao.fazendaAtividadeId };
    _talhaoIdToNomeMap = { for (var talhao in _talhoes) if (talhao.id != null) talhao.id!: talhao.nome };
    _fazendaIdToNomeMap = { for (var talhao in _talhoes) if (talhao.fazendaId.isNotEmpty && talhao.fazendaNome != null) talhao.fazendaId: talhao.fazendaNome! };
  }

  @override
  void dispose() {
    _dadosColetaSubscription?.cancel();
    _dadosCubagemSubscription?.cancel();
    _dadosDiarioSubscription?.cancel();
    super.dispose();
  }
}
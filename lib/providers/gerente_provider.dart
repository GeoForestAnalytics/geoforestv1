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
import 'package:geoforestv1/models/pilha_madeira_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/silvi_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/services/gerente_service.dart';
import 'package:geoforestv1/services/licensing_service.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:collection/collection.dart';

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
  StreamSubscription? _dadosPilhasSubscription;
  StreamSubscription? _dadosSilviSubscription;

  List<Parcela> _parcelasSincronizadas = [];
  List<CubagemArvore> _cubagensSincronizadas = [];
  List<DiarioDeCampo> _diariosSincronizados = [];
  List<PilhaMadeira> _pilhasSincronizadas = [];
  List<OperacaoSilvi> _silviSincronizadas = [];

  List<Projeto> _projetos = [];
  List<Atividade> _atividades = [];
  List<Talhao> _talhoes = [];

  Map<int, int> _talhaoToProjetoMap = {};
  Map<int, int> _talhaoToAtividadeMap = {};
  Map<int, String> _talhaoIdToNomeMap = {};
  Map<String, String> _fazendaIdToNomeMap = {};

  bool _isLoading = false;
  String? _error;
  int? _projetoSelecionadoId;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<Projeto> get projetos => _projetos;
  List<Atividade> get atividades => _atividades;
  List<Talhao> get talhoes => _talhoes;
  List<Parcela> get parcelasSincronizadas => _parcelasSincronizadas;
  List<CubagemArvore> get cubagensSincronizadas => _cubagensSincronizadas;
  List<DiarioDeCampo> get diariosSincronizados => _diariosSincronizados;
  List<PilhaMadeira> get pilhasSincronizadas => _pilhasSincronizadas;
  List<OperacaoSilvi> get silviSincronizadas => _silviSincronizadas;
  Map<int, int> get talhaoToProjetoMap => _talhaoToProjetoMap;
  Map<int, int> get talhaoToAtividadeMap => _talhaoToAtividadeMap;
  int? get projetoCarregadoId => _projetoSelecionadoId;

  GerenteProvider() {
    initializeDateFormatting('pt_BR', null);
  }

  Future<Set<String>> _getDelegatedLicenseIds() async {
    final projetosLocais = await _projetoRepository.getTodosOsProjetosParaGerente();
    return projetosLocais
        .where((p) => p.delegadoPorLicenseId != null)
        .map((p) => p.delegadoPorLicenseId!)
        .toSet();
  }

  /// CARGA ESTRUTURAL (Nomes e IDs)
  Future<void> iniciarMonitoramentoEstrutural() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception("Usuário não autenticado.");

      _projetos = (await _projetoRepository.getTodosOsProjetosParaGerente())
          .where((p) => p.status != 'deletado')
          .toList();
      _projetos.sort((a, b) => a.nome.compareTo(b.nome));
      final projetoIdsAtivos = _projetos.map((p) => p.id!).toSet();
      _atividades = (await _atividadeRepository.getTodasAsAtividades())
          .where((a) => projetoIdsAtivos.contains(a.projetoId))
          .toList();
      _talhoes = await _talhaoRepository.getTodosOsTalhoes();

      await _buildAuxiliaryMaps();

      final licenseDoc = await _licensingService.findLicenseDocumentForUser(user);
      final ownLicenseId = licenseDoc?.id;
      final delegatedLicenseIds = await _getDelegatedLicenseIds();
      final allLicenseIds = {if (ownLicenseId != null) ownLicenseId, ...delegatedLicenseIds}.toList();

      _dadosDiarioSubscription?.cancel();
      _dadosDiarioSubscription = _gerenteService.getDadosDiarioStream(licenseIds: allLicenseIds).listen(
        (listaDeDiarios) {
          _diariosSincronizados = listaDeDiarios;
          notifyListeners();
        },
        onError: (e) => debugPrint("Erro stream diários: $e"),
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = "Erro ao carregar estrutura: $e";
      _isLoading = false;
      notifyListeners();
    }
  }

  /// VISÃO GLOBAL (Para Dashboards e Rankings)
  Future<void> carregarVisaoGlobalGerente() async {
    _isLoading = true;
    _projetoSelecionadoId = null;
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final licenseDoc = await _licensingService.findLicenseDocumentForUser(user);
      final ownLicenseId = licenseDoc?.id;
      final delegatedLicenseIds = await _getDelegatedLicenseIds();
      final allLicenseIds = {if (ownLicenseId != null) ownLicenseId, ...delegatedLicenseIds}.toList();

      debugPrint(">>> [MODO GESTÃO] Carregando dados globais de todas as equipes");

      _dadosColetaSubscription?.cancel();
      _dadosCubagemSubscription?.cancel();
      _dadosPilhasSubscription?.cancel();
      _dadosSilviSubscription?.cancel();

      _dadosColetaSubscription = _gerenteService.getParcelasGlobalStream(licenseIds: allLicenseIds).listen((lista) {
        _parcelasSincronizadas = lista.map((p) {
          final atividadeId = _talhaoToAtividadeMap[p.talhaoId];
          final tipoAtividade = _atividades.firstWhereOrNull((a) => a.id == atividadeId)?.tipo;
          return p.copyWith(
            nomeFazenda: _fazendaIdToNomeMap[p.idFazenda] ?? p.nomeFazenda,
            nomeTalhao: _talhaoIdToNomeMap[p.talhaoId] ?? p.nomeTalhao,
            atividadeTipo: tipoAtividade,
          );
        }).toList();
        _isLoading = false;
        notifyListeners();
      });

      _dadosCubagemSubscription = _gerenteService.getCubagensGlobalStream(licenseIds: allLicenseIds).listen((lista) {
        _cubagensSincronizadas = lista;
        notifyListeners();
      });

      _dadosPilhasSubscription = _gerenteService.getPilhasGlobalStream(licenseIds: allLicenseIds).listen((lista) {
        _pilhasSincronizadas = lista;
        notifyListeners();
      }, onError: (e) => debugPrint("Erro stream pilhas: $e"));

      _dadosSilviSubscription = _gerenteService.getOperacoesSilviGlobalStream(licenseIds: allLicenseIds).listen((lista) {
        _silviSincronizadas = lista;
        notifyListeners();
      }, onError: (e) => debugPrint("Erro stream silvi: $e"));

    } catch (e) {
      _error = "Erro na visão global: $e";
      _isLoading = false;
      notifyListeners();
    }
  }

  /// VISÃO FOCADA (Lazy Loading para Coleta)
  Future<void> carregarDadosDoProjeto(int projetoId) async {
    if (_projetoSelecionadoId == projetoId) return;

    _isLoading = true;
    _parcelasSincronizadas = [];
    _cubagensSincronizadas = [];
    _pilhasSincronizadas = [];
    _silviSincronizadas = [];
    _dadosColetaSubscription?.cancel();
    _dadosCubagemSubscription?.cancel();
    _dadosPilhasSubscription?.cancel();
    _dadosSilviSubscription?.cancel();
    _projetoSelecionadoId = projetoId;
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final licenseDoc = await _licensingService.findLicenseDocumentForUser(user);
      final ownLicenseId = licenseDoc?.id;
      final delegatedLicenseIds = await _getDelegatedLicenseIds();
      final allLicenseIds = {if (ownLicenseId != null) ownLicenseId, ...delegatedLicenseIds}.toList();

      _dadosColetaSubscription = _gerenteService.getParcelasDoProjetoStream(
        licenseIds: allLicenseIds,
        projetoId: projetoId,
      ).listen((listaDeParcelas) {
        _parcelasSincronizadas = listaDeParcelas.map((p) {
          final atividadeId = _talhaoToAtividadeMap[p.talhaoId];
          final tipoAtividade = _atividades.firstWhereOrNull((a) => a.id == atividadeId)?.tipo;
          return p.copyWith(
            nomeFazenda: _fazendaIdToNomeMap[p.idFazenda] ?? p.nomeFazenda,
            nomeTalhao: _talhaoIdToNomeMap[p.talhaoId] ?? p.nomeTalhao,
            atividadeTipo: tipoAtividade,
          );
        }).toList();
        _isLoading = false;
        notifyListeners();
      });

      final atividadesDoProjetoIds = _atividades.where((a) => a.projetoId == projetoId).map((a) => a.id).toSet();
      final talhoesDoProjetoIds = _talhoes.where((t) => atividadesDoProjetoIds.contains(t.fazendaAtividadeId)).map((t) => t.id!).toList();

      if (talhoesDoProjetoIds.isNotEmpty) {
        _dadosCubagemSubscription = _gerenteService.getCubagensDoProjetoStream(
          licenseIds: allLicenseIds,
          talhoesIds: talhoesDoProjetoIds,
        ).listen((listaDeCubagens) {
          _cubagensSincronizadas = listaDeCubagens;
          notifyListeners();
        });
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _buildAuxiliaryMaps() async {
    _talhaoToProjetoMap = {for (var t in _talhoes) if (t.id != null && t.projetoId != null) t.id!: t.projetoId!};
    _talhaoToAtividadeMap = {for (var t in _talhoes) if (t.id != null) t.id!: t.fazendaAtividadeId};
    _talhaoIdToNomeMap = {for (var t in _talhoes) if (t.id != null) t.id!: t.nome};
    _fazendaIdToNomeMap = {for (var t in _talhoes) if (t.fazendaId.isNotEmpty && t.fazendaNome != null) t.fazendaId: t.fazendaNome!};
  }

  @override
  void dispose() {
    _dadosColetaSubscription?.cancel();
    _dadosCubagemSubscription?.cancel();
    _dadosDiarioSubscription?.cancel();
    _dadosPilhasSubscription?.cancel();
    _dadosSilviSubscription?.cancel();
    super.dispose();
  }
}

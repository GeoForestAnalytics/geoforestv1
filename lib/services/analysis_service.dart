// lib/services/analysis_service.dart (VERSÃO FINAL COM CURTIS)

import 'dart:math';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/cubagem_secao_model.dart';
import 'package:geoforestv1/models/enums.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/analise_result_model.dart';
import 'package:geoforestv1/models/sortimento_model.dart';
import 'package:ml_linalg/linalg.dart';

import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/data/repositories/analise_repository.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/data/repositories/atividade_repository.dart';

// Extensão para adicionar a funcionalidade groupBy
extension GroupByExtension<T> on Iterable<T> {
  Map<K, List<T>> groupBy<K>(K Function(T) keyFunction) {
    final map = <K, List<T>>{};
    for (final element in this) {
      final key = keyFunction(element);
      (map[key] ??= []).add(element);
    }
    return map;
  }
}

class AnalysisService {
  final _cubagemRepository = CubagemRepository();
  final _analiseRepository = AnaliseRepository();
  final _projetoRepository = ProjetoRepository();
  final _atividadeRepository = AtividadeRepository();

  static const double fatorDeForma = 0.45;

  final List<SortimentoModel> _sortimentosFixos = [
    SortimentoModel(id: 4, nome: "> 35cm", comprimento: 2.7, diametroMinimo: 35, diametroMaximo: 200),
    SortimentoModel(id: 3, nome: "23-35cm", comprimento: 2.7, diametroMinimo: 23, diametroMaximo: 35),
    SortimentoModel(id: 2, nome: "18-23cm", comprimento: 6.0, diametroMinimo: 18, diametroMaximo: 23),
    SortimentoModel(id: 1, nome: "8-18cm", comprimento: 6.0, diametroMinimo: 8, diametroMaximo: 18),
  ];

  double _calculateDominantHeight(List<Arvore> arvores) {
    final alturasDominantes = arvores.where((a) => a.dominante && a.altura != null && a.altura! > 0).map((a) => a.altura!).toList();
    if (alturasDominantes.isEmpty) return 0.0;
    return _calculateAverage(alturasDominantes);
  }

  double _calculateSiteIndex(double alturaDominante, double? idadeAtualAnos) {
    if (alturaDominante <= 0 || idadeAtualAnos == null || idadeAtualAnos <= 0) return 0.0;
    const double idadeReferencia = 7.0;
    const double coeficiente = -0.5;
    final indiceDeSitio = alturaDominante * exp(coeficiente * (1 / idadeAtualAnos - 1 / idadeReferencia));
    return indiceDeSitio;
  }

  Future<AnaliseVolumetricaCompletaResult> gerarAnaliseVolumetricaCompleta({
    required List<CubagemArvore> arvoresParaRegressao,
    required List<Talhao> talhoesInventario,
  }) async {
    final resultadosCompletosRegressao = await gerarEquacaoSchumacherHall(arvoresParaRegressao);
    final resultadoRegressao = resultadosCompletosRegressao['resultados'] as Map<String, dynamic>;
    final diagnosticoRegressao = resultadosCompletosRegressao['diagnostico'] as Map<String, dynamic>;
    if (resultadoRegressao.containsKey('error')) throw Exception(resultadoRegressao['error']);

    double volumeTotalLote = 0;
    double areaTotalLote = 0;
    double areaBasalMediaPonderada = 0;
    double arvoresHaMediaPonderada = 0;
    List<Arvore> todasAsArvoresDoInventarioComVolume = [];

    for (final talhao in talhoesInventario) {
      final dadosAgregados = await _analiseRepository.getDadosAgregadosDoTalhao(talhao.id!);
      final List<Parcela> parcelas = dadosAgregados['parcelas'];
      final List<Arvore> arvores = dadosAgregados['arvores'];
      if (parcelas.isEmpty || arvores.isEmpty) continue;

      // Aplica volume usando Curtis para preencher alturas antes de aplicar Schumacher
      final arvoresComVolume = aplicarEquacaoDeVolume(
        arvoresDoInventario: arvores, 
        b0: resultadoRegressao['b0'], 
        b1: resultadoRegressao['b1'], 
        b2: resultadoRegressao['b2']
      );
      
      todasAsArvoresDoInventarioComVolume.addAll(arvoresComVolume);
      
      // Analisa o talhão usando as árvores já com altura corrigida e volume
      final analiseTalhao = getTalhaoInsights(talhao, parcelas, arvoresComVolume);

      if (talhao.areaHa != null && talhao.areaHa! > 0) {
        volumeTotalLote += (analiseTalhao.volumePorHectare * talhao.areaHa!);
        areaTotalLote += talhao.areaHa!;
        areaBasalMediaPonderada += (analiseTalhao.areaBasalPorHectare * talhao.areaHa!);
        arvoresHaMediaPonderada += (analiseTalhao.arvoresPorHectare * talhao.areaHa!);
      }
    }

    final totaisInventario = {
      'talhoes': talhoesInventario.map((t) => t.nome).join(', '),
      'volume_ha': areaTotalLote > 0 ? volumeTotalLote / areaTotalLote : 0.0,
      'arvores_ha': areaTotalLote > 0 ? (arvoresHaMediaPonderada / areaTotalLote).round() : 0,
      'area_basal_ha': areaTotalLote > 0 ? areaBasalMediaPonderada / areaTotalLote : 0.0,
      'volume_total_lote': volumeTotalLote,
      'area_total_lote': areaTotalLote,
    };

    final producaoPorSortimento = await _calcularProducaoPorSortimento(arvoresParaRegressao, totaisInventario['volume_ha'] as double);
    final volumePorCodigo = _calcularVolumePorCodigo(todasAsArvoresDoInventarioComVolume, totaisInventario['volume_ha'] as double);

    return AnaliseVolumetricaCompletaResult(
      resultadoRegressao: resultadoRegressao,
      diagnosticoRegressao: diagnosticoRegressao,
      totaisInventario: totaisInventario,
      producaoPorSortimento: producaoPorSortimento,
      volumePorCodigo: volumePorCodigo,
    );
  }

  Future<List<VolumePorSortimento>> _calcularProducaoPorSortimento(List<CubagemArvore> arvoresCubadas, double volumeHaInventario) async {
    final Map<String, double> volumesAcumuladosSortimento = {};
    for (final arvoreCubada in arvoresCubadas) {
      if (arvoreCubada.id == null) continue;
      final secoes = await _cubagemRepository.getSecoesPorArvoreId(arvoreCubada.id!);
      final volumePorSortimento = classificarSortimentos(secoes);
      volumePorSortimento.forEach((sortimento, volume) {
        volumesAcumuladosSortimento.update(sortimento, (value) => value + volume, ifAbsent: () => volume);
      });
    }

    double volumeTotalCubado = volumesAcumuladosSortimento.values.fold(0.0, (a, b) => a + b);
    if (volumeTotalCubado == 0) return [];

    final List<VolumePorSortimento> resultado = [];
    final sortedKeys = volumesAcumuladosSortimento.keys.toList()..sort((a, b) {
      final numA = double.tryParse(a.split('-').first.replaceAll('>', '')) ?? 99;
      final numB = double.tryParse(b.split('-').first.replaceAll('>', '')) ?? 99;
      return numB.compareTo(numA);
    });

    for (final sortimento in sortedKeys) {
      final volumeDoSortimento = volumesAcumuladosSortimento[sortimento]!;
      final porcentagem = (volumeDoSortimento / volumeTotalCubado) * 100;
      resultado.add(VolumePorSortimento(
        nome: sortimento,
        porcentagem: porcentagem,
        volumeHa: volumeHaInventario * (porcentagem / 100),
      ));
    }
    return resultado;
  }

  List<VolumePorCodigo> _calcularVolumePorCodigo(List<Arvore> arvoresComVolume, double volumeTotalHa) {
    if (arvoresComVolume.isEmpty || volumeTotalHa <= 0) return [];
    final grupoPorCodigo = arvoresComVolume.groupBy((Arvore a) => a.codigo.name);
    final Map<String, double> volumeAcumuladoPorCodigo = {};
    grupoPorCodigo.forEach((codigo, arvores) {
      volumeAcumuladoPorCodigo[codigo] = arvores.map((a) => a.volume ?? 0).fold(0.0, (prev, vol) => prev + vol);
    });

    final double volumeTotalAmostrado = volumeAcumuladoPorCodigo.values.fold(0.0, (a, b) => a + b);
    if (volumeTotalAmostrado <= 0) return [];

    final List<VolumePorCodigo> resultado = [];
    volumeAcumuladoPorCodigo.forEach((codigo, volume) {
      final porcentagem = (volume / volumeTotalAmostrado) * 100;
      resultado.add(VolumePorCodigo(
        codigo: codigo,
        porcentagem: porcentagem,
        volumeTotal: volumeTotalHa * (porcentagem / 100),
      ));
    });

    resultado.sort((a, b) => b.volumeTotal.compareTo(a.volumeTotal));
    return resultado;
  }

  double calcularVolumeComercialSmalian(List<CubagemSecao> secoes) {
    if (secoes.length < 2) return 0.0;
    secoes.sort((a, b) => a.alturaMedicao.compareTo(b.alturaMedicao));
    double volumeTotal = 0.0;
    for (int i = 0; i < secoes.length - 1; i++) {
      final secao1 = secoes[i];
      final secao2 = secoes[i + 1];
      final diametro1m = secao1.diametroSemCasca / 100;
      final diametro2m = secao2.diametroSemCasca / 100;
      final area1 = (pi * pow(diametro1m, 2)) / 4;
      final area2 = (pi * pow(diametro2m, 2)) / 4;
      final comprimentoTora = secao2.alturaMedicao - secao1.alturaMedicao;
      final volumeTora = ((area1 + area2) / 2) * comprimentoTora;
      volumeTotal += volumeTora;
    }
    return volumeTotal;
  }

  // ===========================================================================
  // ===================== IMPLEMENTAÇÃO DO MODELO DE CURTIS ===================
  // ===========================================================================

  /// Ajusta a curva hipsométrica de Curtis: ln(h) = b0 + b1 * (1/DAP)
  Map<String, double>? _ajustarCurvaHipsometricaCurtis(List<Arvore> arvores) {
    // 1. Filtra árvores que têm CAP e Altura medidos
    final amostras = arvores.where((a) => a.cap > 0 && (a.altura ?? 0) > 0).toList();

    // Requer pelo menos 10 árvores medidas para significância
    if (amostras.length < 10) return null;

    try {
      final List<Vector> xData = [];
      final List<double> yData = [];

      for (var a in amostras) {
        final dap = a.cap / pi;
        if (dap <= 0) continue;
        
        final invDap = 1 / dap; // X do Curtis
        final lnH = log(a.altura!); // Y do Curtis

        xData.add(Vector.fromList([1.0, invDap])); // [Intercepto, X]
        yData.add(lnH);
      }

      final features = Matrix.fromRows(xData);
      final labels = Vector.fromList(yData);
      
      final coefficients = (features.transpose() * features).inverse() * features.transpose() * labels;
      
      final b0 = coefficients.expand((e) => e).toList()[0];
      final b1 = coefficients.expand((e) => e).toList()[1];

      return {'b0': b0, 'b1': b1};

    } catch (e) {
      debugPrint("Erro ao ajustar Curtis: $e");
      return null;
    }
  }

  /// Preenche alturas de árvores não medidas usando Curtis (preferencial) ou Média.
  List<Arvore> _preencherAlturasFaltantes(List<Arvore> arvoresOriginais) {
    // Tenta ajustar a curva com os dados disponíveis
    final coeficientes = _ajustarCurvaHipsometricaCurtis(arvoresOriginais);
    
    // Calcula média para fallback
    final alturasValidas = arvoresOriginais.where((a) => (a.altura ?? 0) > 0).map((a) => a.altura!).toList();
    final mediaAltura = alturasValidas.isNotEmpty ? _calculateAverage(alturasValidas) : 0.0;

    return arvoresOriginais.map((a) {
      // Se já tem altura, mantém
      if ((a.altura ?? 0) > 0) return a;

      // Se não tem CAP, retorna com altura 0 ou média se possível
      if (a.cap <= 0) return a.copyWith(altura: mediaAltura > 0 ? mediaAltura : 0);

      // Tenta aplicar Curtis
      if (coeficientes != null) {
        final dap = a.cap / pi;
        final b0 = coeficientes['b0']!;
        final b1 = coeficientes['b1']!;
        
        final lnH = b0 + (b1 * (1 / dap));
        final alturaEstimada = exp(lnH);
        
        // Proteção contra valores absurdos
        if (alturaEstimada > 0 && alturaEstimada < 100) {
          return a.copyWith(altura: alturaEstimada);
        }
      }

      // Fallback: Usa a média
      return a.copyWith(altura: mediaAltura);
    }).toList();
  }

  // ===========================================================================
  // ===========================================================================
  
  Future<Map<String, Map<String, dynamic>>> gerarEquacaoSchumacherHall(List<CubagemArvore> arvoresCubadas) async {
    final List<Vector> xData = [];
    final List<double> yData = [];
    final List<double> lnDapList = [];
    final List<double> lnAlturaList = [];

    for (final arvoreCubada in arvoresCubadas) {
      if (arvoreCubada.id == null) continue;
      final secoes = await _cubagemRepository.getSecoesPorArvoreId(arvoreCubada.id!);
      final volumeReal = calcularVolumeComercialSmalian(secoes);
      if (volumeReal <= 0 || arvoreCubada.valorCAP <= 0 || arvoreCubada.alturaTotal <= 0) continue;
      
      final dap = arvoreCubada.valorCAP / pi;
      final altura = arvoreCubada.alturaTotal;
      final lnVolume = log(volumeReal);
      final lnDAP = log(dap);
      final lnAltura = log(altura);

      xData.add(Vector.fromList([1.0, lnDAP, lnAltura]));
      yData.add(lnVolume);
      lnDapList.add(lnDAP);
      lnAlturaList.add(lnAltura);
    }

    final int n = xData.length;
    const int p = 3;
    if (n < p) {
      final errorResult = {'error': 'Dados insuficientes. Pelo menos $p árvores cubadas completas são necessárias.'};
      return {'resultados': errorResult, 'diagnostico': {}};
    }

    double calculateStdDev(List<double> numbers) {
      if (numbers.length < 2) return 0.0;
      final mean = numbers.reduce((a, b) => a + b) / numbers.length;
      final variance = numbers.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / (numbers.length - 1);
      return sqrt(variance);
    }

    final double stdDevDap = calculateStdDev(lnDapList);
    final double stdDevAltura = calculateStdDev(lnAlturaList);

    if (stdDevDap < 0.0001 || stdDevAltura < 0.0001) {
      final errorResult = {'error': 'Variação de dados insuficiente. Selecione árvores de cubagem com DAPs e Alturas mais diferentes.'};
      return {'resultados': errorResult, 'diagnostico': {}};
    }

    final features = Matrix.fromRows(xData);
    final labels = Vector.fromList(yData);

    try {
      final coefficients = (features.transpose() * features).inverse() * features.transpose() * labels;
      final List<double> coeffsAsList = coefficients.expand((e) => e).toList();
      final double b0 = coeffsAsList[0];
      final double b1 = coeffsAsList[1];
      final double b2 = coeffsAsList[2];

      final predictedValues = features * coefficients;
      final yMean = labels.mean();
      final totalSumOfSquares = labels.fold(0.0, (sum, val) => sum + pow(val - yMean, 2));
      final residuals = labels - predictedValues;
      final residualSumOfSquares = residuals.fold(0.0, (sum, val) => sum + pow(val, 2));

      if (totalSumOfSquares == 0) {
        final errorResult = {'error': 'Variação nula nos dados.'};
        return {'resultados': errorResult, 'diagnostico': {}};
      }
      final rSquared = 1 - (residualSumOfSquares / totalSumOfSquares);
      final double mse = residualSumOfSquares / (n - p);
      final double syx = sqrt(mse);
      
      return {
        'resultados': {'b0': b0, 'b1': b1, 'b2': b2, 'R2': rSquared, 'equacao': 'ln(V) = ${b0.toStringAsFixed(5)} + ${b1.toStringAsFixed(5)}*ln(DAP) + ${b2.toStringAsFixed(5)}*ln(H)', 'n_amostras': n,},
        'diagnostico': {'syx': syx, 'syx_percent': yMean != 0 ? (syx / yMean) * 100 : 0.0, 'shapiro_wilk_p_value': null, }
      };
    } catch (e) {
      final errorResult = {'error': 'Erro matemático na regressão. Detalhe: $e'};
      return {'resultados': errorResult, 'diagnostico': {}};
    }
  }

  // --- ATUALIZADO: Agora usa Curtis para preencher alturas antes de aplicar o volume ---
  List<Arvore> aplicarEquacaoDeVolume({required List<Arvore> arvoresDoInventario, required double b0, required double b1, required double b2}) {
    // 1. Preenche as alturas (Se Curtis falhar, usa média)
    final arvoresPreparadas = _preencherAlturasFaltantes(arvoresDoInventario);
    
    final List<Arvore> arvoresComVolume = [];
    const codigosSemVolume = [Codigo.Falha, Codigo.MortaOuSeca, Codigo.Caida];

    for (final arvore in arvoresPreparadas) {
      if (arvore.cap <= 0 || codigosSemVolume.contains(arvore.codigo)) {
        arvoresComVolume.add(arvore.copyWith(volume: 0));
        continue;
      }
      
      // Aqui a altura já foi estimada
      final alturaParaCalculo = (arvore.altura != null && arvore.altura! > 0) ? arvore.altura! : 0.1;
      
      if (alturaParaCalculo <= 0.1) {
        arvoresComVolume.add(arvore.copyWith(volume: 0));
        continue;
      }

      final dap = arvore.cap / pi;
      final lnVolume = b0 + (b1 * log(dap)) + (b2 * log(alturaParaCalculo));
      final volumeEstimado = exp(lnVolume);
      arvoresComVolume.add(arvore.copyWith(volume: volumeEstimado));
    }
    return arvoresComVolume;
  }

  Map<String, double> classificarSortimentos(List<CubagemSecao> secoes) {
    Map<String, double> volumesPorSortimento = {};
    if (secoes.length < 2) return volumesPorSortimento;
    secoes.sort((a, b) => a.alturaMedicao.compareTo(b.alturaMedicao));
    for (int i = 0; i < secoes.length - 1; i++) {
      final secaoBase = secoes[i];
      final secaoPonta = secoes[i + 1];
      final diametroBase = secaoBase.diametroSemCasca;
      final diametroPonta = secaoPonta.diametroSemCasca;
      if (diametroBase < _sortimentosFixos.last.diametroMinimo) continue;
      final comprimentoTora = secaoPonta.alturaMedicao - secaoBase.alturaMedicao;
      final areaBaseM2 = (pi * pow(diametroBase / 100, 2)) / 4;
      final areaPontaM2 = (pi * pow(diametroPonta / 100, 2)) / 4;
      final volumeTora = ((areaBaseM2 + areaPontaM2) / 2) * comprimentoTora;
      SortimentoModel? sortimentoEncontrado;
      for (final sortimentoDef in _sortimentosFixos) {
        if (diametroPonta >= sortimentoDef.diametroMinimo && diametroPonta < sortimentoDef.diametroMaximo) {
          sortimentoEncontrado = sortimentoDef;
          break;
        }
      }
      if (sortimentoEncontrado != null) {
        volumesPorSortimento.update(sortimentoEncontrado.nome, (value) => value + volumeTora, ifAbsent: () => volumeTora);
      }
    }
    return volumesPorSortimento;
  }

  TalhaoAnalysisResult getTalhaoInsights(Talhao talhao, List<Parcela> parcelasDoTalhao, List<Arvore> todasAsArvores) {
    if (parcelasDoTalhao.isEmpty) return TalhaoAnalysisResult();
    final double areaTotalAmostradaM2 = parcelasDoTalhao.map((p) => p.areaMetrosQuadrados).fold(0.0, (a, b) => a + b);
    if (areaTotalAmostradaM2 == 0) return TalhaoAnalysisResult();
    final double areaTotalAmostradaHa = areaTotalAmostradaM2 / 10000;
    final codeAnalysis = getTreeCodeAnalysis(todasAsArvores);
    return _analisarListaDeArvores(talhao, todasAsArvores, areaTotalAmostradaHa, parcelasDoTalhao.length, codeAnalysis);
  }
  
  // --- ATUALIZADO: Agora usa Curtis para preencher alturas antes de calcular as médias ---
  TalhaoAnalysisResult _analisarListaDeArvores(Talhao talhao, List<Arvore> arvoresDoConjunto, double areaTotalAmostradaHa, int numeroDeParcelas, CodeAnalysisResult? codeAnalysis) {
    if (arvoresDoConjunto.isEmpty || areaTotalAmostradaHa <= 0) return TalhaoAnalysisResult();
    
    // Preenche alturas faltantes para estatísticas mais precisas
    final List<Arvore> arvoresComAlturaCompleta = _preencherAlturasFaltantes(arvoresDoConjunto);

    const codigosSemVolume = [Codigo.Falha, Codigo.MortaOuSeca, Codigo.Caida];
    final List<Arvore> arvoresVivas = arvoresComAlturaCompleta.where((a) => !codigosSemVolume.contains(a.codigo)).toList();
    
    if (arvoresVivas.isEmpty) return TalhaoAnalysisResult(warnings: ["Nenhuma árvore com potencial de volume encontrada nas amostras para análise."]);

    final double mediaCap = _calculateAverage(arvoresVivas.map((a) => a.cap).toList());
    
    // Média de altura agora reflete as estimativas do Curtis também
    final double mediaAltura = _calculateAverage(arvoresVivas.map((a) => a.altura!).toList());

    final double areaBasalTotalAmostrada = arvoresVivas.map((a) => _areaBasalPorArvore(a.cap)).fold(0.0, (a, b) => a + b);
    final double areaBasalPorHectare = areaBasalTotalAmostrada / areaTotalAmostradaHa;
    
    // Usa a altura estimada (ou média) para estimativa de volume individual
    final double volumeTotalAmostrado = arvoresVivas.map((a) => a.volume ?? _estimateVolume(a.cap, a.altura!)).fold(0.0, (a, b) => a + b);
    
    final double volumePorHectare = volumeTotalAmostrado / areaTotalAmostradaHa;
    final int arvoresPorHectare = (arvoresVivas.length / areaTotalAmostradaHa).round();
    final double alturaDominante = _calculateDominantHeight(arvoresVivas);
    final double indiceDeSitio = _calculateSiteIndex(alturaDominante, talhao.idadeAnos);

    List<String> warnings = [];
    List<String> insights = [];
    List<String> recommendations = [];

    final int arvoresMortas = (codeAnalysis?.contagemPorCodigo['MortaOuSeca'] ?? 0) + (codeAnalysis?.contagemPorCodigo['Caida'] ?? 0);
    final taxaMortalidade = (codeAnalysis?.totalFustes ?? 0) > 0 ? (arvoresMortas / codeAnalysis!.totalFustes) * 100 : 0.0;
    if (taxaMortalidade > 15) warnings.add("Mortalidade de ${taxaMortalidade.toStringAsFixed(1)}% detectada, valor considerado alto.");
    if (areaBasalPorHectare > 38) {
      insights.add("A Área Basal (${areaBasalPorHectare.toStringAsFixed(1)} m²/ha) indica um povoamento muito denso.");
      recommendations.add("O talhão é um forte candidato para desbaste. Use a ferramenta de simulação para avaliar cenários.");
    } else if (areaBasalPorHectare < 20) {
      insights.add("A Área Basal (${areaBasalPorHectare.toStringAsFixed(1)} m²/ha) está baixa, indicando um povoamento aberto ou muito jovem.");
    }
    
    final Map<double, int> distribuicao = getDistribuicaoDiametrica(arvoresVivas);

    return TalhaoAnalysisResult(
      areaTotalAmostradaHa: areaTotalAmostradaHa, totalArvoresAmostradas: arvoresDoConjunto.length, totalParcelasAmostradas: numeroDeParcelas,
      mediaCap: mediaCap, mediaAltura: mediaAltura, areaBasalPorHectare: areaBasalPorHectare, volumePorHectare: volumePorHectare,
      arvoresPorHectare: arvoresPorHectare, alturaDominante: alturaDominante, indiceDeSitio: indiceDeSitio,
      distribuicaoDiametrica: distribuicao, analiseDeCodigos: codeAnalysis,
      warnings: warnings, insights: insights, recommendations: recommendations,
    );
  }
  
  CodeAnalysisResult getTreeCodeAnalysis(List<Arvore> arvores) {
    if (arvores.isEmpty) return CodeAnalysisResult();
    final contagemPorCodigo = arvores.groupBy<String>((arvore) => arvore.codigo.name).map((key, value) => MapEntry(key, value.length));
    final covasUnicas = <String>{};
    for (final arvore in arvores) {
      covasUnicas.add('${arvore.linha}-${arvore.posicaoNaLinha}');
    }
    final totalCovasAmostradas = covasUnicas.length;
    final totalCovasOcupadas = arvores.where((a) => a.codigo != Codigo.Falha).map((a) => '${a.linha}-${a.posicaoNaLinha}').toSet().length;
    final Map<String, CodeStatDetails> estatisticas = {};
    final arvoresAgrupadas = arvores.groupBy((Arvore a) => a.codigo.name);

    arvoresAgrupadas.forEach((codigo, listaDeArvores) {
      final caps = listaDeArvores.map((a) => a.cap).where((cap) => cap > 0).toList();
      final alturas = listaDeArvores.map((a) => a.altura).whereType<double>().where((h) => h > 0).toList();
      estatisticas[codigo] = CodeStatDetails(
        mediaCap: _calculateAverage(caps), medianaCap: _calculateMedian(caps), modaCap: _calculateMode(caps).firstOrNull ?? 0.0, desvioPadraoCap: _calculateStdDev(caps),
        mediaAltura: _calculateAverage(alturas), medianaAltura: _calculateMedian(alturas), modaAltura: _calculateMode(alturas).firstOrNull ?? 0.0, desvioPadraoAltura: _calculateStdDev(alturas),
      );
    });

    return CodeAnalysisResult(
      contagemPorCodigo: contagemPorCodigo, estatisticasPorCodigo: estatisticas,
      totalFustes: arvores.length, totalCovasAmostradas: totalCovasAmostradas, totalCovasOcupadas: totalCovasOcupadas,
    );
  }

  TalhaoAnalysisResult simularDesbaste({
    required Talhao talhao,
    required List<Parcela> parcelasOriginais,
    required List<Arvore> todasAsArvores,
    required double porcentagemRemocaoSeletiva,
    required bool sistematicoAtivo,
    required int? linhaSistematica,
  }) {
    if (parcelasOriginais.isEmpty) {
      return getTalhaoInsights(talhao, parcelasOriginais, todasAsArvores);
    }

    const codigosSemVolume = [Codigo.Falha, Codigo.MortaOuSeca, Codigo.Caida];
    final List<Arvore> arvoresVivas = todasAsArvores.where((a) => !codigosSemVolume.contains(a.codigo)).toList();
    if (arvoresVivas.isEmpty) {
      return getTalhaoInsights(talhao, parcelasOriginais, todasAsArvores);
    }

    List<Arvore> arvoresRemanescentes;

    if (sistematicoAtivo && linhaSistematica != null && linhaSistematica > 0) {
      final arvoresParaDesbasteSeletivo = <Arvore>[];
      for (var arvore in arvoresVivas) {
        if (arvore.linha % linhaSistematica != 0) {
          arvoresParaDesbasteSeletivo.add(arvore);
        }
      }
      
      arvoresParaDesbasteSeletivo.sort((a, b) => a.cap.compareTo(b.cap));
      final int quantidadeRemoverSeletivo = (arvoresParaDesbasteSeletivo.length * (porcentagemRemocaoSeletiva / 100)).floor();
      
      arvoresRemanescentes = arvoresParaDesbasteSeletivo.sublist(quantidadeRemoverSeletivo);

    } else {
      arvoresVivas.sort((a, b) => a.cap.compareTo(b.cap));
      final int quantidadeRemover = (arvoresVivas.length * (porcentagemRemocaoSeletiva / 100)).floor();
      arvoresRemanescentes = arvoresVivas.sublist(quantidadeRemover);
    }

    final double areaTotalAmostradaM2 = parcelasOriginais.map((p) => p.areaMetrosQuadrados).fold(0.0, (a, b) => a + b);
    final double areaTotalAmostradaHa = areaTotalAmostradaM2 / 10000;
    
    final codeAnalysisRemanescente = getTreeCodeAnalysis(arvoresRemanescentes);
    return _analisarListaDeArvores(talhao, arvoresRemanescentes, areaTotalAmostradaHa, parcelasOriginais.length, codeAnalysisRemanescente);
  }  
  
  Map<String, int> gerarPlanoDeCubagem({
    required Map<double, int> distribuicaoAmostrada,
    required int totalArvoresAmostradas,
    required int totalArvoresParaCubar,
    required MetricaDistribuicao metrica,
    double? larguraClasseManual,
  }) {
    final double larguraClasse = larguraClasseManual ?? ((metrica == MetricaDistribuicao.cap) ? 15.0 : 5.0);

    if (totalArvoresAmostradas == 0 || totalArvoresParaCubar == 0 || distribuicaoAmostrada.isEmpty) return {};
    
    final Map<String, int> plano = {};

    for (var entry in distribuicaoAmostrada.entries) {
      final pontoMedio = entry.key;
      final contagemNaClasse = entry.value;
      final double proporcao = contagemNaClasse / totalArvoresAmostradas;
      final int arvoresParaCubarNestaClasse = (proporcao * totalArvoresParaCubar).round();
      
      final inicioClasse = pontoMedio - (larguraClasse / 2);
      final fimClasse = pontoMedio + (larguraClasse / 2) - 0.1;
      
      final String rotuloClasse = "${metrica.descricao}: ${inicioClasse.toStringAsFixed(1)} - ${fimClasse.toStringAsFixed(1)} cm";
          
      if (arvoresParaCubarNestaClasse > 0) {
        plano[rotuloClasse] = arvoresParaCubarNestaClasse;
      }
    }
    
    int somaAtual = plano.values.fold(0, (a, b) => a + b);
    int diferenca = totalArvoresParaCubar - somaAtual;

    if (diferenca != 0 && plano.isNotEmpty) {
      String? classeParaAjustar;
      int maxValor = -1;
      plano.forEach((key, value) {
        if (value > maxValor) {
          maxValor = value;
          classeParaAjustar = key;
        }
      });

      if (classeParaAjustar != null) {
        final novoValor = plano[classeParaAjustar]! + diferenca;
        if (novoValor > 0) plano[classeParaAjustar!] = novoValor;
        else plano.remove(classeParaAjustar);
      }
    }
    return plano;
  }

  Map<double, int> getDistribuicaoPorMetrica({
    required List<Arvore> arvores,
    required MetricaDistribuicao metrica,
    double? larguraClasseManual,
  }) {
    final double larguraClasse = larguraClasseManual ?? ((metrica == MetricaDistribuicao.cap) ? 15.0 : 5.0);

    if (arvores.isEmpty || larguraClasse <= 0) return {};
    
    final Map<int, int> contagemPorClasse = {};
    
    for (final arvore in arvores) {
      if (arvore.cap > 0) {
        final double valor;
        switch (metrica) {
          case MetricaDistribuicao.dap:
            valor = arvore.cap / pi;
            break;
          case MetricaDistribuicao.cap:
            valor = arvore.cap;
            break;
        }
        
        final int classeBase = (valor / larguraClasse).floor() * larguraClasse.toInt();
        contagemPorClasse.update(classeBase, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    
    final sortedKeys = contagemPorClasse.keys.toList()..sort();
    final Map<double, int> resultadoFinal = {};
    
    for (final key in sortedKeys) {
      final double pontoMedio = key.toDouble() + (larguraClasse / 2.0);
      resultadoFinal[pontoMedio] = contagemPorClasse[key]!;
    }
    return resultadoFinal;
  }
  
  Map<double, int> getDistribuicaoDiametrica(List<Arvore> arvores) {
    return getDistribuicaoPorMetrica(arvores: arvores, metrica: MetricaDistribuicao.dap);
  }

  double _areaBasalPorArvore(double cap) {
    if (cap <= 0) return 0.0;
    final double dap = cap / pi;
    return (pi * pow(dap, 2)) / 40000;
  }

  double _estimateVolume(double cap, double altura) {
    if (cap <= 0 || altura <= 0) return 0.0;
    final areaBasal = _areaBasalPorArvore(cap);
    return areaBasal * altura * fatorDeForma;
  }

  double _calculateAverage(List<double> numbers) {
    if (numbers.isEmpty) return 0.0;
    return numbers.reduce((a, b) => a + b) / numbers.length;
  }

  double _calculateMedian(List<double> numbers) {
    if (numbers.isEmpty) return 0.0;
    final sortedList = List<double>.from(numbers)..sort();
    final middle = sortedList.length ~/ 2;
    if (sortedList.length % 2 == 1) {
      return sortedList[middle];
    } else {
      return (sortedList[middle - 1] + sortedList[middle]) / 2.0;
    }
  }

  List<double> _calculateMode(List<double> numbers) {
    if (numbers.isEmpty) return [];
    final frequencyMap = <double, int>{};
    for (var number in numbers) {
      frequencyMap[number] = (frequencyMap[number] ?? 0) + 1;
    }
    if (frequencyMap.isEmpty) return [];
    final maxFrequency = frequencyMap.values.reduce(max);
    if (maxFrequency <= 1) return []; 
    final modes = frequencyMap.entries.where((entry) => entry.value == maxFrequency).map((entry) => entry.key).toList();
    return modes;
  }
  
  double _calculateStdDev(List<double> numbers) {
    if (numbers.length < 2) return 0.0;
    final mean = _calculateAverage(numbers);
    final variance = numbers.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / (numbers.length - 1);
    return sqrt(variance);
  }

  // ✅ FUNÇÃO PRINCIPAL QUE FOI ALTERADA
  Future<Map<Talhao, Map<String, int>>> criarMultiplasAtividadesDeCubagem({
    required List<Talhao> talhoes,
    required MetodoDistribuicaoCubagem metodo,
    required int quantidade,
    required String metodoCubagem,
    required MetricaDistribuicao metrica,
    bool isIntervaloManual = false,
    double? intervaloManual,
  }) async {
    final Map<int, int> quantidadesPorTalhao = {};
    final Map<Talhao, Map<String, int>> planosGerados = {};

    if (metodo == MetodoDistribuicaoCubagem.fixoPorTalhao) {
      for (final talhao in talhoes) {
        if (talhao.id != null) {
          quantidadesPorTalhao[talhao.id!] = quantidade;
        }
      }
    } else if (metodo == MetodoDistribuicaoCubagem.proporcionalPorArea) {
      double areaTotalDoLote =
          talhoes.map((t) => t.areaHa ?? 0.0).fold(0.0, (prev, area) => prev + area);
      if (areaTotalDoLote <= 0) {
        throw Exception(
            "A área total dos talhões selecionados é zero. Não é possível calcular a proporção.");
      }
      int arvoresDistribuidas = 0;
      for (int i = 0; i < talhoes.length; i++) {
        final talhao = talhoes[i];
        if (talhao.id == null) continue;
        final areaTalhao = talhao.areaHa ?? 0.0;
        final proporcao = areaTalhao / areaTotalDoLote;
        if (i == talhoes.length - 1) {
          quantidadesPorTalhao[talhao.id!] = quantidade - arvoresDistribuidas;
        } else {
          final qtdParaEsteTalhao = (quantidade * proporcao).round();
          quantidadesPorTalhao[talhao.id!] = qtdParaEsteTalhao;
          arvoresDistribuidas += qtdParaEsteTalhao;
        }
      }
    }

    final Map<Talhao, List<CubagemArvore>> planosCompletos = {};

    for (final talhao in talhoes) {
      if (talhao.id == null) continue;
      final totalArvoresParaCubar = quantidadesPorTalhao[talhao.id!] ?? 0;
      if (totalArvoresParaCubar <= 0) continue;

      final dadosAgregados = await _analiseRepository.getDadosAgregadosDoTalhao(talhao.id!);
      final parcelas = dadosAgregados['parcelas'] as List<Parcela>;
      final arvores = dadosAgregados['arvores'] as List<Arvore>;
      if (parcelas.isEmpty || arvores.isEmpty) continue;

      final analiseResult = getTalhaoInsights(talhao, parcelas, arvores);
      
      final distribuicao = getDistribuicaoPorMetrica(
        arvores: arvores, 
        metrica: metrica,
        larguraClasseManual: isIntervaloManual ? intervaloManual : null,
      );

      final plano = gerarPlanoDeCubagem(
        distribuicaoAmostrada: distribuicao,
        totalArvoresAmostradas: analiseResult.totalArvoresAmostradas,
        totalArvoresParaCubar: totalArvoresParaCubar,
        metrica: metrica,
        larguraClasseManual: isIntervaloManual ? intervaloManual : null,
      );

      if (plano.isEmpty) {
        debugPrint("Aviso: Não foi possível gerar o plano de cubagem para o talhão ${talhao.nome}. Pulando.");
        continue;
      }

      planosGerados[talhao] = plano;
      
      final List<CubagemArvore> placeholders = [];
      plano.forEach((classe, qtd) {
        for (int i = 1; i <= qtd; i++) {
          final classeSanitizada = classe.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-');
          placeholders.add(CubagemArvore(
            nomeFazenda: talhao.fazendaNome ?? 'N/A', 
            idFazenda: talhao.fazendaId, 
            nomeTalhao: talhao.nome,
            classe: classe, 
            identificador: 'PLANO-${classeSanitizada}-${i.toString().padLeft(2, '0')}',
            alturaTotal: 0, valorCAP: 0, alturaBase: 1.30, tipoMedidaCAP: 'fita',
          ));
        }
      });
      planosCompletos[talhao] = placeholders;
    }

    if (planosCompletos.isNotEmpty) {
      final primeiroTalhao = planosCompletos.keys.first;
      final projeto = await _projetoRepository.getProjetoPelaAtividade(primeiroTalhao.fazendaAtividadeId);
      if (projeto != null) {
        final novaAtividadeUnica = Atividade(
          projetoId: projeto.id!,
          tipo: 'Cubagem - $metodoCubagem',
          descricao: 'Plano de cubagem para ${planosCompletos.length} talhões.',
          dataCriacao: DateTime.now(),
          metodoCubagem: metodoCubagem,
        );

        await _atividadeRepository.criarAtividadeUnicaComMultiplosPlanos(novaAtividadeUnica, planosCompletos);
      }
    }
    
    return planosGerados;
  }

  // Em lib/services/analysis_service.dart

  /// Consolida dados de múltiplos talhões como um único Estrato.
  /// Realiza médias ponderadas pela área para variáveis por hectare.
  TalhaoAnalysisResult analisarEstratoUnificado({
    required List<Talhao> talhoes,
    required Map<int, List<Parcela>> parcelasPorTalhao,
    required Map<int, List<Arvore>> arvoresPorTalhao,
  }) {
    double areaTotalEstrato = 0;
    List<Parcela> todasParcelas = [];
    List<Arvore> todasArvores = [];
    
    // Variáveis para média ponderada
    double somaVolumeTotal = 0;
    double somaAreaBasalTotal = 0;
    double somaArvoresTotal = 0;

    for (var talhao in talhoes) {
      if (talhao.id == null) continue;
      
      final areaTalhao = talhao.areaHa ?? 0.0;
      final parcelas = parcelasPorTalhao[talhao.id] ?? [];
      final arvores = arvoresPorTalhao[talhao.id] ?? [];
      
      if (parcelas.isEmpty || arvores.isEmpty) continue;

      // Analisa individualmente para obter as médias por hectare deste talhão
      final analiseIndividual = getTalhaoInsights(talhao, parcelas, arvores);
      
      // Acumula para o Estrato
      areaTotalEstrato += areaTalhao;
      todasParcelas.addAll(parcelas);
      todasArvores.addAll(arvores);
      
      // Soma os totais absolutos (Volume/ha * Area = Volume Total do Talhão)
      if (areaTalhao > 0) {
        somaVolumeTotal += (analiseIndividual.volumePorHectare * areaTalhao);
        somaAreaBasalTotal += (analiseIndividual.areaBasalPorHectare * areaTalhao);
        somaArvoresTotal += (analiseIndividual.arvoresPorHectare * areaTalhao);
      }
    }

    if (areaTotalEstrato == 0 || todasArvores.isEmpty) return TalhaoAnalysisResult();

    // Calcula as médias ponderadas do Estrato
    final volumePorHectareEstrato = somaVolumeTotal / areaTotalEstrato;
    final areaBasalPorHectareEstrato = somaAreaBasalTotal / areaTotalEstrato;
    final arvoresPorHectareEstrato = (somaArvoresTotal / areaTotalEstrato).round();

    // Para CAP, Altura e Distribuição, usamos todos os dados juntos (média aritmética da amostra composta)
    final codeAnalysis = getTreeCodeAnalysis(todasArvores);
    
    // Filtra árvores vivas para médias dendrométricas
    const codigosSemVolume = [Codigo.Falha, Codigo.MortaOuSeca, Codigo.Caida];
    final arvoresVivas = todasArvores.where((a) => !codigosSemVolume.contains(a.codigo)).toList();
    
    final double mediaCap = _calculateAverage(arvoresVivas.map((a) => a.cap).toList());
    final double mediaAltura = _calculateAverage(arvoresVivas.map((a) => a.altura ?? 0).where((h) => h > 0).toList());
    final double alturaDominante = _calculateDominantHeight(arvoresVivas);
    
    // Índice de Sítio (Usa a idade do primeiro talhão como referência ou média ponderada se as idades variarem muito)
    // Aqui assumimos que o estrato tem idades próximas, usamos a média.
    final mediaIdade = talhoes.map((t) => t.idadeAnos ?? 0).reduce((a, b) => a + b) / talhoes.length;
    final double indiceDeSitio = _calculateSiteIndex(alturaDominante, mediaIdade);
    
     final distribuicao = getDistribuicaoDiametrica(arvoresVivas);

    List<String> insights = [];
    
    // --- ALTERAÇÃO AQUI: Listando os nomes ---
    // Pega os nomes, ordena alfabeticamente para ficar organizado e junta com vírgulas
    final nomesDosTalhoes = talhoes.map((t) => t.nome).toList()..sort();
    final listaFormatada = nomesDosTalhoes.join(', ');

    insights.add("Análise consolidada de ${talhoes.length} talhões.");
    insights.add("Composição: $listaFormatada."); // <--- Nova linha com a lista
    // ------------------------------------------

    insights.add("Área total do estrato: ${areaTotalEstrato.toStringAsFixed(2)} ha.");

    return TalhaoAnalysisResult(
      areaTotalAmostradaHa: areaTotalEstrato, 
      totalArvoresAmostradas: todasArvores.length,
      totalParcelasAmostradas: todasParcelas.length,
      mediaCap: mediaCap,
      mediaAltura: mediaAltura,
      areaBasalPorHectare: areaBasalPorHectareEstrato,
      volumePorHectare: volumePorHectareEstrato,
      arvoresPorHectare: arvoresPorHectareEstrato,
      alturaDominante: alturaDominante,
      indiceDeSitio: indiceDeSitio,
      distribuicaoDiametrica: distribuicao,
      analiseDeCodigos: codeAnalysis,
      insights: insights,
      warnings: [], 
      recommendations: ["Considere este resultado para planejamento de colheita ou desbaste do bloco inteiro."],
    );
  }
}
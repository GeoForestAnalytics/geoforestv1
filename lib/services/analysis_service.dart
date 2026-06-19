// ================================================================================
// Arquivo: lib\services\analysis_service.dart
// ================================================================================

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

  // Definição de sortimentos padrão (pode vir do banco no futuro)
  final List<SortimentoModel> _sortimentosFixos = [
    SortimentoModel(id: 4, nome: "> 35cm", comprimento: 2.7, diametroMinimo: 35, diametroMaximo: 200),
    SortimentoModel(id: 3, nome: "23-35cm", comprimento: 2.7, diametroMinimo: 23, diametroMaximo: 35),
    SortimentoModel(id: 2, nome: "18-23cm", comprimento: 6.0, diametroMinimo: 18, diametroMaximo: 23),
    SortimentoModel(id: 1, nome: "8-18cm", comprimento: 6.0, diametroMinimo: 8, diametroMaximo: 18),
  ];

  // --- MÉTODOS AUXILIARES MATEMÁTICOS ---

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

  double _calculateDominantHeight(List<Arvore> arvores) {
    // Agora 'dominante' é um booleano simples no modelo, não precisa checar Enum
    final alturasDominantes = arvores.where((a) => a.dominante && a.altura != null && a.altura! > 0).map((a) => a.altura!).toList();
    if (alturasDominantes.isEmpty) return 0.0;
    return _calculateAverage(alturasDominantes);
  }

  double _calculateSiteIndex(double alturaDominante, double? idadeAtualAnos) {
    if (alturaDominante <= 0 || idadeAtualAnos == null || idadeAtualAnos <= 0) return 0.0;
    const double idadeReferencia = 7.0;
    const double coeficiente = -0.5; // Coeficiente empírico genérico para Eucalyptus
    // Modelo: IS = HD * exp( b * (1/I - 1/I_ref) )
    final indiceDeSitio = alturaDominante * exp(coeficiente * (1 / idadeAtualAnos - 1 / idadeReferencia));
    return indiceDeSitio;
  }

  double _areaBasalPorArvore(double cap) {
    if (cap <= 0) return 0.0;
    final double dap = cap / pi;
    return (pi * pow(dap, 2)) / 40000; // m²
  }

  // Volume estimado básico (Fator de Forma) quando não há equação ajustada
  double _estimateVolume(double cap, double altura) {
    if (cap <= 0 || altura <= 0) return 0.0;
    final areaBasal = _areaBasalPorArvore(cap);
    return areaBasal * altura * fatorDeForma;
  }

  // ===========================================================================
  // ===================== IMPLEMENTAÇÃO DO MODELO DE CURTIS ===================
  // ===========================================================================

  /// Ajusta a curva hipsométrica de Curtis: ln(h) = b0 + b1 * (1/DAP)
  Map<String, double>? _ajustarCurvaHipsometricaCurtis(List<Arvore> arvores) {
    // 1. Filtra árvores que têm CAP e Altura medidos (e válidos)
    final amostras = arvores.where((a) => a.cap > 0 && (a.altura ?? 0) > 0).toList();

    // Requer pelo menos 10 árvores medidas para significância mínima
    if (amostras.length < 10) return null;

    try {
      final List<Vector> xData = [];
      final List<double> yData = [];

      for (var a in amostras) {
        final dap = a.cap / pi;
        if (dap <= 0) continue;
        
        final invDap = 1.0 / dap; // Variável Independente (X)
        final lnH = log(a.altura!); // Variável Dependente (Y)

        xData.add(Vector.fromList([1.0, invDap])); // [Intercepto, Slope]
        yData.add(lnH);
      }

      final features = Matrix.fromRows(xData);
      final labels = Vector.fromList(yData);
      
      // Resolução OLS: (X^T * X)^-1 * X^T * Y
      final coefficients = (features.transpose() * features).inverse() * features.transpose() * labels;
      
      final b0 = coefficients.expand((e) => e).toList()[0];
      final b1 = coefficients.expand((e) => e).toList()[1];

      return {'b0': b0, 'b1': b1};

    } catch (e) {
      debugPrint("Erro matemático ao ajustar Curtis (Provável matriz singular): $e");
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
      // Se já tem altura medida, mantém
      if ((a.altura ?? 0) > 0) return a;

      // Se não tem CAP, não dá para estimar altura dendrométrica
      if (a.cap <= 0) return a.copyWith(altura: 0);

      // Tenta aplicar Curtis
      if (coeficientes != null) {
        final dap = a.cap / pi;
        final b0 = coeficientes['b0']!;
        final b1 = coeficientes['b1']!;
        
        final lnH = b0 + (b1 * (1.0 / dap));
        final alturaEstimada = exp(lnH);
        
        // Proteção contra valores absurdos (ex: altura negativa ou > 100m)
        if (alturaEstimada > 0 && alturaEstimada < 70) {
          return a.copyWith(altura: alturaEstimada);
        }
      }

      // Fallback: Usa a média do talhão/amostra
      return a.copyWith(altura: mediaAltura > 0 ? mediaAltura : 0);
    }).toList();
  }

  // ===========================================================================
  // ====================== ANÁLISE VOLUMÉTRICA COMPLETA =======================
  // ===========================================================================

  Future<AnaliseVolumetricaCompletaResult> gerarAnaliseVolumetricaCompleta({
    required List<CubagemArvore> arvoresParaRegressao,
    required List<Talhao> talhoesInventario,
  }) async {
    // 1. Gera equação de Volume (Schumacher-Hall) com base nas árvores cubadas
    final resultadosCompletosRegressao = await gerarEquacaoSchumacherHall(arvoresParaRegressao);
    final resultadoRegressao = resultadosCompletosRegressao['resultados'] as Map<String, dynamic>;
    final diagnosticoRegressao = resultadosCompletosRegressao['diagnostico'] as Map<String, dynamic>;
    
    if (resultadoRegressao.containsKey('error')) {
      throw Exception(resultadoRegressao['error']);
    }

    double volumeTotalLote = 0;
    double areaTotalLote = 0;
    double areaBasalMediaPonderada = 0;
    double arvoresHaMediaPonderada = 0;
    List<Arvore> todasAsArvoresDoInventarioComVolume = [];

    // 2. Aplica a equação nos talhões de inventário selecionados
    for (final talhao in talhoesInventario) {
      final dadosAgregados = await _analiseRepository.getDadosAgregadosDoTalhao(talhao.id!);
      final List<Parcela> parcelas = dadosAgregados['parcelas'];
      final List<Arvore> arvores = dadosAgregados['arvores'];
      
      if (parcelas.isEmpty || arvores.isEmpty) continue;

      // >>> PASSO CRÍTICO: Preencher alturas (Curtis) -> Calcular Volume (Schumacher)
      final arvoresComVolume = aplicarEquacaoDeVolume(
        arvoresDoInventario: arvores, 
        b0: resultadoRegressao['b0'], 
        b1: resultadoRegressao['b1'], 
        b2: resultadoRegressao['b2']
      );
      
      todasAsArvoresDoInventarioComVolume.addAll(arvoresComVolume);
      
      // Analisa o talhão usando as árvores já enriquecidas
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

    // 3. Calcula sortimentos baseados na cubagem original (proporção)
    final producaoPorSortimento = await _calcularProducaoPorSortimento(
      arvoresParaRegressao, 
      totaisInventario['volume_ha'] as double
    );
    
    // 4. Calcula contribuição de volume por código
    final volumePorCodigo = _calcularVolumePorCodigo(
      todasAsArvoresDoInventarioComVolume, 
      totaisInventario['volume_ha'] as double
    );

    return AnaliseVolumetricaCompletaResult(
      resultadoRegressao: resultadoRegressao,
      diagnosticoRegressao: diagnosticoRegressao,
      totaisInventario: totaisInventario,
      producaoPorSortimento: producaoPorSortimento,
      volumePorCodigo: volumePorCodigo,
    );
  }

  // --- REGRESSÃO SCHUMACHER-HALL ---
  // Modelo: ln(V) = b0 + b1*ln(DAP) + b2*ln(H)
  Future<Map<String, Map<String, dynamic>>> gerarEquacaoSchumacherHall(List<CubagemArvore> arvoresCubadas) async {
    final List<Vector> xData = [];
    final List<double> yData = [];
    final List<double> lnDapList = [];
    final List<double> lnAlturaList = [];

    for (final arvoreCubada in arvoresCubadas) {
      if (arvoreCubada.id == null) continue;
      final secoes = await _cubagemRepository.getSecoesPorArvoreId(arvoreCubada.id!);
      
      // Volume Real (Smalian)
      final volumeReal = calcularVolumeComercialSmalian(secoes);
      
      if (volumeReal <= 0 || arvoreCubada.valorCAP <= 0 || arvoreCubada.alturaTotal <= 0) continue;
      
      final dap = arvoreCubada.valorCAP / pi;
      final altura = arvoreCubada.alturaTotal;
      
      final lnVolume = log(volumeReal);
      final lnDAP = log(dap);
      final lnAltura = log(altura);

      xData.add(Vector.fromList([1.0, lnDAP, lnAltura])); // [Intercepto, lnDAP, lnH]
      yData.add(lnVolume);
      
      lnDapList.add(lnDAP);
      lnAlturaList.add(lnAltura);
    }

    final int n = xData.length;
    const int p = 3; // Parâmetros (b0, b1, b2)
    if (n < p) {
      return {'resultados': {'error': 'Dados insuficientes. Pelo menos $p árvores cubadas completas são necessárias.'}, 'diagnostico': {}};
    }

    // Verifica variância para evitar matriz singular
    double calculateStdDev(List<double> numbers) {
      if (numbers.length < 2) return 0.0;
      final mean = numbers.reduce((a, b) => a + b) / numbers.length;
      final variance = numbers.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / (numbers.length - 1);
      return sqrt(variance);
    }

    if (calculateStdDev(lnDapList) < 0.0001 || calculateStdDev(lnAlturaList) < 0.0001) {
      return {'resultados': {'error': 'Variação de dados insuficiente (DAP ou Altura constantes).'}, 'diagnostico': {}};
    }

    final features = Matrix.fromRows(xData);
    final labels = Vector.fromList(yData);

    try {
      // Cálculo dos coeficientes OLS: (X'X)^-1 X'Y
      final coefficients = (features.transpose() * features).inverse() * features.transpose() * labels;
      final List<double> coeffsAsList = coefficients.expand((e) => e).toList();
      final double b0 = coeffsAsList[0];
      final double b1 = coeffsAsList[1];
      final double b2 = coeffsAsList[2];

      // Estatísticas
      final predictedValues = features * coefficients;
      final yMean = labels.mean();
      final totalSumOfSquares = labels.fold(0.0, (sum, val) => sum + pow(val - yMean, 2));
      final residuals = labels - predictedValues;
      final residualSumOfSquares = residuals.fold(0.0, (sum, val) => sum + pow(val, 2));

      final rSquared = (totalSumOfSquares == 0) ? 0.0 : 1 - (residualSumOfSquares / totalSumOfSquares);
      final double mse = residualSumOfSquares / (n - p);
      final double syx = sqrt(mse); // Erro Padrão da Estimativa (log unit)
      
      return {
        'resultados': {
          'b0': b0, 'b1': b1, 'b2': b2, 
          'R2': rSquared, 
          'equacao': 'ln(V) = ${b0.toStringAsFixed(5)} + ${b1.toStringAsFixed(5)}*ln(DAP) + ${b2.toStringAsFixed(5)}*ln(H)', 
          'n_amostras': n,
        },
        'diagnostico': {
          'syx': syx, 
          'syx_percent': yMean != 0 ? (syx / yMean) * 100 : 0.0, 
          'shapiro_wilk_p_value': null, 
        }
      };
    } catch (e) {
      return {'resultados': {'error': 'Erro matemático na regressão. Detalhe: $e'}, 'diagnostico': {}};
    }
  }

  // Aplica a equação de Schumacher nas árvores do inventário
  // IMPORTANTE: Primeiro preenche as alturas (Curtis), depois calcula volume
  List<Arvore> aplicarEquacaoDeVolume({required List<Arvore> arvoresDoInventario, required double b0, required double b1, required double b2}) {
    // 1. Estima alturas para árvores que não foram medidas
    final arvoresComAltura = _preencherAlturasFaltantes(arvoresDoInventario);
    
    final List<Arvore> arvoresComVolume = [];
    
    // Lista de códigos que não geram volume (Falha, Morta, Caída)
    const codigosSemVolume = ["F", "M", "CA", "CR"];

    for (final arvore in arvoresComAltura) {
      if (arvore.cap <= 0 || codigosSemVolume.contains(arvore.codigo)) {
        arvoresComVolume.add(arvore.copyWith(volume: 0));
        continue;
      }
      
      // Altura já foi garantida pelo _preencherAlturasFaltantes
      final alturaParaCalculo = arvore.altura!;
      
      if (alturaParaCalculo <= 0.1) {
        arvoresComVolume.add(arvore.copyWith(volume: 0));
        continue;
      }

      final dap = arvore.cap / pi;
      
      // Fórmula Schumacher-Hall Linearizada: ln(V) = b0 + b1*ln(D) + b2*ln(H)
      // Volume = exp(ln(V))
      final lnVolume = b0 + (b1 * log(dap)) + (b2 * log(alturaParaCalculo));
      final volumeEstimado = exp(lnVolume);
      
      arvoresComVolume.add(arvore.copyWith(volume: volumeEstimado));
    }
    return arvoresComVolume;
  }

  double calcularVolumeComercialSmalian(List<CubagemSecao> secoes) {
    if (secoes.length < 2) return 0.0;
    secoes.sort((a, b) => a.alturaMedicao.compareTo(b.alturaMedicao));
    double volumeTotal = 0.0;
    for (int i = 0; i < secoes.length - 1; i++) {
      final secao1 = secoes[i];
      final secao2 = secoes[i + 1];
      
      // Converte cm para metros para área em m²
      final diametro1m = secao1.diametroSemCasca / 100;
      final diametro2m = secao2.diametroSemCasca / 100;
      
      final area1 = (pi * pow(diametro1m, 2)) / 4;
      final area2 = (pi * pow(diametro2m, 2)) / 4;
      
      final comprimentoTora = secao2.alturaMedicao - secao1.alturaMedicao;
      
      // Fórmula de Smalian
      final volumeTora = ((area1 + area2) / 2) * comprimentoTora;
      volumeTotal += volumeTora;
    }
    return volumeTotal;
  }

  // --- MÉTODOS DE ANÁLISE GERAL ---

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
    final sortedKeys = volumesAcumuladosSortimento.keys.toList()..sort();

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
    
    // Agrupa pela String do código
    final Map<String, double> volumeAcumuladoPorCodigo = {};
    for (var a in arvoresComVolume) {
      volumeAcumuladoPorCodigo.update(a.codigo, (val) => val + (a.volume ?? 0), ifAbsent: () => (a.volume ?? 0));
    }

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

  // Analisa um único talhão
  TalhaoAnalysisResult getTalhaoInsights(Talhao talhao, List<Parcela> parcelasDoTalhao, List<Arvore> todasAsArvores) {
    if (parcelasDoTalhao.isEmpty) return TalhaoAnalysisResult();
    
    final double areaTotalAmostradaM2 = parcelasDoTalhao.map((p) => p.areaMetrosQuadrados).fold(0.0, (a, b) => a + b);
    if (areaTotalAmostradaM2 == 0) return TalhaoAnalysisResult();
    
    final double areaTotalAmostradaHa = areaTotalAmostradaM2 / 10000;
    final codeAnalysis = getTreeCodeAnalysis(todasAsArvores);
    
    return _analisarListaDeArvores(talhao, todasAsArvores, areaTotalAmostradaHa, parcelasDoTalhao.length, codeAnalysis);
  }
  
  TalhaoAnalysisResult _analisarListaDeArvores(Talhao talhao, List<Arvore> arvoresDoConjunto, double areaTotalAmostradaHa, int numeroDeParcelas, CodeAnalysisResult? codeAnalysis) {
    if (arvoresDoConjunto.isEmpty || areaTotalAmostradaHa <= 0) return TalhaoAnalysisResult();
    
    // IMPORTANTE: Preenche alturas faltantes com Curtis antes da análise estatística
    final List<Arvore> arvoresComAlturaCompleta = _preencherAlturasFaltantes(arvoresDoConjunto);

    const codigosSemVolume = ["F", "M", "CA", "CR"];
    final List<Arvore> arvoresVivas = arvoresComAlturaCompleta.where((a) => !codigosSemVolume.contains(a.codigo)).toList();
    
    if (arvoresVivas.isEmpty) return TalhaoAnalysisResult(warnings: ["Nenhuma árvore viva encontrada."]);

    // Médias
    final double mediaCap = _calculateAverage(arvoresVivas.map((a) => a.cap).toList());
    final double mediaAltura = _calculateAverage(arvoresVivas.map((a) => a.altura!).toList());

    // Área Basal
    final double areaBasalTotalAmostrada = arvoresVivas.map((a) => _areaBasalPorArvore(a.cap)).fold(0.0, (a, b) => a + b);
    final double areaBasalPorHectare = areaBasalTotalAmostrada / areaTotalAmostradaHa;
    
    // Volume (Se já tiver calculado por Schumacher, usa; senão estima por Fator de Forma)
    final double volumeTotalAmostrado = arvoresVivas.map((a) => a.volume ?? _estimateVolume(a.cap, a.altura!)).fold(0.0, (a, b) => a + b);
    final double volumePorHectare = volumeTotalAmostrado / areaTotalAmostradaHa;
    
    final int arvoresPorHectare = (arvoresVivas.length / areaTotalAmostradaHa).round();
    final double alturaDominante = _calculateDominantHeight(arvoresVivas);
    final double indiceDeSitio = _calculateSiteIndex(alturaDominante, talhao.idadeAnos);

    List<String> warnings = [];
    List<String> insights = [];
    List<String> recommendations = [];

    // Lógica simples de insights
    if (areaBasalPorHectare > 35) insights.add("Densidade alta (G > 35 m²/ha). Avaliar desbaste.");
    
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
    
    // Agrupa por código (String)
    final contagemPorCodigo = arvores.groupBy<String>((arvore) => arvore.codigo).map((key, value) => MapEntry(key, value.length));
    
    final covasUnicas = arvores.map((a) => '${a.linha}-${a.posicaoNaLinha}').toSet();
    final totalCovasAmostradas = covasUnicas.length;
    // Considera ocupada se o código não for "F" (Falha)
    final totalCovasOcupadas = arvores.where((a) => a.codigo != "F").map((a) => '${a.linha}-${a.posicaoNaLinha}').toSet().length;
    
    final Map<String, CodeStatDetails> estatisticas = {};
    final arvoresAgrupadas = arvores.groupBy((Arvore a) => a.codigo);

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

  // --- PLANEJAMENTO DE CUBAGEM E SIMULAÇÃO ---

  Map<double, int> getDistribuicaoPorMetrica({required List<Arvore> arvores, required MetricaDistribuicao metrica, double? larguraClasseManual}) {
    final double larguraClasse = larguraClasseManual ?? ((metrica == MetricaDistribuicao.cap) ? 15.0 : 5.0);
    if (arvores.isEmpty || larguraClasse <= 0) return {};
    
    final Map<int, int> contagemPorClasse = {};
    
    for (final arvore in arvores) {
      if (arvore.cap > 0) {
        final double valor = (metrica == MetricaDistribuicao.dap) ? arvore.cap / pi : arvore.cap;
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

  TalhaoAnalysisResult simularDesbaste({
    required Talhao talhao,
    required List<Parcela> parcelasOriginais,
    required List<Arvore> todasAsArvores,
    required double porcentagemRemocaoSeletiva,
    required bool sistematicoAtivo,
    required int? linhaSistematica,
  }) {
    if (parcelasOriginais.isEmpty || todasAsArvores.isEmpty) {
      return getTalhaoInsights(talhao, parcelasOriginais, todasAsArvores);
    }

    const codigosSemVolume = ["F", "M", "CA", "CR"];
    final List<Arvore> arvoresVivas = todasAsArvores.where((a) => !codigosSemVolume.contains(a.codigo)).toList();
    
    List<Arvore> arvoresRemanescentes;

    if (sistematicoAtivo && linhaSistematica != null && linhaSistematica > 0) {
      // 1. Remove linhas sistemáticas
      final arvoresParaDesbasteSeletivo = arvoresVivas.where((a) => a.linha % linhaSistematica != 0).toList();
      
      // 2. Aplica desbaste seletivo nas remanescentes (remove as piores/menores)
      arvoresParaDesbasteSeletivo.sort((a, b) => a.cap.compareTo(b.cap));
      final int qtdRemoverSeletivo = (arvoresParaDesbasteSeletivo.length * (porcentagemRemocaoSeletiva / 100)).floor();
      
      arvoresRemanescentes = arvoresParaDesbasteSeletivo.sublist(qtdRemoverSeletivo);
    } else {
      // Apenas desbaste seletivo
      arvoresVivas.sort((a, b) => a.cap.compareTo(b.cap));
      final int qtdRemover = (arvoresVivas.length * (porcentagemRemocaoSeletiva / 100)).floor();
      arvoresRemanescentes = arvoresVivas.sublist(qtdRemover);
    }

    final double areaTotalAmostradaM2 = parcelasOriginais.map((p) => p.areaMetrosQuadrados).fold(0.0, (a, b) => a + b);
    
    final codeAnalysisRemanescente = getTreeCodeAnalysis(arvoresRemanescentes);
    
    return _analisarListaDeArvores(talhao, arvoresRemanescentes, areaTotalAmostradaM2 / 10000, parcelasOriginais.length, codeAnalysisRemanescente);
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
    
    // Ajuste fino para bater a quantidade exata
    int somaAtual = plano.values.fold(0, (a, b) => a + b);
    int diferenca = totalArvoresParaCubar - somaAtual;

    if (diferenca != 0 && plano.isNotEmpty) {
      // Adiciona a diferença à classe mais frequente
      final classeMaisFrequente = plano.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      plano[classeMaisFrequente] = plano[classeMaisFrequente]! + diferenca;
    }
    
    return plano;
  }

  // Consolidação de Estrato
  TalhaoAnalysisResult analisarEstratoUnificado({
    required List<Talhao> talhoes,
    required Map<int, List<Parcela>> parcelasPorTalhao,
    required Map<int, List<Arvore>> arvoresPorTalhao,
  }) {
    double areaTotalEstrato = 0;
    List<Parcela> todasParcelas = [];
    List<Arvore> todasArvores = [];
    
    double somaVolumeTotal = 0;
    double somaAreaBasalTotal = 0;
    double somaArvoresTotal = 0;

    for (var talhao in talhoes) {
      if (talhao.id == null) continue;
      
      final areaTalhao = talhao.areaHa ?? 0.0;
      final parcelas = parcelasPorTalhao[talhao.id] ?? [];
      final arvores = arvoresPorTalhao[talhao.id] ?? [];
      
      if (parcelas.isEmpty || arvores.isEmpty) continue;

      // Analisa individualmente para obter médias por hectare
      final analiseIndividual = getTalhaoInsights(talhao, parcelas, arvores);
      
      areaTotalEstrato += areaTalhao;
      todasParcelas.addAll(parcelas);
      todasArvores.addAll(arvores);
      
      if (areaTalhao > 0) {
        somaVolumeTotal += (analiseIndividual.volumePorHectare * areaTalhao);
        somaAreaBasalTotal += (analiseIndividual.areaBasalPorHectare * areaTalhao);
        somaArvoresTotal += (analiseIndividual.arvoresPorHectare * areaTalhao);
      }
    }

    if (areaTotalEstrato == 0 || todasArvores.isEmpty) return TalhaoAnalysisResult();

    // Médias ponderadas
    final volumePorHectareEstrato = somaVolumeTotal / areaTotalEstrato;
    final areaBasalPorHectareEstrato = somaAreaBasalTotal / areaTotalEstrato;
    final arvoresPorHectareEstrato = (somaArvoresTotal / areaTotalEstrato).round();

    // Análise qualitativa usa a amostra total agregada
    final codeAnalysis = getTreeCodeAnalysis(todasArvores);
    
    const codigosSemVolume = ["F", "M", "CA", "CR"];
    final arvoresVivas = todasArvores.where((a) => !codigosSemVolume.contains(a.codigo)).toList();
    
    final double mediaCap = _calculateAverage(arvoresVivas.map((a) => a.cap).toList());
    final double mediaAltura = _calculateAverage(arvoresVivas.map((a) => a.altura ?? 0).where((h) => h > 0).toList());
    final double alturaDominante = _calculateDominantHeight(arvoresVivas);
    
    final mediaIdade = talhoes.map((t) => t.idadeAnos ?? 0).reduce((a, b) => a + b) / talhoes.length;
    final double indiceDeSitio = _calculateSiteIndex(alturaDominante, mediaIdade);
    
    final distribuicao = getDistribuicaoDiametrica(arvoresVivas);

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
      insights: ["Análise consolidada de ${talhoes.length} talhões.", "Área total do estrato: ${areaTotalEstrato.toStringAsFixed(2)} ha."],
      recommendations: ["Estrato calculado com médias ponderadas pela área dos talhões."],
    );
  }
  
  // (Método criarMultiplasAtividadesDeCubagem omitido aqui, mas deve estar presente conforme versão anterior do context, usando getDistribuicaoPorMetrica)
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

    // 1. Distribui a quantidade total entre os talhões
    if (metodo == MetodoDistribuicaoCubagem.fixoPorTalhao) {
      for (final talhao in talhoes) {
        if (talhao.id != null) quantidadesPorTalhao[talhao.id!] = quantidade;
      }
    } else {
      double areaTotal = talhoes.map((t) => t.areaHa ?? 0.0).fold(0.0, (p, a) => p + a);
      if (areaTotal <= 0) throw Exception("Área total zero.");
      int distribuidos = 0;
      for (int i = 0; i < talhoes.length; i++) {
        final t = talhoes[i];
        if (t.id == null) continue;
        if (i == talhoes.length - 1) {
          quantidadesPorTalhao[t.id!] = quantidade - distribuidos;
        } else {
          final qtd = (quantidade * (t.areaHa ?? 0.0) / areaTotal).round();
          quantidadesPorTalhao[t.id!] = qtd;
          distribuidos += qtd;
        }
      }
    }

    final Map<Talhao, List<CubagemArvore>> planosCompletos = {};

    for (final talhao in talhoes) {
      if (talhao.id == null) continue;
      final qtdAlvo = quantidadesPorTalhao[talhao.id!] ?? 0;
      if (qtdAlvo <= 0) continue;

      final dados = await _analiseRepository.getDadosAgregadosDoTalhao(talhao.id!);
      final List<Arvore> arvores = dados['arvores'];
      final List<Parcela> parcelas = dados['parcelas'];
      if (arvores.isEmpty) continue;

      final analise = getTalhaoInsights(talhao, parcelas, arvores);
      
      final distribuicao = getDistribuicaoPorMetrica(
        arvores: arvores, metrica: metrica, larguraClasseManual: isIntervaloManual ? intervaloManual : null
      );

      final plano = gerarPlanoDeCubagem(
        distribuicaoAmostrada: distribuicao,
        totalArvoresAmostradas: analise.totalArvoresAmostradas,
        totalArvoresParaCubar: qtdAlvo,
        metrica: metrica,
        larguraClasseManual: isIntervaloManual ? intervaloManual : null
      );

      if (plano.isNotEmpty) {
        planosGerados[talhao] = plano;
        final List<CubagemArvore> placeholders = [];
        plano.forEach((classe, q) {
          for(int i=1; i<=q; i++) {
             placeholders.add(CubagemArvore(
               nomeFazenda: talhao.fazendaNome ?? 'N/A',
               idFazenda: talhao.fazendaId,
               nomeTalhao: talhao.nome,
               classe: classe,
               identificador: 'PLANO-${classe.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-')}-${i.toString().padLeft(2, '0')}',
               alturaTotal: 0, valorCAP: 0,
             ));
          }
        });
        planosCompletos[talhao] = placeholders;
      }
    }

    if (planosCompletos.isNotEmpty) {
      final primeiro = planosCompletos.keys.first;
      final projeto = await _projetoRepository.getProjetoPelaAtividade(primeiro.fazendaAtividadeId);
      if (projeto != null) {
        final novaAtividade = Atividade(
          projetoId: projeto.id!, 
          tipo: 'Cubagem - $metodoCubagem', 
          descricao: 'Plano gerado automaticamente', 
          dataCriacao: DateTime.now(), 
          metodoCubagem: metodoCubagem
        );
        await _atividadeRepository.criarAtividadeUnicaComMultiplosPlanos(novaAtividade, planosCompletos);
      }
    }

    return planosGerados;
  }
}
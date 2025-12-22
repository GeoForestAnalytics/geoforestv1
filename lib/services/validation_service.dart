// lib/services/validation_service.dart (VERSÃO CORRIGIDA - REGRA BIFURCADA vs MÚLTIPLA)

import 'dart:math';
import 'package:collection/collection.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';

class ValidationResult {
  final bool isValid;
  final List<String> warnings;
  ValidationResult({this.isValid = true, this.warnings = const []});
}

class ValidationIssue {
  final String tipo;
  final String mensagem;
  final int? parcelaId;
  final int? cubagemId;
  final int? arvoreId;
  final String identificador;

  ValidationIssue({
    required this.tipo,
    required this.mensagem,
    this.parcelaId,
    this.cubagemId,
    this.arvoreId,
    required this.identificador,
  });
}

class FullValidationReport {
  final List<ValidationIssue> issues;
  final int parcelasVerificadas;
  final int arvoresVerificadas;
  final int cubagensVerificadas;

  FullValidationReport({
    this.issues = const [],
    required this.parcelasVerificadas,
    required this.arvoresVerificadas,
    required this.cubagensVerificadas,
  });

  bool get isConsistent => issues.isEmpty;
}

class ValidationService {
  
  ValidationResult validateSingleTree(Arvore arvore) {
    final List<String> warnings = [];
    if (arvore.codigo != Codigo.Falha && arvore.codigo != Codigo.Caida) {
      if (arvore.cap <= 5.0) {
        warnings.add("CAP de ${arvore.cap} cm é muito baixo. Verifique.");
      }
      if (arvore.cap > 400.0) {
        warnings.add("CAP de ${arvore.cap} cm é fisicamente improvável. Verifique.");
      }
    }
    if (arvore.altura != null && arvore.altura! > 70) {
      warnings.add("Altura de ${arvore.altura}m é extremamente rara. Confirme.");
    }
    if (arvore.altura != null && arvore.cap > 150 && arvore.altura! < 10) {
      warnings.add("Relação CAP/Altura incomum: ${arvore.cap} cm de CAP com apenas ${arvore.altura}m de altura.");
    }
    if (arvore.altura != null && arvore.alturaDano != null && arvore.altura! > 0 && arvore.alturaDano! >= arvore.altura!) {
      warnings.add("Altura do Dano (${arvore.alturaDano}m) não pode ser maior ou igual à Altura Total (${arvore.altura}m).");
    }
    return ValidationResult(isValid: warnings.isEmpty, warnings: warnings);
  }

  ValidationResult validateParcela(List<Arvore> arvores) {
    final arvoresValidasParaAnalise = arvores.where((a) => a.codigo != Codigo.Falha && a.codigo != Codigo.Caida).toList();
    if (arvoresValidasParaAnalise.length < 10) return ValidationResult();
    final List<String> warnings = [];
    double somaCap = arvoresValidasParaAnalise.map((a) => a.cap).reduce((a, b) => a + b);
    double mediaCap = somaCap / arvoresValidasParaAnalise.length;
    double somaDiferencasQuadrado = arvoresValidasParaAnalise.map((a) => pow(a.cap - mediaCap, 2)).reduce((a, b) => a + b).toDouble();
    if (arvoresValidasParaAnalise.length <= 1) return ValidationResult();
    double desvioPadraoCap = sqrt(somaDiferencasQuadrado / (arvoresValidasParaAnalise.length - 1));
    for (final arvore in arvoresValidasParaAnalise) {
      if ((arvore.cap - mediaCap).abs() > 2.5 * desvioPadraoCap) {
        warnings.add("Árvore Linha ${arvore.linha}/Pos ${arvore.posicaoNaLinha}: O CAP de ${arvore.cap}cm é um outlier estatístico (média: ${mediaCap.toStringAsFixed(1)}cm).");
      }
    }
    return ValidationResult(isValid: warnings.isEmpty, warnings: warnings);
  }

  Future<FullValidationReport> performFullConsistencyCheck({
    required List<Parcela> parcelas,
    required List<CubagemArvore> cubagens,
    required ParcelaRepository parcelaRepo,
    required CubagemRepository cubagemRepo,
  }) async {
    final List<ValidationIssue> allIssues = [];

    int arvoresVerificadas = 0;
    for (final parcela in parcelas) {
      final arvores = await parcelaRepo.getArvoresDaParcela(parcela.dbId!);
      arvoresVerificadas += arvores.length;
      allIssues.addAll(_checkParcelaStructure(parcela, arvores));
    }
    
    for (final cubagem in cubagens) {
      allIssues.addAll(await _checkCubagemIntegrity(cubagem, cubagemRepo));
    }

    return FullValidationReport(
      issues: allIssues,
      parcelasVerificadas: parcelas.length,
      arvoresVerificadas: arvoresVerificadas,
      cubagensVerificadas: cubagens.length,
    );
  }

  List<ValidationIssue> _checkParcelaStructure(Parcela parcela, List<Arvore> arvores) {
    final List<ValidationIssue> issues = [];
    final identificador = "${parcela.idParcela} (Talhão: ${parcela.nomeTalhao})";

    if (arvores.isEmpty) return issues;

    final primeiraArvore = arvores.first;
    if (primeiraArvore.linha != 1 || primeiraArvore.posicaoNaLinha != 1) {
      issues.add(ValidationIssue(tipo: 'Início Inválido', mensagem: 'A primeira árvore não é Linha 1 / Posição 1. Começa em L:${primeiraArvore.linha} P:${primeiraArvore.posicaoNaLinha}.', parcelaId: parcela.dbId!, identificador: identificador));
    }

    final arvoresPorLinha = groupBy(arvores, (Arvore a) => a.linha);
    final linhasUnicas = arvoresPorLinha.keys.toList()..sort();

    for (int i = 0; i < linhasUnicas.length - 1; i++) {
      if (linhasUnicas[i+1] != linhasUnicas[i] + 1) {
        issues.add(ValidationIssue(tipo: 'Sequência de Linha', mensagem: 'Sequência de linha quebrada. Pulou de ${linhasUnicas[i]} para ${linhasUnicas[i+1]}.', parcelaId: parcela.dbId!, identificador: identificador));
        break;
      }
    }

    arvoresPorLinha.forEach((linha, arvoresDaLinha) {
      arvoresDaLinha.sort((a, b) => a.posicaoNaLinha.compareTo(b.posicaoNaLinha));

      for (int i = 0; i < arvoresDaLinha.length - 1; i++) {
        final atual = arvoresDaLinha[i];
        final proxima = arvoresDaLinha[i+1];

        // Se a posição for a mesma, verifica se é aceitável (Múltipla)
        // A checagem de "código correto" é feita no bloco 'posicoesAgrupadas' abaixo.
        // Aqui apenas pulamos o erro de "sequência quebrada" se for a mesma posição.
        if (proxima.posicaoNaLinha == atual.posicaoNaLinha) {
          continue;
        }

        // Se pulou número (ex: 1 para 3), aí sim é erro
        if (proxima.posicaoNaLinha != atual.posicaoNaLinha + 1) {
          final posFaltando = atual.posicaoNaLinha + 1;
          issues.add(ValidationIssue(tipo: 'Sequência de Posição', mensagem: 'Na Linha $linha, a sequência pulou da Posição ${atual.posicaoNaLinha} para ${proxima.posicaoNaLinha} (faltando P$posFaltando).', parcelaId: parcela.dbId!, identificador: identificador));
        }
      }
      
      if (arvoresDaLinha.isNotEmpty && !arvoresDaLinha.last.fimDeLinha) {
        issues.add(ValidationIssue(tipo: 'Fim de Linha Ausente', mensagem: 'A última árvore da Linha $linha (Posição ${arvoresDaLinha.last.posicaoNaLinha}) não está marcada como "Fim de Linha".', parcelaId: parcela.dbId!, arvoreId: arvoresDaLinha.last.id, identificador: identificador));
      }
    });

    final posicoesAgrupadas = groupBy(arvores, (Arvore a) => '${a.linha}-${a.posicaoNaLinha}');
    posicoesAgrupadas.forEach((pos, arvoresNaPosicao) {
      // Se tiver mais de uma árvore na mesma posição (cova)
      if (arvoresNaPosicao.length > 1) {
        // ✅ CORREÇÃO: Apenas "Multipla" justifica ter > 1 registro na mesma cova
        // "Bifurcada" foi removido daqui pois é um único fuste na base.
        final temMultipla = arvoresNaPosicao.any((a) => a.codigo == Codigo.Multipla);
        
        if (!temMultipla) {
          issues.add(ValidationIssue(tipo: 'Árvore Duplicada', mensagem: 'A posição L:${pos.split('-')[0]} P:${pos.split('-')[1]} está duplicada sem o código "Multipla".', parcelaId: parcela.dbId!, identificador: identificador));
        }
      } 
      // Se tiver só uma árvore, mas ela diz que é Multipla (Erro: Múltipla solitária)
      else if (arvoresNaPosicao.length == 1 && arvoresNaPosicao.first.codigo == Codigo.Multipla) {
         issues.add(ValidationIssue(tipo: 'Código Inconsistente', mensagem: 'A posição L:${pos.split('-')[0]} P:${pos.split('-')[1]} tem código "Multipla" mas apenas 1 fuste registrado.', parcelaId: parcela.dbId!, arvoreId: arvoresNaPosicao.first.id, identificador: identificador));
      }
    });

    for (final arvore in arvores) {
      final singleValidation = validateSingleTree(arvore);
      if (!singleValidation.isValid) {
        issues.add(ValidationIssue(tipo: 'Outlier de Dados', mensagem: 'Árvore L:${arvore.linha} P:${arvore.posicaoNaLinha}: ${singleValidation.warnings.join(", ")}', parcelaId: parcela.dbId!, arvoreId: arvore.id, identificador: identificador));
      }
      if (arvore.codigo == Codigo.Falha && arvore.cap > 0) {
        issues.add(ValidationIssue(tipo: 'Código Inconsistente', mensagem: 'Árvore L:${arvore.linha} P:${arvore.posicaoNaLinha} é "Falha" mas tem CAP > 0.', parcelaId: parcela.dbId!, arvoreId: arvore.id, identificador: identificador));
      }
    }
    return issues;
  }

  Future<List<ValidationIssue>> _checkCubagemIntegrity(CubagemArvore cubagem, CubagemRepository cubagemRepo) async {
    final List<ValidationIssue> issues = [];
    final identificador = "${cubagem.identificador} (Talhão: ${cubagem.nomeTalhao})";
    
    final secoes = await cubagemRepo.getSecoesPorArvoreId(cubagem.id!);
    if (secoes.length >= 2) {
      secoes.sort((a, b) => a.alturaMedicao.compareTo(b.alturaMedicao));
      for (int i = 1; i < secoes.length; i++) {
        final secaoAnterior = secoes[i - 1];
        final secaoAtual = secoes[i];
        if (secaoAtual.diametroSemCasca > secaoAnterior.diametroSemCasca) {
          issues.add(ValidationIssue(tipo: 'Afilamento Incorreto', mensagem: 'Diâmetro a ${secaoAtual.alturaMedicao}m (${secaoAtual.diametroSemCasca.toStringAsFixed(1)}cm) é maior que o diâmetro a ${secaoAnterior.alturaMedicao}m (${secaoAnterior.diametroSemCasca.toStringAsFixed(1)}cm).', cubagemId: cubagem.id, identificador: identificador));
        }
      }
    }

    if (cubagem.classe != null && cubagem.classe!.isNotEmpty && cubagem.valorCAP > 0) {
      final dap = cubagem.valorCAP / pi;
      final numerosNaClasse = RegExp(r'(\d+\.?\d*)').allMatches(cubagem.classe!).map((m) => double.tryParse(m.group(1) ?? '0')).whereType<double>().toList();
      
      if (numerosNaClasse.length >= 2) {
        numerosNaClasse.sort();
        final minClasse = numerosNaClasse.first;
        final maxClasse = numerosNaClasse.last;
        if (dap < minClasse || dap >= maxClasse) {
           issues.add(ValidationIssue(tipo: 'Fora da Classe', mensagem: 'Árvore com DAP ${dap.toStringAsFixed(1)}cm está fora da sua classe designada (${cubagem.classe}).', cubagemId: cubagem.id, identificador: identificador));
        }
      }
    }
    return issues;
  }
}
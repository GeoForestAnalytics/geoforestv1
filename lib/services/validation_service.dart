// lib/services/validation_service.dart (VERSÃO COM A CLASSE FALTANTE REINSERIDA)

import 'dart:math';
import 'package:collection/collection.dart';
import 'package:geoforestv1/data/repositories/cubagem_repository.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';

// =========================================================================
// MODELOS PARA ESTRUTURAR O RELATÓRIO DE CONSISTÊNCIA
// =========================================================================

// ✅ CLASSE QUE ESTAVA FALTANDO, AGORA ADICIONADA NOVAMENTE
class ValidationResult {
  final bool isValid;
  final List<String> warnings;
  ValidationResult({this.isValid = true, this.warnings = const []});
}

/// Representa um único problema de consistência encontrado nos dados.
class ValidationIssue {
  final String tipo; // Ex: "Outlier de CAP", "Sequência Quebrada", "Afilamento Incorreto"
  final String mensagem; // Ex: "CAP de 250cm é um outlier."
  final int? parcelaId; // ID da parcela (se for erro de inventário)
  final int? cubagemId; // ID da cubagem (se for erro de cubagem)
  final int? arvoreId; // ID da árvore específica (se aplicável)
  final String identificador; // Ex: "Parcela P05 (Talhão T2)" ou "Cubagem CUB-01"

  ValidationIssue({
    required this.tipo,
    required this.mensagem,
    this.parcelaId,
    this.cubagemId,
    this.arvoreId,
    required this.identificador,
  });
}

/// Contém o resultado completo da verificação de consistência.
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

  /// Retorna `true` se nenhum problema foi encontrado.
  bool get isConsistent => issues.isEmpty;
}


// =========================================================================
// SERVIÇO DE VALIDAÇÃO
// =========================================================================

class ValidationService {
  
  // Nenhuma alteração aqui, mas agora ele encontrará a classe `ValidationResult`.
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
    return ValidationResult(isValid: warnings.isEmpty, warnings: warnings);
  }

  // Nenhuma alteração aqui, mas agora ele encontrará a classe `ValidationResult`.
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

  // O resto do arquivo permanece o mesmo...
  Future<FullValidationReport> performFullConsistencyCheck({
    required List<Parcela> parcelas,
    required List<CubagemArvore> cubagens,
    required ParcelaRepository parcelaRepo,
    required CubagemRepository cubagemRepo,
  }) async {
    final List<ValidationIssue> allIssues = [];

    // --- VERIFICAÇÃO DE INVENTÁRIO ---
    int arvoresVerificadas = 0;
    for (final parcela in parcelas) {
      final arvores = await parcelaRepo.getArvoresDaParcela(parcela.dbId!);
      arvoresVerificadas += arvores.length;
      allIssues.addAll(_checkParcelaStructure(parcela, arvores));
    }

    // --- VERIFICAÇÃO DE CUBAGEM ---
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

    // CHECK 1: Início da parcela
    final primeiraArvore = arvores.first;
    if (primeiraArvore.linha != 1 || primeiraArvore.posicaoNaLinha != 1) {
      issues.add(ValidationIssue(tipo: 'Início Inválido', mensagem: 'A primeira árvore não é Linha 1 / Posição 1. Começa em L:${primeiraArvore.linha} P:${primeiraArvore.posicaoNaLinha}.', parcelaId: parcela.dbId!, identificador: identificador));
    }

    // CHECK 2: Sequência de linhas
    final linhasUnicas = arvores.map((a) => a.linha).toSet().toList()..sort();
    for (int i = 0; i < linhasUnicas.length - 1; i++) {
      if (linhasUnicas[i+1] != linhasUnicas[i] + 1) {
        issues.add(ValidationIssue(tipo: 'Sequência de Linha', mensagem: 'Sequência de linha quebrada. Pulou de ${linhasUnicas[i]} para ${linhasUnicas[i+1]}.', parcelaId: parcela.dbId!, identificador: identificador));
        break;
      }
    }

    // CHECK 3: Duplicatas e códigos
    final posicoesAgrupadas = groupBy(arvores, (Arvore a) => '${a.linha}-${a.posicaoNaLinha}');
    posicoesAgrupadas.forEach((pos, arvoresNaPosicao) {
      if (arvoresNaPosicao.length > 1) {
        final temMultipla = arvoresNaPosicao.any((a) => a.codigo == Codigo.Multipla);
        if (!temMultipla) {
          issues.add(ValidationIssue(tipo: 'Árvore Duplicada', mensagem: 'A posição L:${pos.split('-')[0]} P:${pos.split('-')[1]} está duplicada sem o código "Multipla".', parcelaId: parcela.dbId!, identificador: identificador));
        }
      } else if (arvoresNaPosicao.length == 1 && arvoresNaPosicao.first.codigo == Codigo.Multipla) {
        issues.add(ValidationIssue(tipo: 'Código Inconsistente', mensagem: 'A posição L:${pos.split('-')[0]} P:${pos.split('-')[1]} tem código "Multipla" mas apenas 1 fuste.', parcelaId: parcela.dbId!, arvoreId: arvoresNaPosicao.first.id, identificador: identificador));
      }
    });

    // CHECK 4: Outliers e inconsistências individuais
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
    
    // CHECK 1: Afilamento Incorreto
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

    // CHECK 2: Árvore fora da classe
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
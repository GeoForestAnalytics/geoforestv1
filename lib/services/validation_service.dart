// lib/services/validation_service.dart

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
  final int? arvoreId; // ID da árvore para o "Pulo Direto"
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
  
  /// Converte os resultados brutos da IA para a lista de problemas clicáveis
  List<ValidationIssue> mapIaErrorsToIssues(
    List<Map<String, dynamic>> iaErros, 
    Parcela parcela
  ) {
    final idRelatorio = "P${parcela.idParcela} | IA - ${parcela.nomeTalhao}";
    
    return iaErros.map((erro) {
      return ValidationIssue(
        tipo: 'Análise IA',
        mensagem: erro['msg'] ?? 'Inconsistência detectada pela IA.',
        parcelaId: parcela.dbId,
        arvoreId: erro['id'], // Aqui o ID que a IA devolveu faz a mágica
        identificador: idRelatorio,
      );
    }).toList();
  }

  ValidationResult validateParcela(List<Arvore> arvores) {
    final List<String> warnings = [];
    final vivas = arvores.where((a) => a.codigo != Codigo.Falha && a.codigo != Codigo.Caida && a.cap > 0).toList();
    
    if (vivas.length < 5) return ValidationResult(isValid: true, warnings: []);

    double somaCap = vivas.map((a) => a.cap).reduce((a, b) => a + b);
    double mediaCap = somaCap / vivas.length;
    double somaDiferencasQuadrado = vivas.map((a) => pow(a.cap - mediaCap, 2)).reduce((a, b) => a + b).toDouble();
    double desvioPadraoCap = sqrt(somaDiferencasQuadrado / (vivas.length - 1));

    for (final arvore in vivas) {
      if ((arvore.cap - mediaCap).abs() > 3 * desvioPadraoCap) {
        warnings.add("L:${arvore.linha} P:${arvore.posicaoNaLinha}: CAP de ${arvore.cap}cm é um outlier (Média: ${mediaCap.toStringAsFixed(1)}cm).");
      }
      
      final singleRes = validateSingleTree(arvore);
      if (!singleRes.isValid) {
        warnings.addAll(singleRes.warnings.map((w) => "L:${arvore.linha} P:${arvore.posicaoNaLinha}: $w"));
      }
    }
    return ValidationResult(isValid: warnings.isEmpty, warnings: warnings);
  }

  ValidationResult validateSingleTree(Arvore arvore) {
    final List<String> warnings = [];
    
    if (arvore.codigo == Codigo.Normal && arvore.codigo2 != null) {
      warnings.add("Árvore 'Normal' com código secundário (${arvore.codigo2!.name}).");
    }

    if (arvore.codigo != Codigo.Falha && arvore.codigo != Codigo.Caida) {
      if (arvore.cap <= 3.0) warnings.add("CAP (${arvore.cap} cm) muito baixo.");
      if (arvore.cap > 450.0) warnings.add("CAP (${arvore.cap} cm) improvável. Verifique digitação.");
    }

    if (arvore.altura != null && arvore.altura! > 70) warnings.add("Altura (${arvore.altura}m) extremamente rara.");

    if (arvore.altura != null && arvore.cap > 150 && arvore.altura! < 8) {
      warnings.add("CAP alto (${arvore.cap}cm) para altura baixa (${arvore.altura}m).");
    }

    if (arvore.altura != null && arvore.alturaDano != null && arvore.altura! > 0 && arvore.alturaDano! >= arvore.altura!) {
      warnings.add("Altura do Dano deve ser menor que a Altura Total.");
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
    int arvoresContadas = 0;

    // Proteção: Processa apenas se tiver dbId
    final parcelasValidas = parcelas.where((p) => p.dbId != null).toList();

    for (final parcela in parcelasValidas) {
      final arvores = await parcelaRepo.getArvoresDaParcela(parcela.dbId!);
      arvoresContadas += arvores.length;
      allIssues.addAll(_checkParcelaStructure(parcela, arvores));
    }
    
    for (final cubagem in cubagens) {
      if (cubagem.id != null) {
        allIssues.addAll(await _checkCubagemIntegrity(cubagem, cubagemRepo));
      }
    }

    return FullValidationReport(
      issues: allIssues,
      parcelasVerificadas: parcelasValidas.length,
      arvoresVerificadas: arvoresContadas,
      cubagensVerificadas: cubagens.length,
    );
  }

  List<ValidationIssue> _checkParcelaStructure(Parcela parcela, List<Arvore> arvores) {
    final List<ValidationIssue> issues = [];
    final idRelatorio = "P${parcela.idParcela} | ${parcela.nomeFazenda} - ${parcela.nomeTalhao}";

    if (arvores.isEmpty) {
       issues.add(ValidationIssue(tipo: 'Parcela Vazia', mensagem: 'Parcela finalizada sem registros.', parcelaId: parcela.dbId, identificador: idRelatorio));
       return issues;
    }

    final primeira = arvores.first;
    if (primeira.linha != 1 || primeira.posicaoNaLinha != 1) {
      issues.add(ValidationIssue(tipo: 'Início de Coleta', mensagem: 'Não inicia na L:1 P:1.', parcelaId: parcela.dbId, arvoreId: primeira.id, identificador: idRelatorio));
    }

    final arvoresPorLinha = groupBy(arvores, (Arvore a) => a.linha);
    final posicoesAgrupadas = groupBy(arvores, (Arvore a) => '${a.linha}-${a.posicaoNaLinha}');

    arvoresPorLinha.forEach((linha, listaArvores) {
      listaArvores.sort((a, b) => a.posicaoNaLinha.compareTo(b.posicaoNaLinha));

      for (int i = 0; i < listaArvores.length - 1; i++) {
        final atual = listaArvores[i];
        final proxima = listaArvores[i+1];
        if (proxima.posicaoNaLinha != atual.posicaoNaLinha && proxima.posicaoNaLinha != atual.posicaoNaLinha + 1) {
          issues.add(ValidationIssue(tipo: 'Sequência', mensagem: 'Salto de posição na Linha $linha.', parcelaId: parcela.dbId, arvoreId: atual.id, identificador: idRelatorio));
        }
      }
      
      if (listaArvores.isNotEmpty && !listaArvores.last.fimDeLinha) {
        issues.add(ValidationIssue(tipo: 'Fim de Linha', mensagem: 'Última árvore da linha não marcada.', parcelaId: parcela.dbId, arvoreId: listaArvores.last.id, identificador: idRelatorio));
      }
    });

    posicoesAgrupadas.forEach((pos, fustes) {
      if (fustes.length > 1) {
        if (!fustes.any((a) => a.codigo == Codigo.Multipla)) {
          issues.add(ValidationIssue(tipo: 'Duplicata', mensagem: 'Cova duplicada sem código Múltipla.', parcelaId: parcela.dbId, arvoreId: fustes.first.id, identificador: idRelatorio));
        }
      } else if (fustes.first.codigo == Codigo.Multipla) {
         issues.add(ValidationIssue(tipo: 'Código', mensagem: 'Marcada como Múltipla mas só tem 1 fuste.', parcelaId: parcela.dbId, arvoreId: fustes.first.id, identificador: idRelatorio));
      }
    });

    for (final arvore in arvores) {
      final res = validateSingleTree(arvore);
      if (!res.isValid) {
        issues.add(ValidationIssue(tipo: 'Inconsistência', mensagem: res.warnings.join(" "), parcelaId: parcela.dbId, arvoreId: arvore.id, identificador: idRelatorio));
      }
    }

    return issues;
  }

  Future<List<ValidationIssue>> _checkCubagemIntegrity(CubagemArvore cubagem, CubagemRepository cubagemRepo) async {
    final List<ValidationIssue> issues = [];
    final idRelatorio = "CUB: ${cubagem.identificador} (${cubagem.nomeTalhao})";
    
    final secoes = await cubagemRepo.getSecoesPorArvoreId(cubagem.id!);
    if (secoes.length < 2 && cubagem.alturaTotal > 0) {
       issues.add(ValidationIssue(tipo: 'Incompleta', mensagem: 'Menos de 2 seções medidas.', cubagemId: cubagem.id, identificador: idRelatorio));
    }

    if (secoes.length >= 2) {
      secoes.sort((a, b) => a.alturaMedicao.compareTo(b.alturaMedicao));
      for (int i = 1; i < secoes.length; i++) {
        if (secoes[i].diametroSemCasca > secoes[i-1].diametroSemCasca) {
          issues.add(ValidationIssue(tipo: 'Afilamento', mensagem: 'Diâmetro aumenta na altura ${secoes[i].alturaMedicao}m.', cubagemId: cubagem.id, identificador: idRelatorio));
        }
      }
    }
    return issues;
  }
}
// lib/services/validation_service.dart (LÓGICA CORRIGIDA)

import 'dart:math';
import 'package:geoforestv1/models/arvore_model.dart';

class ValidationResult {
  final bool isValid;
  final List<String> warnings;
  ValidationResult({this.isValid = true, this.warnings = const []});
}

class ValidationService {
  ValidationResult validateSingleTree(Arvore arvore) {
    final List<String> warnings = [];

    // Não valida CAP para 'falha' ou 'caida', pois é esperado que seja 0.
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

  ValidationResult validateParcela(List<Arvore> arvores) {
    final arvoresValidasParaAnalise = arvores
        .where((a) => a.codigo != Codigo.Falha && a.codigo != Codigo.Caida)
        .toList();

    if (arvoresValidasParaAnalise.length < 10) return ValidationResult();
    
    final List<String> warnings = [];

    double somaCap = arvoresValidasParaAnalise.map((a) => a.cap).reduce((a, b) => a + b);
    double mediaCap = somaCap / arvoresValidasParaAnalise.length;
    
    double somaDiferencasQuadrado = arvoresValidasParaAnalise.map((a) => pow(a.cap - mediaCap, 2)).reduce((a, b) => a + b).toDouble();
    
    if (arvoresValidasParaAnalise.length <= 1) return ValidationResult(); // Evita divisão por zero
    
    double desvioPadraoCap = sqrt(somaDiferencasQuadrado / (arvoresValidasParaAnalise.length - 1));
    
    for (final arvore in arvoresValidasParaAnalise) {
      if ((arvore.cap - mediaCap).abs() > 2.5 * desvioPadraoCap) {
        warnings.add("Árvore Linha ${arvore.linha}/Pos ${arvore.posicaoNaLinha}: O CAP de ${arvore.cap}cm é um outlier estatístico (média: ${mediaCap.toStringAsFixed(1)}cm).");
      }
    }
    
    return ValidationResult(isValid: warnings.isEmpty, warnings: warnings);
  }
}
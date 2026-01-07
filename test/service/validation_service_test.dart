// test/services/validation_service_test.dart (VERSÃO CORRIGIDA - SEM ENUMS)

import 'package:flutter_test/flutter_test.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/services/validation_service.dart';

void main() {
  
  group('ValidationService - validateSingleTree', () {
    
    final validationService = ValidationService();

    test('deve retornar válido para uma árvore com dados normais', () {
      final arvoreNormal = Arvore(
        cap: 45.5,
        altura: 28.0,
        linha: 1,
        posicaoNaLinha: 1,
        codigo: '101', // ID do Excel para 'Normal'
      );

      final result = validationService.validateSingleTree(arvoreNormal);

      expect(result.isValid, isTrue);
      expect(result.warnings, isEmpty);
    });

    test('deve retornar inválido e um aviso para CAP muito baixo', () {
      final arvoreCapBaixo = Arvore(
        cap: 2.0, // Valor abaixo do limite de 3.0
        altura: 25.0,
        linha: 1,
        posicaoNaLinha: 2,
        codigo: '101',
      );

      final result = validationService.validateSingleTree(arvoreCapBaixo);

      expect(result.isValid, isFalse);
      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first, contains('muito baixo'));
    });

    test('deve retornar inválido e um aviso para CAP muito alto', () {
      final arvoreCapAlto = Arvore(
        cap: 500.0, // Valor acima do limite de 450.0
        altura: 30.0,
        linha: 2,
        posicaoNaLinha: 1,
        codigo: '101',
      );

      final result = validationService.validateSingleTree(arvoreCapAlto);

      expect(result.isValid, isFalse);
      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first, contains('improvável'));
    });

    test('deve retornar inválido e um aviso para Altura muito alta', () {
      final arvoreAlturaAlta = Arvore(
        cap: 120.0,
        altura: 80.0, // Acima do limite de 70m
        linha: 3,
        posicaoNaLinha: 5,
        codigo: '101',
      );

      final result = validationService.validateSingleTree(arvoreAlturaAlta);

      expect(result.isValid, isFalse);
      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first, contains('extremamente rara'));
    });
    
    test('deve retornar inválido para relação CAP/Altura incomum', () {
      final arvoreIncomum = Arvore(
        cap: 160.0, 
        altura: 5.0, // CAP muito alto para altura muito baixa
        linha: 4,
        posicaoNaLinha: 1,
        codigo: '101',
      );

      final result = validationService.validateSingleTree(arvoreIncomum);

      expect(result.isValid, isFalse);
      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first, contains('CAP alto para altura baixa'));
    });

    test('deve retornar válido para código Falha com CAP 0', () {
      // 107 = ID do Excel para 'Falha'
      final arvoreFalha = Arvore(
        cap: 0.0,
        linha: 5,
        posicaoNaLinha: 1,
        codigo: '107', 
      );

      final result = validationService.validateSingleTree(arvoreFalha);

      expect(result.isValid, isTrue);
      expect(result.warnings, isEmpty);
    });
  });
}
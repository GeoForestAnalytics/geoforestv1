// test/services/validation_service_test.dart

// 1. Importa a biblioteca de testes do Flutter.
import 'package:flutter_test/flutter_test.dart';

// 2. Importa as classes que vamos testar.
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/services/validation_service.dart';

// A função 'main' é o ponto de entrada para os testes neste arquivo.
void main() {
  
  // 'group' agrupa testes relacionados. Facilita a leitura dos resultados.
  group('ValidationService - validateSingleTree', () {
    
    // Instancia o serviço que queremos testar.
    final validationService = ValidationService();

    // 'test' define um caso de teste individual.
    test('deve retornar válido para uma árvore com dados normais', () {
      // ARRANGE: Preparamos os dados de entrada.
      final arvoreNormal = Arvore(
        cap: 45.5,
        altura: 28.0,
        linha: 1,
        posicaoNaLinha: 1,
        codigo: Codigo.Normal,
      );

      // ACT: Executamos o método que queremos testar.
      final result = validationService.validateSingleTree(arvoreNormal);

      // ASSERT: Verificamos se o resultado é o esperado.
      // 'expect' é a função que faz a verificação.
      expect(result.isValid, isTrue);
      expect(result.warnings, isEmpty);
    });

    test('deve retornar inválido e um aviso para CAP muito baixo', () {
      // ARRANGE
      final arvoreCapBaixo = Arvore(
        cap: 4.0, // <-- Valor problemático
        altura: 25.0,
        linha: 1,
        posicaoNaLinha: 2,
        codigo: Codigo.Normal,
      );

      // ACT
      final result = validationService.validateSingleTree(arvoreCapBaixo);

      // ASSERT
      expect(result.isValid, isFalse);
      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first, contains('CAP de 4.0 cm é muito baixo'));
    });

    test('deve retornar inválido e um aviso para CAP muito alto', () {
      // ARRANGE
      final arvoreCapAlto = Arvore(
        cap: 500.0, // <-- Valor problemático
        altura: 30.0,
        linha: 2,
        posicaoNaLinha: 1,
        codigo: Codigo.Normal,
      );

      // ACT
      final result = validationService.validateSingleTree(arvoreCapAlto);

      // ASSERT
      expect(result.isValid, isFalse);
      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first, contains('CAP de 500.0 cm é fisicamente improvável'));
    });

    test('deve retornar inválido e um aviso para Altura muito alta', () {
      // ARRANGE
      final arvoreAlturaAlta = Arvore(
        cap: 120.0,
        altura: 80.0, // <-- Valor problemático
        linha: 3,
        posicaoNaLinha: 5,
        codigo: Codigo.Normal,
      );

      // ACT
      final result = validationService.validateSingleTree(arvoreAlturaAlta);

      // ASSERT
      expect(result.isValid, isFalse);
      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first, contains('Altura de 80.0m é extremamente rara'));
    });
    
    test('deve retornar inválido para relação CAP/Altura incomum', () {
      // ARRANGE
      final arvoreIncomum = Arvore(
        cap: 160.0, // <-- CAP alto
        altura: 8.0, // <-- Altura baixa
        linha: 4,
        posicaoNaLinha: 1,
        codigo: Codigo.Normal,
      );

      // ACT
      final result = validationService.validateSingleTree(arvoreIncomum);

      // ASSERT
      expect(result.isValid, isFalse);
      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first, contains('Relação CAP/Altura incomum'));
    });

    test('deve retornar válido para código Falha com CAP 0', () {
      // ARRANGE: Para 'Falha', CAP 0 é o esperado e não deve gerar aviso.
      final arvoreFalha = Arvore(
        cap: 0.0,
        linha: 5,
        posicaoNaLinha: 1,
        codigo: Codigo.Falha,
      );

      // ACT
      final result = validationService.validateSingleTree(arvoreFalha);

      // ASSERT
      expect(result.isValid, isTrue);
      expect(result.warnings, isEmpty);
    });
  });
}
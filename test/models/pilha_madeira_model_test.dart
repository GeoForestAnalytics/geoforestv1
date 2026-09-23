// Testa o cálculo de volume de pilha de madeira (lib/models/pilha_madeira_model.dart):
// cunha inicial + trapézios centrais + cunha final, igual descrito no comentário
// original do código.

import 'package:flutter_test/flutter_test.dart';
import 'package:geoforestv1/models/pilha_madeira_model.dart';

void main() {
  group('PilhaMadeira.calcularVolumeBruto', () {
    test('retorna 0 sem seções medidas', () {
      final pilha = PilhaMadeira(
        numeroPilha: 1,
        sortimento: 'Teste',
        comprimentoTora: 1.0,
        comprimentoPilha: 3.0,
        secoes: const [],
      );
      expect(pilha.calcularVolumeBruto(), 0.0);
    });

    test('cunha inicial + trapézios + cunha final, com tora de 1m', () {
      // Pilha de 3m, 3 seções medidas em 0.5/1.5/2.5m com alturas 1.0/2.0/1.0m.
      // Cunha inicial (0 -> 0.5m): (1.0/2) * 0.5 * 1 = 0.25
      // Trapézio 1 (0.5 -> 1.5m):  ((1.0+2.0)/2) * 1.0 * 1 = 1.5
      // Trapézio 2 (1.5 -> 2.5m):  ((2.0+1.0)/2) * 1.0 * 1 = 1.5
      // Cunha final (2.5 -> 3.0m): (1.0/2) * 0.5 * 1 = 0.25
      // Total esperado: 3.5 m³ (estéreo)
      final pilha = PilhaMadeira(
        numeroPilha: 1,
        sortimento: 'Teste',
        comprimentoTora: 1.0,
        comprimentoPilha: 3.0,
        secoes: [
          SecaoPilha(posicao: 1, distanciaMetros: 0.5, altura: 1.0),
          SecaoPilha(posicao: 2, distanciaMetros: 1.5, altura: 2.0),
          SecaoPilha(posicao: 3, distanciaMetros: 2.5, altura: 1.0),
        ],
      );

      expect(pilha.calcularVolumeBruto(), closeTo(3.5, 0.0001));
    });

    test('multiplica pelo comprimento real da tora quando informado', () {
      final base = PilhaMadeira(
        numeroPilha: 1,
        sortimento: 'Teste',
        comprimentoTora: 1.0,
        comprimentoPilha: 3.0,
        secoes: [
          SecaoPilha(posicao: 1, distanciaMetros: 0.5, altura: 1.0),
          SecaoPilha(posicao: 2, distanciaMetros: 1.5, altura: 2.0),
          SecaoPilha(posicao: 3, distanciaMetros: 2.5, altura: 1.0),
        ],
      );
      final comToraReal = PilhaMadeira(
        numeroPilha: 1,
        sortimento: 'Teste',
        comprimentoTora: 1.0,
        comprimentoToraReal: 2.0, // dobro do padrão da OS
        comprimentoPilha: 3.0,
        secoes: [
          SecaoPilha(posicao: 1, distanciaMetros: 0.5, altura: 1.0),
          SecaoPilha(posicao: 2, distanciaMetros: 1.5, altura: 2.0),
          SecaoPilha(posicao: 3, distanciaMetros: 2.5, altura: 1.0),
        ],
      );

      // Volume deve dobrar junto com o comprimento real da tora.
      expect(comToraReal.calcularVolumeBruto(), closeTo(base.calcularVolumeBruto() * 2, 0.0001));
    });
  });

  group('PilhaMadeira.calcularVolumesolido', () {
    test('aplica o fator de empilhamento sobre o volume estéreo', () {
      final pilha = PilhaMadeira(
        numeroPilha: 1,
        sortimento: 'Teste',
        comprimentoTora: 1.0,
        comprimentoPilha: 3.0,
        fatorEmpilhamento: 0.65,
        secoes: [
          SecaoPilha(posicao: 1, distanciaMetros: 0.5, altura: 1.0),
          SecaoPilha(posicao: 2, distanciaMetros: 1.5, altura: 2.0),
          SecaoPilha(posicao: 3, distanciaMetros: 2.5, altura: 1.0),
        ],
      );

      // 3.5 m³ estéreo * 0.65 = 2.275 m³ sólido
      expect(pilha.calcularVolumesolido(), closeTo(2.275, 0.0001));
    });
  });

  group('PilhaMadeira.calcularAlturaMedia', () {
    test('retorna 0 sem seções', () {
      final pilha = PilhaMadeira(
        numeroPilha: 1,
        sortimento: 'Teste',
        comprimentoTora: 1.0,
        comprimentoPilha: 3.0,
        secoes: const [],
      );
      expect(pilha.calcularAlturaMedia(), 0.0);
    });

    test('calcula a média simples das alturas medidas', () {
      final pilha = PilhaMadeira(
        numeroPilha: 1,
        sortimento: 'Teste',
        comprimentoTora: 1.0,
        comprimentoPilha: 3.0,
        secoes: [
          SecaoPilha(posicao: 1, distanciaMetros: 0.5, altura: 1.0),
          SecaoPilha(posicao: 2, distanciaMetros: 1.5, altura: 2.0),
          SecaoPilha(posicao: 3, distanciaMetros: 2.5, altura: 3.0),
        ],
      );
      expect(pilha.calcularAlturaMedia(), closeTo(2.0, 0.0001));
    });
  });
}

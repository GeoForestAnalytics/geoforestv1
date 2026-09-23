// Testa o cálculo de volume comercial pela fórmula de Smalian
// (lib/services/analysis_service.dart), usada na cubagem rigorosa de árvores.

import 'package:flutter_test/flutter_test.dart';
import 'package:geoforestv1/services/analysis_service.dart';
import 'package:geoforestv1/models/cubagem_secao_model.dart';

void main() {
  final service = AnalysisService();

  group('calcularVolumeComercialSmalian', () {
    test('retorna 0 com menos de 2 seções (não dá pra formar tora nenhuma)', () {
      expect(service.calcularVolumeComercialSmalian([]), 0.0);
      expect(
        service.calcularVolumeComercialSmalian([CubagemSecao(alturaMedicao: 0)]),
        0.0,
      );
    });

    test('calcula o volume de uma tora única entre duas seções', () {
      // Seção 1 (base, 0m): diâmetro sem casca 20cm -> circunferência = 20*pi
      // Seção 2 (4m): diâmetro sem casca 10cm -> circunferência = 10*pi
      // Sem casca (casca1_mm = casca2_mm = 0), pra diametroSemCasca bater exato.
      final secoes = [
        CubagemSecao(alturaMedicao: 0, circunferencia: 20 * 3.14159265358979),
        CubagemSecao(alturaMedicao: 4, circunferencia: 10 * 3.14159265358979),
      ];

      // Smalian: V = ((A1 + A2) / 2) * L
      // A1 = pi*(0.20)^2/4 = 0.0314159...  A2 = pi*(0.10)^2/4 = 0.00785398...
      // V = ((0.0314159 + 0.00785398) / 2) * 4 = 0.07853982 m³
      final volume = service.calcularVolumeComercialSmalian(secoes);
      expect(volume, closeTo(0.07853982, 0.0001));
    });

    test('soma o volume de várias toras (múltiplas seções empilhadas)', () {
      // Cilindro perfeito de 10cm de diâmetro sem casca, em 3 seções de 1m cada
      // (0m, 1m, 2m) -> cada tora é um cilindro de área constante.
      const circunferenciaCm = 10 * 3.14159265358979;
      final secoes = [
        CubagemSecao(alturaMedicao: 0, circunferencia: circunferenciaCm),
        CubagemSecao(alturaMedicao: 1, circunferencia: circunferenciaCm),
        CubagemSecao(alturaMedicao: 2, circunferencia: circunferenciaCm),
      ];

      // Área constante = pi*(0.10)^2/4 = 0.00785398 m² ; volume por tora = área * 1m
      // 2 toras (0->1 e 1->2) -> volume total = 2 * 0.00785398
      final volume = service.calcularVolumeComercialSmalian(secoes);
      expect(volume, closeTo(2 * 0.00785398, 0.0001));
    });

    test('desconta a espessura da casca do diâmetro', () {
      // Mesma circunferência das seções acima, mas agora com 10mm de casca de
      // cada lado (1cm) -> diâmetro sem casca cai 2cm em relação ao com casca.
      final comCasca = CubagemSecao(alturaMedicao: 0, circunferencia: 20 * 3.14159265358979);
      final semCasca = CubagemSecao(
        alturaMedicao: 0,
        circunferencia: 20 * 3.14159265358979,
        casca1_mm: 10,
        casca2_mm: 10,
      );
      expect(semCasca.diametroSemCasca, closeTo(comCasca.diametroSemCasca - 2.0, 0.0001));
    });

    test('não depende da ordem em que as seções são passadas (reordena por altura)', () {
      final secoesEmOrdem = [
        CubagemSecao(alturaMedicao: 0, circunferencia: 20 * 3.14159265358979),
        CubagemSecao(alturaMedicao: 4, circunferencia: 10 * 3.14159265358979),
      ];
      final secoesInvertidas = secoesEmOrdem.reversed.toList();

      expect(
        service.calcularVolumeComercialSmalian(secoesInvertidas),
        closeTo(service.calcularVolumeComercialSmalian(secoesEmOrdem), 0.0001),
      );
    });
  });
}

// Testa a conversão WGS84 -> UTM (lib/utils/utm_converter.dart).
//
// Guarda especificamente contra a classe de bug encontrada em 2026-09: o
// registro de projeção no proj4dart falhando silenciosamente (Projection.get()
// retorna null em vez de lançar exceção, então um try/catch em volta dele
// nunca funciona pra registrar a projeção). Ver histórico do main.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:geoforestv1/utils/utm_converter.dart';

void main() {
  group('converterParaUtm', () {
    test('retorna "UTM N/A" quando não há coordenada', () {
      expect(converterParaUtm(latitude: null, longitude: null), 'UTM N/A');
      expect(converterParaUtm(latitude: -23.5, longitude: null), 'UTM N/A');
      expect(converterParaUtm(latitude: null, longitude: -46.6), 'UTM N/A');
    });

    test('converte uma coordenada real (região de Itararé/SP) pra UTM Zona 22S', () {
      // Ponto usado nos testes reais em campo desta sessão.
      final resultado = converterParaUtm(
        latitude: -24.1147,
        longitude: -49.3305,
      );

      expect(resultado, isNot('UTM N/A'));
      expect(resultado, contains('Zona 22S'));
      expect(resultado, matches(RegExp(r'^E:\d+ N:\d+ ')));

      // Confere a ordem de grandeza esperada pra zona 22S (evita, por exemplo,
      // confundir X com Y ou latitude com longitude).
      final easting = int.parse(RegExp(r'E:(\d+)').firstMatch(resultado)!.group(1)!);
      final northing = int.parse(RegExp(r'N:(\d+)').firstMatch(resultado)!.group(1)!);
      expect(easting, inInclusiveRange(166000, 833000)); // faixa válida de Easting UTM
      expect(northing, greaterThan(7000000)); // hemisfério sul, latitude ~-24°
    });

    test('nunca usa "|" no resultado (quebraria o parser do EXIF)', () {
      final resultado = converterParaUtm(latitude: -24.1147, longitude: -49.3305);
      expect(resultado.contains('|'), isFalse);
    });

    test('registrar a projeção duas vezes seguidas não quebra (idempotente)', () {
      // Chamar em sequência simula duas árvores seguidas no mesmo app rodando —
      // é exatamente o cenário que expôs o bug original de registro.
      final r1 = converterParaUtm(latitude: -24.1147, longitude: -49.3305);
      final r2 = converterParaUtm(latitude: -24.1150, longitude: -49.3310);
      expect(r1, isNot('UTM N/A'));
      expect(r2, isNot('UTM N/A'));
    });

    test('usa a zona informada, não sempre a padrão', () {
      final resultado = converterParaUtm(
        latitude: -24.1147,
        longitude: -49.3305,
        nomeZona: 'SIRGAS 2000 / UTM Zona 21S',
      );
      expect(resultado, contains('Zona 21S'));
    });
  });
}

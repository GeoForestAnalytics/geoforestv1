import 'dart:async';
import 'dart:convert';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:geoforestv1/data/repositories/especie_repository.dart';
import 'package:geoforestv1/utils/app_config.dart';

/// Uma sugestão de espécie devolvida pelo Pl@ntNet, já cruzada com a base
/// interna de espécies (quando existe correspondência) pra mostrar o nome
/// comum em português em vez do nome científico/inglês cru da API.
class SugestaoEspecie {
  final String nomeCientifico;
  final String? nomeComumLocal;
  final List<String> nomesComunsPlantNet;
  final double confianca; // 0.0 a 1.0

  SugestaoEspecie({
    required this.nomeCientifico,
    required this.nomeComumLocal,
    required this.nomesComunsPlantNet,
    required this.confianca,
  });

  /// O que mostrar pro usuário: nome comum da base interna se existir,
  /// senão o primeiro nome comum do Pl@ntNet, senão o nome científico.
  String get nomeExibicao {
    if (nomeComumLocal != null && nomeComumLocal!.isNotEmpty) return nomeComumLocal!;
    if (nomesComunsPlantNet.isNotEmpty) return nomesComunsPlantNet.first;
    return nomeCientifico;
  }
}

/// Identificação de espécie por foto via Pl@ntNet (my-api.plantnet.org) —
/// substitui o Gemini/Vertex AI nesse papel: é um modelo treinado
/// especificamente pra identificação botânica, não um LLM generalista, e
/// tem cota diária gratuita (500 identificações/dia no plano usado aqui).
class PlantNetService {
  final _especieRepository = EspecieRepository();

  static const _baseUrl = 'https://my-api.plantnet.org/v2/identify/all';

  /// Identifica uma árvore a partir de 1 a 5 fotos DA MESMA árvore (ângulos
  /// diferentes — casca, folha, flor — melhoram a precisão). O Pl@ntNet
  /// conta isso como UMA identificação na cota diária, não uma por foto.
  ///
  /// Nunca lança exceção pro chamador. Retorna um registro
  /// `(sugestoes, erro)`: `erro` só vem preenchido quando algo IMPEDIU a
  /// consulta de rodar (chave ausente, rede, timeout, HTTP não-200) — pra
  /// isso poder virar um aviso visível na tela, em vez de simplesmente não
  /// acontecer nada e parecer que o botão não funcionou. Uma consulta que
  /// rodou normal mas não achou nada com confiança volta com `erro: null`
  /// e lista vazia.
  Future<(List<SugestaoEspecie> sugestoes, String? erro)> identificarPorFotos(
    List<String> caminhosFotos, {
    int maxResultados = 5,
  }) async {
    if (caminhosFotos.isEmpty) return (<SugestaoEspecie>[], null);
    if (AppConfig.plantNetApiKey.isEmpty) {
      debugPrint('PlantNetService: PLANTNET_API_KEY não configurada — pulando identificação.');
      return (<SugestaoEspecie>[], 'Identificação por foto não configurada neste aplicativo (chave de API ausente).');
    }

    try {
      // A API aceita no máximo 5 imagens por identificação.
      final fotos = caminhosFotos.take(5).toList();

      final uri = Uri.parse('$_baseUrl?api-key=${AppConfig.plantNetApiKey}&lang=pt');
      final request = http.MultipartRequest('POST', uri);
      for (final caminho in fotos) {
        request.files.add(await http.MultipartFile.fromPath('images', caminho));
        // A API exige um "organs" por imagem (images[] e organs[] precisam
        // ter o mesmo tamanho) — `request.fields` só aceita 1 valor por
        // chave, então usamos `files` (via fromString) pra poder repetir o
        // campo "organs" uma vez por foto, como um campo de texto comum.
        request.files.add(http.MultipartFile.fromString('organs', 'auto'));
      }

      final streamedResponse = await request.send().timeout(const Duration(seconds: 25));
      final body = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 429) {
        return (<SugestaoEspecie>[], 'Limite diário de identificações do Pl@ntNet atingido (500/dia). Volta amanhã ou preenche manualmente.');
      }
      if (streamedResponse.statusCode != 200) {
        debugPrint('PlantNetService: erro HTTP ${streamedResponse.statusCode}: $body');
        return (<SugestaoEspecie>[], 'Falha ao identificar (erro ${streamedResponse.statusCode}). Tenta de novo — se persistir, avisa o suporte.');
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      final resultadosBrutos = (json['results'] as List?) ?? [];

      final sugestoes = <SugestaoEspecie>[];
      for (final item in resultadosBrutos.take(maxResultados)) {
        final especie = item['species'] as Map<String, dynamic>?;
        if (especie == null) continue;

        final nomeCientifico = especie['scientificNameWithoutAuthor'] as String? ?? '';
        if (nomeCientifico.isEmpty) continue;

        final nomesComuns = (especie['commonNames'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];

        final local = await _especieRepository.buscarPorNomeCientifico(nomeCientifico);

        sugestoes.add(SugestaoEspecie(
          nomeCientifico: nomeCientifico,
          nomeComumLocal: local?.nomeComum,
          nomesComunsPlantNet: nomesComuns,
          confianca: (item['score'] as num?)?.toDouble() ?? 0,
        ));
      }
      return (sugestoes, null);
    } catch (e, stack) {
      debugPrint('Erro ao identificar espécie via Pl@ntNet: $e');
      unawaited(FirebaseCrashlytics.instance.recordError(
        e,
        stack,
        reason: 'PlantNetService.identificarPorFotos falhou',
        fatal: false,
      ));
      final mensagem = e is TimeoutException
          ? 'A identificação demorou demais (sem internet?). Tenta de novo.'
          : 'Não foi possível identificar a espécie agora. Tenta de novo ou preenche manualmente.';
      return (<SugestaoEspecie>[], mensagem);
    }
  }
}

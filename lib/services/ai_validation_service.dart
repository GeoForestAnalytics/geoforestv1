import 'dart:convert';
import 'package:firebase_vertexai/firebase_vertexai.dart'; 
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';

class AiValidationService {
  late final GenerativeModel _model;

  AiValidationService() {
    _model = FirebaseVertexAI.instance.generativeModel(
      model: 'gemini-2.0-flash', 
    );
  }

  /// 1. MÉTODO PARA CHAT INTERATIVO (Texto Humano)
  Future<String> perguntarSobreDados(String perguntaUsuario, Parcela parcela, List<Arvore> arvores) async {
    final dadosContexto = _prepararDados(parcela, arvores);

    final prompt = [
      Content.text('''
        Você é o "GeoForest AI", especialista em biometria florestal. 
        Analise os dados desta parcela e responda à pergunta do usuário.

        DADOS DA PARCELA:
        ${jsonEncode(dadosContexto)}

        PERGUNTA DO USUÁRIO: "$perguntaUsuario"

        REGRAS:
        1. Responda em PORTUGUÊS (Brasil).
        2. Seja breve e técnico.
        3. NÃO responda com JSON. Use texto natural.
      ''')
    ];

    try {
      final response = await _model.generateContent(prompt);
      return response.text ?? "Não foi possível gerar uma resposta.";
    } catch (e) {
      return "Erro na análise: $e";
    }
  }

  /// 2. MÉTODO PARA AUDITORIA AUTOMÁTICA (Ajustado para ignorar altura zero em Normais)
  Future<List<Map<String, dynamic>>> validarErrosAutomatico(Parcela parcela, List<Arvore> arvores) async {
    final jsonModel = FirebaseVertexAI.instance.generativeModel(
      model: 'gemini-2.0-flash',
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
    );

    final dadosContexto = _prepararDados(parcela, arvores);

    final prompt = [
      Content.text('''
        Atue como um auditor de inventário florestal. Analise o JSON e retorne erros de consistência.

        ⚠️ REGRA IMPORTANTE SOBRE ALTURA:
        - Em inventários florestais, NEM TODAS as árvores têm a altura medida. 
        - Se a altura ('h') for igual a 0 ou nula em árvores com código 'Normal', 'Bifurcada' ou 'Multipla', **NÃO CONSIDERE ERRO**. Ignore e não mencione.
        - Trate a altura 0 apenas como "árvore não selecionada para medição de altura".

        O QUE REALMENTE SÃO ERROS:
        1. CAP muito alto com altura muito baixa (ex: CAP 100cm e Altura 2m).
        2. Árvores marcadas como 'Falha' mas que possuem CAP maior que zero.
        3. Pulos na sequência de posições dentro da mesma linha.
        4. CAP ou Altura com valores fisicamente impossíveis (ex: Altura 100m, CAP 500cm).

        DADOS:
        ${jsonEncode(dadosContexto)}

        Retorne EXATAMENTE este formato JSON:
        {
          "erros": [
            {"id": 123, "msg": "Descrição do erro real aqui"}
          ]
        }
        Se encontrar apenas árvores normais com altura 0, retorne a lista "erros" vazia.
      ''')
    ];

    try {
      final response = await jsonModel.generateContent(prompt);
      final responseText = response.text ?? '{"erros": []}';
      final decoded = jsonDecode(responseText);
      return List<Map<String, dynamic>>.from(decoded['erros'] ?? []);
    } catch (e) {
      print("Erro na validação automática: $e");
      return [];
    }
  }

  /// Função privada otimizada para tokens (agora incluindo ID)
  Map<String, dynamic> _prepararDados(Parcela parcela, List<Arvore> arvores) {
    final listaLimitada = arvores.length > 300 ? arvores.take(300).toList() : arvores;

    return {
      "talhao": parcela.nomeTalhao,
      "area": parcela.areaMetrosQuadrados,
      "total": arvores.length,
      "arvores": listaLimitada.map((a) => {
        "id": a.id, // <--- ID ADICIONADO PARA O PULO DIRETO
        "l": a.linha, 
        "p": a.posicaoNaLinha, 
        "c": a.cap, 
        "h": a.altura ?? 0, 
        "cod": a.codigo.name
      }).toList()
    };
  }
}
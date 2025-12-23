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

  /// 1. MÉTODO PARA O CHAT (Conversa sobre os dados)
  Future<String> perguntarSobreDados(String pergunta, Parcela parcela, List<Arvore> arvores) async {
    final resumo = _prepararResumoPlot(parcela, arvores);
    final prompt = [
      Content.text('''
        Você é o especialista GeoForest AI. Analise os dados e responda: "$pergunta"
        DADOS: ${jsonEncode(resumo)}
        Regra: Altura 0 é normal (amostragem). Responda em Português técnico e direto.
      ''')
    ];
    try {
      final response = await _model.generateContent(prompt);
      return response.text ?? "Sem resposta.";
    } catch (e) { return "Erro no chat: $e"; }
  }

  /// 2. MÉTODO PARA AUDITORIA INDIVIDUAL (Erros de digitação e lógica local)
  Future<List<Map<String, dynamic>>> validarErrosAutomatico(Parcela parcela, List<Arvore> arvores, {double? idade}) async {
    final jsonModel = FirebaseVertexAI.instance.generativeModel(
      model: 'gemini-2.0-flash',
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
    );

    final resumo = _prepararResumoPlot(parcela, arvores, idade: idade);
    final prompt = [
      Content.text('''
        Atue como Auditor de Controle de Qualidade (QC). Analise o JSON em busca de:
        1. ERROS DE DIGITAÇÃO: CAPs que fogem da escala (ex: 150 em vez de 15.0).
        2. ERROS DE LÓGICA: Pulos na sequência de árvores (ex: posição 1, 2, 4).
        3. INCONSISTÊNCIA: Código 'Falha' com medida > 0.
        4. REGRA: Altura 0 é normal. NÃO mencione como erro.

        DADOS: ${jsonEncode(resumo)}
        Retorne: { "erros": [ {"id": 123, "msg": "texto"} ] }
      ''')
    ];

    try {
      final response = await jsonModel.generateContent(prompt);
      final decoded = jsonDecode(response.text ?? '{"erros": []}');
      return List<Map<String, dynamic>>.from(decoded['erros'] ?? []);
    } catch (e) { return []; }
  }

  /// 3. MÉTODO PARA ESTRATO (O que estava faltando e causava o erro)
  /// Atua como analista de operações e performance.
  Future<List<String>> validarEstrato(List<Map<String, dynamic>> resumos) async {
     final jsonModel = FirebaseVertexAI.instance.generativeModel(
      model: 'gemini-2.0-flash',
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
    );

    final prompt = [
      Content.text('''
        Você é um Analista de Dados e Auditor de Operações Florestais. 
        Analise o conjunto de talhões (ESTRATO) abaixo para entregar um relatório mastigado para o escritório.

        --- TAREFAS DE ANÁLISE ---
        1. PADRÕES E ERROS: Identifique se algum talhão destoa completamente da média do grupo.
        2. PERFORMANCE: Se o campo 'segundos_por_arvore' for muito baixo (ex: < 10s), aponte como suspeita de coleta rápida demais/estimada.
        3. CONDIÇÃO FLORESTAL: Identifique se o talhão parece ser de 'Rebrota' (baseado em fustes múltiplos) ou se está 'Sujo' (muitas falhas/mortas).
        4. COMPARAÇÃO: Compare talhões de mesma idade e espécies.
        
        REGRAS: 
        - É PROIBIDO reclamar de falta de idade. Se não houver, faça análise comparativa.
        - Seja propositivo. Dê insights de gestão.

        DADOS: ${jsonEncode(resumos)}

        RETORNE APENAS O JSON: { "alertas": ["Insight 1...", "Alerta 2..."] }
      ''')
    ];

    try {
      final response = await jsonModel.generateContent(prompt);
      final decoded = jsonDecode(response.text ?? '{"alertas": []}');
      return List<String>.from(decoded['alertas'] ?? []);
    } catch (e) { 
      return ["Erro ao processar auditoria inteligente."]; 
    }
  }

  /// Auxiliar para formatar dados
  Map<String, dynamic> _prepararResumoPlot(Parcela p, List<Arvore> arvores, {double? idade}) {
    return {
      "t": p.nomeTalhao,
      "idade": idade ?? "N/I",
      "arv": arvores.take(150).map((a) => {
        "l": a.linha, "p": a.posicaoNaLinha, "c": a.cap, "h": a.altura ?? 0, "cod": a.codigo.name
      }).toList()
    };
  }
}
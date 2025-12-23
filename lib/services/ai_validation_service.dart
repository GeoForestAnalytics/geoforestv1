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

  /// 1. MÉTODO PARA O CHAT (Manual Técnico e Suporte ao App)
  Future<String> perguntarSobreDados(String pergunta, Parcela parcela, List<Arvore> arvores) async {
    final resumo = _prepararResumoPlot(parcela, arvores);
    final prompt = [
      Content.text('''
        Você é o GeoForest AI, assistente técnico e de suporte do aplicativo GeoForestv1. 
        
        SUA PERSONA: Especialista em Inventário Florestal, Dendrometria e Operações de Campo.

        CONTEXTO TÉCNICO DO APP (Responda se o usuário perguntar):
        - Hipsometria: Processo de estimar alturas não medidas no campo usando uma amostra real e modelos matemáticos (curva hipsométrica).
        - Regressão de Volume: O app utiliza o modelo de Schumacher-Hall (geralmente) para converter CAP e Altura em Volume (m³).
        - Delegação de Projetos: Permite que um Gerente compartilhe um projeto com uma equipe externa (chave de acesso), garantindo que os dados voltem para o painel do dono do projeto automaticamente.
        - Incremento Médio Anual (IMA): Calculado dividindo o Volume Total pela Idade. Essencial para saber a produtividade.

        REGRAS DE INVENTÁRIO (Contexto para análise):
        - Medimos CAP de todas, Altura de 10% a 15% (árvores amostra). Altura 0.0 em árvores "Normal" é esperado.
        - Múltiplas: Devem obrigatoriamente estar na mesma posição (Linha/Posição) mas com números de fuste diferentes (1, 2, 3...).
        - Falhas/Caídas: São covas sem produção. Devem ter CAP e Altura obrigatoriamente 0.0.
        - Quebradas: Devem possuir o campo 'Altura de Dano' (hd) preenchido para cálculo de perda.

        DADOS DA PARCELA ATUAL: ${jsonEncode(resumo)}

        INSTRUÇÃO: Responda à pergunta "$pergunta" de forma técnica e clara. 
        Se for uma dúvida sobre o app, explique a funcionalidade. 
        Se for sobre os dados, analise conforme as regras acima.
      ''')
    ];
    try {
      final response = await _model.generateContent(prompt);
      return response.text ?? "Sem resposta.";
    } catch (e) { return "Erro no chat: $e"; }
  }

  /// 2. MÉTODO PARA AUDITORIA AUTOMÁTICA (Regras de Negócio Rígidas)
  Future<List<Map<String, dynamic>>> validarErrosAutomatico(Parcela parcela, List<Arvore> arvores, {double? idade}) async {
    final jsonModel = FirebaseVertexAI.instance.generativeModel(
      model: 'gemini-2.0-flash',
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
    );

    final resumo = _prepararResumoPlot(parcela, arvores, idade: idade);
    final prompt = [
      Content.text('''
        Atue como Auditor de Controle de Qualidade (QC) Florestal.
        Analise o JSON e identifique violações das seguintes REGRAS DE NEGÓCIO:

        1. REGRA MÚLTIPLAS: Se o código for "Multipla", verifique se existem outras árvores na mesma Linha (l) e Posição (p). Se houver apenas um registro para aquela posição com código Multipla, é um erro.
        2. REGRA FALHA/CAÍDA: Se o código for "Falha" ou "Caida", o CAP (c) e a Altura (h) DEVEM ser 0.0. Se houver medida, aponte erro.
        3. REGRA QUEBRADA: Se o código for "Quebrada", o campo hd (Altura de Dano) deve ser maior que 0. Se estiver 0, o coletor esqueceu de medir onde a árvore quebrou.
        4. REGRA SEQUÊNCIA: Verifique a coluna "p" (posição). Se a sequência dentro de uma linha "l" pular números (ex: 1,2,3,5), aponte "Salto de sequência na posição".
        5. REGRA OUTROS: Se o código for "Outro", gere um aviso: "O código 'Outro' deve ser avaliado pelo supervisor para correta classificação botânica ou de dano".
        6. REGRA DENDROMÉTRICA: CAP (c) acima de 200cm ou Altura (h) acima de 50m são outliers extremos. Peça confirmação.

        DADOS PARA ANÁLISE:
        ${jsonEncode(resumo)}

        RETORNE APENAS JSON: { "erros": [ {"id": arvore_id, "msg": "explicação curta"} ] }
      ''')
    ];

    try {
      final response = await jsonModel.generateContent(prompt);
      final decoded = jsonDecode(response.text ?? '{"erros": []}');
      return List<Map<String, dynamic>>.from(decoded['erros'] ?? []);
    } catch (e) { return []; }
  }

  /// 3. MÉTODO PARA ESTRATO (Consolidado)
  Future<List<String>> validarEstrato(List<Map<String, dynamic>> resumos) async {
     final jsonModel = FirebaseVertexAI.instance.generativeModel(
      model: 'gemini-2.0-flash',
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
    );

    final prompt = [
      Content.text('''
        Analise o conjunto de talhões abaixo (Estrato Florestal).
        DADOS: ${jsonEncode(resumos)}

        FOCO DA ANÁLISE:
        - Produtividade (IMA): Volume / Idade.
        - Homogeneidade: Talhões com a mesma idade devem ter volumes próximos.
        - Qualidade: Identifique se algum talhão tem alta taxa de falhas ou mortalidade.

        RETORNE APENAS JSON: { "alertas": ["string"] }
      ''')
    ];

    try {
      final response = await jsonModel.generateContent(prompt);
      final decoded = jsonDecode(response.text ?? '{"alertas": []}');
      return List<String>.from(decoded['alertas'] ?? []);
    } catch (e) { return ["Erro na auditoria do estrato."]; }
  }

  /// Auxiliar atualizado para incluir Fuste e Altura de Dano
  Map<String, dynamic> _prepararResumoPlot(Parcela p, List<Arvore> arvores, {double? idade}) {
    return {
      "t": p.nomeTalhao,
      "f": p.nomeFazenda,
      "idade": idade ?? "N/I",
      "arv": arvores.map((a) => {
        "id": a.id,
        "l": a.linha,
        "p": a.posicaoNaLinha,
        "fust": a.tora, // ou o campo que você usa para número do fuste
        "c": a.cap,
        "h": a.altura ?? 0,
        "hd": a.alturaDano ?? 0, // Fundamental para a regra de Quebradas
        "cod": a.codigo.name
      }).toList()
    };
  }
}
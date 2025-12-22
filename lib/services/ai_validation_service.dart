import 'dart:convert';
import 'package:firebase_ai/firebase_ai.dart'; 
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';

class AiValidationService {
  late final GenerativeModel _model;

  AiValidationService() {
    // CORREÇÃO AQUI:
    // Troque 'FirebaseAI.instance' por 'FirebaseAI.googleAI()'
    // (Pois você ativou a Gemini Developer API no console)
    
    _model = FirebaseAI.googleAI().generativeModel(
      model: 'gemini-1.5-flash', 
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );
  }

  // ... o resto do código continua igual ...
  Future<List<String>> validarParcelaInteligente(Parcela parcela, List<Arvore> arvores) async {
    final dadosContexto = {
      "talhao": parcela.nomeTalhao,
      "area_parcela": parcela.areaMetrosQuadrados,
      "arvores": arvores.map((a) => {
        "linha": a.linha,
        "pos": a.posicaoNaLinha,
        "cap": a.cap,
        "altura": a.altura,
        "dano": a.alturaDano,
        "codigo": a.codigo.name
      }).toList()
    };

    final prompt = Content.text('''
      Atue como um auditor florestal. Analise os dados desta parcela.
      Busque erros de digitação, valores impossíveis ou sequências erradas.
      
      Dados: ${jsonEncode(dadosContexto)}
      
      Retorne APENAS um JSON: { "alertas": ["Erro 1...", "Erro 2..."] }
      Se não houver erros, retorne lista vazia.
    ''');

    try {
      final response = await _model.generateContent([prompt]);
      final text = response.text;
      
      if (text == null) return [];

      final jsonResponse = jsonDecode(text);
      return List<String>.from(jsonResponse['alertas'] ?? []);
      
    } catch (e, stackTrace) {
      // --- MUDANÇA AQUI PARA DEBUGAR ---
      print("❌ ERRO GRAVE NA IA: $e");
      print("Stack: $stackTrace");
      
      // Retornamos a mensagem técnica para você ver no app o que está havendo
      return ["Erro técnico: ${e.toString().split(']').last.trim()}"]; 
    }
  }
}
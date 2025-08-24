// lib/models/arvore_model.dart (VERSÃO FINAL REVISADA E ROBUSTA)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';

/// Códigos primários para classificar uma árvore durante o inventário.
enum Codigo {
  Normal,
  Falha, // Já existia
  Bifurcada,
  Multipla,
  Quebrada,
  Caida, // "Caida" já existia
  Dominada,
  Geada,
  Fogo,
  PragasOuDoencas,
  AtaqueMacaco, // Já existia como "ataquemacaco"
  VespaMadeira,
  MortaOuSeca, // "Morta" já existia
  PonteiraSeca,  
  Rebrota,
  AtaqueFormiga, // "Formiga" já existia
  Torta,
  FoxTail,
  Inclinada,
  DeitadaVento,
  FeridaBase,
  CaidaRaizVento,
  Resinado,
  Outro // Já existia

}

/// Códigos secundários para adicionar uma segunda característica à árvore.
enum Codigo2 {
  Bifurcada,
  Multipla,
  Quebrada, // Já existia // Já existia como "multipla"    
  Geada,
  Fogo,
  PragasOuDoencas,
  AtaqueMacaco, // Já existia como "ataquemacaco"
  VespaMadeira,
  MortaOuSeca, // "Morta" já existia
  PonteiraSeca,  
  Rebrota,
  AtaqueFormiga, // "Formiga" já existia
  Torta,
  FoxTail,
  Inclinada,
  DeitadaVento,
  FeridaBase,
  Resinado,
  Outro // Já existia
}

/// Representa uma única árvore medida em uma parcela de inventário.
class Arvore {
  /// ID único do banco de dados local (gerado automaticamente).
  int? id;
  
  /// Circunferência à Altura do Peito (1.30m) em centímetros.
  final double cap;
  
  /// Altura total da árvore em metros.
  final double? altura;
  
  /// Altura do Dano/Defeito na árvore em metros.
  final double? alturaDano;
  
  /// Número da linha de plantio onde a árvore está localizada.
  final int linha;
  
  /// Posição da árvore dentro da linha de plantio.
  final int posicaoNaLinha;
  
  /// Indica se esta é a última árvore da linha.
  final bool fimDeLinha;
  
  /// Indica se a árvore foi selecionada como dominante.
  bool dominante;
  
  /// O código principal que classifica a árvore.
  final Codigo codigo;
  
  /// Um segundo código opcional para detalhar a classificação.
  final Codigo2? codigo2;
  
  /// Um terceiro código opcional, geralmente para texto livre.
  final String? codigo3;
  
  /// Número da tora, se aplicável.
  final int? tora;
  
  /// Valor do CAP de uma medição de auditoria.
  final double? capAuditoria;
  
  /// Valor da Altura de uma medição de auditoria.
  final double? alturaAuditoria;
  
  /// Volume da árvore, calculado posteriormente.
  double? volume;
  
  /// Data e hora da última modificação do registro.
  final DateTime? lastModified;

  Arvore({
    this.id,
    required this.cap,
    this.altura,
    this.alturaDano,
    required this.linha,
    required this.posicaoNaLinha,
    this.fimDeLinha = false,
    this.dominante = false,
    required this.codigo,
    this.codigo2,
    this.codigo3,
    this.tora,
    this.capAuditoria,
    this.alturaAuditoria,
    this.volume,
    this.lastModified,
  });

  Arvore copyWith({
    int? id,
    double? cap,
    double? altura,
    double? alturaDano,
    int? linha,
    int? posicaoNaLinha,
    bool? fimDeLinha,
    bool? dominante,
    Codigo? codigo,
    Codigo2? codigo2,
    String? codigo3,
    int? tora,
    double? capAuditoria,
    double? alturaAuditoria,
    double? volume,
    DateTime? lastModified,
  }) {
    return Arvore(
      id: id ?? this.id,
      cap: cap ?? this.cap,
      altura: altura ?? this.altura,
      alturaDano: alturaDano ?? this.alturaDano,
      linha: linha ?? this.linha,
      posicaoNaLinha: posicaoNaLinha ?? this.posicaoNaLinha,
      fimDeLinha: fimDeLinha ?? this.fimDeLinha,
      dominante: dominante ?? this.dominante,
      codigo: codigo ?? this.codigo,
      codigo2: codigo2 ?? this.codigo2,
      codigo3: codigo3 ?? this.codigo3,
      tora: tora ?? this.tora,
      capAuditoria: capAuditoria ?? this.capAuditoria,
      alturaAuditoria: alturaAuditoria ?? this.alturaAuditoria,
      volume: volume ?? this.volume,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  /// Converte o objeto Arvore para um Map, pronto para ser salvo no banco de dados local.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cap': cap,
      'altura': altura,
      'alturaDano': alturaDano,
      'linha': linha,
      'posicaoNaLinha': posicaoNaLinha,
      'fimDeLinha': fimDeLinha ? 1 : 0,
      'dominante': dominante ? 1 : 0,
      'codigo': codigo.name,
      'codigo2': codigo2?.name,
      'codigo3': codigo3,
      'tora': tora,
      'capAuditoria': capAuditoria,
      'alturaAuditoria': alturaAuditoria,
      'lastModified': lastModified?.toIso8601String(),
    };
  }

  /// Cria um objeto Arvore a partir de um Map vindo do banco de dados (local ou Firestore).
  factory Arvore.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      } else if (value is String) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    return Arvore(
      id: map['id'],
      cap: map['cap']?.toDouble() ?? 0.0,
      altura: map['altura']?.toDouble(),
      alturaDano: map['alturaDano']?.toDouble(),
      linha: map['linha'] ?? 0,
      posicaoNaLinha: map['posicaoNaLinha'] ?? 0,
      fimDeLinha: map['fimDeLinha'] == 1,
      dominante: map['dominante'] == 1,
      codigo: Codigo.values.firstWhere((e) => e.name == map['codigo'], orElse: () => Codigo.Normal),
      // <<< MELHORIA: Lógica mais segura para evitar erros se o texto do banco for inválido >>>
      codigo2: map['codigo2'] != null
          ? Codigo2.values.firstWhereOrNull( // <<< MUDANÇA 1: Usar 'firstWhereOrNull'
              (e) => e.name.toLowerCase() == map['codigo2'].toString().toLowerCase()
          )
          : null,
      codigo3: map['codigo3'],
      tora: map['tora'],
      capAuditoria: map['capAuditoria']?.toDouble(),
      alturaAuditoria: map['alturaAuditoria']?.toDouble(),
      lastModified: parseDate(map['lastModified']),
    );
  }
}
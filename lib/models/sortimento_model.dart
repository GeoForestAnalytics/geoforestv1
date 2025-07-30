// lib/models/sortimento_model.dart (ARQUIVO NOVO E CORRIGIDO)

class SortimentoModel {
  final int? id;
  final String nome;
  final double comprimento;
  final double diametroMinimo; // em cm
  final double diametroMaximo; // em cm
  // Você pode adicionar mais propriedades aqui, como 'usoFinal', 'qualidade', etc.

  // Construtor que inicializa todas as variáveis 'final'
  SortimentoModel({
    this.id,
    required this.nome,
    required this.comprimento,
    required this.diametroMinimo,
    required this.diametroMaximo,
  });

  // Métodos de conveniência (padrão que você já utiliza)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'comprimento': comprimento,
      'diametroMinimo': diametroMinimo,
      'diametroMaximo': diametroMaximo,
    };
  }

  factory SortimentoModel.fromMap(Map<String, dynamic> map) {
    return SortimentoModel(
      id: map['id'],
      nome: map['nome'] ?? '',
      comprimento: map['comprimento']?.toDouble() ?? 0.0,
      diametroMinimo: map['diametroMinimo']?.toDouble() ?? 0.0,
      diametroMaximo: map['diametroMaximo']?.toDouble() ?? 0.0,
    );
  }
}
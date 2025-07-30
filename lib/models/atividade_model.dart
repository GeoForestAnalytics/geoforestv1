// lib/models/atividade_model.dart

enum TipoAtividade {
  ipc("Inventário Pré-Corte"),
  ifc("Inventário Florestal Contínuo"),
  cub("Cubagem Rigorosa"),
  aud("Auditoria"),
  ifq6("IFQ - 6 Meses"),
  ifq12("IFQ - 12 Meses"),
  ifs("Inventário de Sobrevivência e Qualidade"),
  bio("Inventario Biomassa");

  const TipoAtividade(this.descricao);
  final String descricao;
}

class Atividade {
  final int? id;
  final int projetoId; // Chave estrangeira para o Projeto
  final String tipo;
  final String descricao; // Campo para notas ou detalhes específicos
  final DateTime dataCriacao;
  // <<< NOVO CAMPO AQUI >>>
  // Guarda o método de cubagem ('Fixas' ou 'Relativas') se a atividade for de cubagem.
  final String? metodoCubagem;

  Atividade({
    this.id,
    required this.projetoId,
    required this.tipo,
    required this.descricao,
    required this.dataCriacao,
    this.metodoCubagem, // <<< ADICIONADO AO CONSTRUTOR
  });

  Atividade copyWith({
    int? id,
    int? projetoId,
    String? tipo,
    String? descricao,
    DateTime? dataCriacao,
    String? metodoCubagem, // <<< ADICIONADO AO COPYWITH
  }) {
    return Atividade(
      id: id ?? this.id,
      projetoId: projetoId ?? this.projetoId,
      tipo: tipo ?? this.tipo,
      descricao: descricao ?? this.descricao,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      metodoCubagem: metodoCubagem ?? this.metodoCubagem, // <<< ADICIONADO AQUI
    );
  }


  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'projetoId': projetoId,
      'tipo': tipo,
      'descricao': descricao,
      'dataCriacao': dataCriacao.toIso8601String(),
      'metodoCubagem': metodoCubagem, // <<< ADICIONADO AO MAP
    };
  }

  factory Atividade.fromMap(Map<String, dynamic> map) {
    return Atividade(
      id: map['id'],
      projetoId: map['projetoId'],
      tipo: map['tipo'],
      descricao: map['descricao'],
      dataCriacao: DateTime.parse(map['dataCriacao']),
      metodoCubagem: map['metodoCubagem'], // <<< ADICIONADO AO FACTORY
    );
  }
}
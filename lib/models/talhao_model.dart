// lib/models/talhao_model.dart

class Talhao {
  final int? id;
  
  // Chaves estrangeiras
  final String fazendaId; 
  final int fazendaAtividadeId;
  final int? projetoId;
  // Propriedades do Talhão
  final String nome;
  final double? areaHa;
  final double? idadeAnos;
  final String? especie;
  final String? espacamento;

  // Campo para exibição na UI
  final String? fazendaNome;
  
  // <<< NOVO CAMPO PARA CÁLCULO TEMPORÁRIO >>>
  double? volumeTotalTalhao;

  Talhao({
    this.id,
    required this.fazendaId,
    required this.fazendaAtividadeId,
    this.projetoId,
    required this.nome,
    this.areaHa,
    this.idadeAnos,
    this.especie,
    this.espacamento,
    this.fazendaNome,
    this.volumeTotalTalhao, // Adicionado ao construtor
  });

  Talhao copyWith({
    int? id,
    String? fazendaId,
    int? fazendaAtividadeId,
    int? projetoId,
    String? nome,
    double? areaHa,
    double? idadeAnos,
    String? especie,
    String? espacamento,
    String? fazendaNome,
    double? volumeTotalTalhao,
  }) {
    return Talhao(
      id: id ?? this.id,
      fazendaId: fazendaId ?? this.fazendaId,
      fazendaAtividadeId: fazendaAtividadeId ?? this.fazendaAtividadeId,
      nome: nome ?? this.nome,
      areaHa: areaHa ?? this.areaHa,
      idadeAnos: idadeAnos ?? this.idadeAnos,
      especie: especie ?? this.especie,
      espacamento: espacamento ?? this.espacamento,
      fazendaNome: fazendaNome ?? this.fazendaNome,
      volumeTotalTalhao: volumeTotalTalhao ?? this.volumeTotalTalhao,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fazendaId': fazendaId,
      'fazendaAtividadeId': fazendaAtividadeId,
      'nome': nome,
      'areaHa': areaHa,
      'idadeAnos': idadeAnos,
      'especie': especie,
      'espacamento': espacamento,
    };
  }

  factory Talhao.fromMap(Map<String, dynamic> map) {
    return Talhao(
      id: map['id'],
      fazendaId: map['fazendaId'],
      fazendaAtividadeId: map['fazendaAtividadeId'],
      nome: map['nome'],
      areaHa: map['areaHa'],
      idadeAnos: map['idadeAnos'],
      especie: map['especie'],
      espacamento: map['espacamento'],
      fazendaNome: map['fazendaNome'], 
    );
  }
}
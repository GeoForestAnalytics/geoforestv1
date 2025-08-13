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

  // Campos para exibição na UI
  final String? fazendaNome;
  final String? municipio; // <-- ADICIONE
  final String? estado;    // <-- ADICIONE
  
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
    this.municipio, // <-- ADICIONE
    this.estado,    // <-- ADICIONE
    this.volumeTotalTalhao,
  });

  // ADICIONE municipio E estado AO MÉTODO copyWith
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
    String? municipio, // <-- ADICIONE
    String? estado,    // <-- ADICIONE
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
      municipio: municipio ?? this.municipio, // <-- ADICIONE
      estado: estado ?? this.estado,          // <-- ADICIONE
      volumeTotalTalhao: volumeTotalTalhao ?? this.volumeTotalTalhao,
    );
  }

  Map<String, dynamic> toMap() {
    // ... (este método não precisa de alterações)
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

  // ADICIONE municipio E estado AO MÉTODO fromMap
  factory Talhao.fromMap(Map<String, dynamic> map) {
    return Talhao(
      id: map['id'],
      fazendaId: map['fazendaId'],
      fazendaAtividadeId: map['fazendaAtividadeId'],
      projetoId: map['projetoId'],
      nome: map['nome'],
      areaHa: map['areaHa'],
      idadeAnos: map['idadeAnos'],
      especie: map['especie'],
      espacamento: map['espacamento'],
      fazendaNome: map['fazendaNome'], 
      municipio: map['municipio'], // <-- ADICIONE
      estado: map['estado'],       // <-- ADICIONE
    );
  }
}
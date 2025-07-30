// lib/models/fazenda_model.dart

class Fazenda {
  // O id agora é a string fornecida pelo cliente e é obrigatória
  final String id; 
  final int atividadeId;
  final String nome;
  final String municipio;
  final String estado;

  Fazenda({
    required this.id,
    required this.atividadeId,
    required this.nome,
    required this.municipio,
    required this.estado,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'atividadeId': atividadeId,
      'nome': nome,
      'municipio': municipio,
      'estado': estado,
    };
  }

  factory Fazenda.fromMap(Map<String, dynamic> map) {
    return Fazenda(
      id: map['id'],
      atividadeId: map['atividadeId'],
      nome: map['nome'],
      municipio: map['municipio'],
      estado: map['estado'],
    );
  }
}
class Especie {
  final int? id;
  final String nomeCientifico;
  final String nomeComum;
  final String familia;
  final double fatorForma;
  final String regiao;

  Especie({
    this.id,
    required this.nomeCientifico,
    required this.nomeComum,
    required this.familia,
    this.fatorForma = 0.5,
    required this.regiao,
  });

  // Converte para salvar no banco
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome_cientifico': nomeCientifico,
      'nome_comum': nomeComum,
      'familia': familia,
      'fator_forma': fatorForma,
      'regiao': regiao,
    };
  }

  // Converte do banco para o App
  factory Especie.fromMap(Map<String, dynamic> map) {
    return Especie(
      id: map['id'],
      nomeCientifico: map['nome_cientifico'] ?? '',
      nomeComum: map['nome_comum'] ?? '',
      familia: map['familia'] ?? '',
      fatorForma: (map['fator_forma'] as num?)?.toDouble() ?? 0.5,
      regiao: map['regiao'] ?? 'Geral',
    );
  }

  // O que aparece na lista do Autocomplete
  @override
  String toString() {
    return '$nomeComum ($nomeCientifico)';
  }
}
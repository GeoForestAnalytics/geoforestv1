// lib/models/cubagem_arvore_model.dart (VERSÃO COMPLETA E CORRIGIDA)

class CubagemArvore {
  int? id;
  int? talhaoId;
  String? idFazenda;
  String nomeFazenda;
  String nomeTalhao;
  String identificador;
  String? classe;
  bool exportada;
  bool isSynced; // <<< CAMPO ADICIONADO

  double alturaTotal;
  String tipoMedidaCAP;
  double valorCAP;
  double alturaBase;

  CubagemArvore({
    this.id,
    this.talhaoId,
    this.idFazenda,
    required this.nomeFazenda,
    required this.nomeTalhao,
    required this.identificador,
    this.classe,
    this.exportada = false,
    this.isSynced = false, // <<< CAMPO ADICIONADO AO CONSTRUTOR
    this.alturaTotal = 0,
    this.tipoMedidaCAP = 'fita',
    this.valorCAP = 0,
    this.alturaBase = 0,
  });

  // <<< MÉTODO copyWith ADICIONADO >>>
  CubagemArvore copyWith({
    int? id,
    int? talhaoId,
    String? idFazenda,
    String? nomeFazenda,
    String? nomeTalhao,
    String? identificador,
    String? classe,
    bool? exportada,
    bool? isSynced,
    double? alturaTotal,
    String? tipoMedidaCAP,
    double? valorCAP,
    double? alturaBase,
  }) {
    return CubagemArvore(
      id: id ?? this.id,
      talhaoId: talhaoId ?? this.talhaoId,
      idFazenda: idFazenda ?? this.idFazenda,
      nomeFazenda: nomeFazenda ?? this.nomeFazenda,
      nomeTalhao: nomeTalhao ?? this.nomeTalhao,
      identificador: identificador ?? this.identificador,
      classe: classe ?? this.classe,
      exportada: exportada ?? this.exportada,
      isSynced: isSynced ?? this.isSynced,
      alturaTotal: alturaTotal ?? this.alturaTotal,
      tipoMedidaCAP: tipoMedidaCAP ?? this.tipoMedidaCAP,
      valorCAP: valorCAP ?? this.valorCAP,
      alturaBase: alturaBase ?? this.alturaBase,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'talhaoId': talhaoId,
      'id_fazenda': idFazenda,
      'nome_fazenda': nomeFazenda,
      'nome_talhao': nomeTalhao,
      'identificador': identificador,
      'classe': classe,
      'alturaTotal': alturaTotal,
      'tipoMedidaCAP': tipoMedidaCAP,
      'valorCAP': valorCAP,
      'alturaBase': alturaBase,
      'exportada': exportada ? 1 : 0,
      'isSynced': isSynced ? 1 : 0, // <<< CAMPO ADICIONADO AO MAPA
    };
  }

  factory CubagemArvore.fromMap(Map<String, dynamic> map) {
    return CubagemArvore(
      id: map['id'],
      talhaoId: map['talhaoId'],
      idFazenda: map['id_fazenda'],
      nomeFazenda: map['nome_fazenda'] ?? '',
      nomeTalhao: map['nome_talhao'] ?? '',
      identificador: map['identificador'],
      classe: map['classe'],
      exportada: map['exportada'] == 1,
      isSynced: map['isSynced'] == 1, // <<< CAMPO ADICIONADO AO FACTORY
      alturaTotal: map['alturaTotal']?.toDouble() ?? 0,
      tipoMedidaCAP: map['tipoMedidaCAP'] ?? 'fita',
      valorCAP: map['valorCAP']?.toDouble() ?? 0,
      alturaBase: map['alturaBase']?.toDouble() ?? 0,
    );
  }
}
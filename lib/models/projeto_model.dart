// lib/models/projeto_model.dart (VERSÃO COM CAMPO DE DELEGAÇÃO)

class Projeto {
  final String? licenseId;
  final int? id;
  final String nome;
  final String empresa;
  final String responsavel;
  final DateTime dataCriacao;
  final String status;
  // <<< MUDANÇA 1: Adicionado o novo campo para rastrear a delegação >>>
  final String? delegadoPorLicenseId;

  Projeto({
    this.id,
    this.licenseId,
    required this.nome,
    required this.empresa,
    required this.responsavel,
    required this.dataCriacao,
    this.status = 'ativo',
    // <<< MUDANÇA 2: Adicionado ao construtor >>>
    this.delegadoPorLicenseId,
  });

  Projeto copyWith({
    int? id,
    String? licenseId,
    String? nome,
    String? empresa,
    String? responsavel,
    DateTime? dataCriacao,
    String? status,
    // <<< MUDANÇA 3: Adicionado ao método copyWith >>>
    String? delegadoPorLicenseId,
  }) {
    return Projeto(
      id: id ?? this.id,
      licenseId: licenseId ?? this.licenseId,
      nome: nome ?? this.nome,
      empresa: empresa ?? this.empresa,
      responsavel: responsavel ?? this.responsavel,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      status: status ?? this.status,
      // <<< MUDANÇA 4: Adicionado aqui >>>
      delegadoPorLicenseId: delegadoPorLicenseId ?? this.delegadoPorLicenseId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'licenseId': licenseId,
      'nome': nome,
      'empresa': empresa,
      'responsavel': responsavel,
      'dataCriacao': dataCriacao.toIso8601String(),
      'status': status,
      // <<< MUDANÇA 5: Adicionado ao mapa para salvar no banco de dados >>>
      'delegado_por_license_id': delegadoPorLicenseId,
    };
  }

  factory Projeto.fromMap(Map<String, dynamic> map) {
    return Projeto(
      id: map['id'],
      licenseId: map['licenseId'],
      nome: map['nome'],
      empresa: map['empresa'],
      responsavel: map['responsavel'],
      dataCriacao: DateTime.parse(map['dataCriacao']),
      status: map['status'] ?? 'ativo',
      // <<< MUDANÇA 6: Lendo o novo campo do banco de dados >>>
      delegadoPorLicenseId: map['delegado_por_license_id'],
    );
  }
}
// lib/models/vehicle_checklist_model.dart

import 'dart:convert';

class VehicleChecklist {
  int? id;
  final DateTime dataRegistro;
  final String? uidUsuario;
  final String nomeMotorista;
  final String? placa;
  final double? kmAtual;
  final String? modeloVeiculo;
  
  // NOVOS CAMPOS
  final String? prefixo;
  final String? categoriaCnh;
  final DateTime? vencimentoCnh;

  final bool isMotorista;
  final Map<String, String> itens;
  final String? observacoes;
  
  // REMOVIDO: final List<String> fotosAvarias;
  
  final DateTime lastModified;

  VehicleChecklist({
    this.id,
    required this.dataRegistro,
    this.uidUsuario,
    required this.nomeMotorista,
    this.placa,
    this.kmAtual,
    this.modeloVeiculo,
    this.prefixo,
    this.categoriaCnh,
    this.vencimentoCnh,
    required this.isMotorista,
    this.itens = const {},
    this.observacoes,
    // REMOVIDO: this.fotosAvarias = const [],
    required this.lastModified,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'data_registro': dataRegistro.toIso8601String(),
      'uid_usuario': uidUsuario,
      'nome_motorista': nomeMotorista,
      'placa': placa,
      'km_atual': kmAtual,
      'modelo_veiculo': modeloVeiculo,
      'prefixo': prefixo,
      'categoria_cnh': categoriaCnh,
      'vencimento_cnh': vencimentoCnh?.toIso8601String(),
      'is_motorista': isMotorista ? 1 : 0,
      'itens_json': jsonEncode(itens),
      'observacoes': observacoes,
      // REMOVIDO: 'fotos_avarias': jsonEncode(fotosAvarias), 
      'lastModified': lastModified.toIso8601String(),
    };
  }

  factory VehicleChecklist.fromMap(Map<String, dynamic> map) {
    return VehicleChecklist(
      id: map['id'],
      dataRegistro: DateTime.parse(map['data_registro']),
      uidUsuario: map['uid_usuario'],
      nomeMotorista: map['nome_motorista'],
      placa: map['placa'],
      kmAtual: map['km_atual'],
      modeloVeiculo: map['modelo_veiculo'],
      prefixo: map['prefixo'],
      categoriaCnh: map['categoria_cnh'],
      vencimentoCnh: map['vencimento_cnh'] != null ? DateTime.parse(map['vencimento_cnh']) : null,
      isMotorista: map['is_motorista'] == 1,
      itens: Map<String, String>.from(jsonDecode(map['itens_json'] ?? '{}')),
      observacoes: map['observacoes'],
      // REMOVIDO A LÓGICA DE FOTOS AQUI
      lastModified: DateTime.parse(map['lastModified']),
    );
  }
}

// Lista fixa dos itens baseada na sua foto
const List<String> checklistItensDescricao = [
  "1. Documentação do veículo (Digital ou físico)",
  "2. Manual do veículo",
  "3. Ar condicionado",
  "4. Lataria",
  "5. Estado das lanternas e faróis",
  "6. Luz Baixa",
  "7. Meia Luz",
  "8. Luz Alta",
  "9. Luzes de seta",
  "10. Pisca Alerta",
  "11. Pneu",
  "12. Estepe",
  "13. Macaco",
  "14. Chave de Roda",
  "15. Triângulo",
  "16. Limpeza externa",
  "17. O para-brisa apresenta alguma trinca/dano?",
  "18. Limpador de Para brisa",
  "19. Espelhos Retrovisores",
  "20. Quebra sol",
  "21. Bancos",
  "22. Cinto de Segurança",
  "23. Funcionalidade das luzes de advertência no painel?",
  "24. Limpeza interna / Odor incômodo?",
  "25. Funcionamento da trava elétrica/manual",
  "26. Rastreador (cabos e fixação)",
  "27. Nível óleo",
  "28. Nível água para-brisa"
];
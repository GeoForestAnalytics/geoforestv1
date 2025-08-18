// Crie o arquivo: lib/models/diario_de_campo_model.dart

class DiarioDeCampo {
  final int? id;
  final String dataRelatorio;
  final String nomeLider;
  final int projetoId;
  final int talhaoId;
  final double? kmInicial;
  final double? kmFinal;
  final String? localizacaoDestino;
  final double? pedagioValor;
  final double? abastecimentoValor;
  final int? alimentacaoMarmitasQtd;
  final double? alimentacaoRefeicaoValor;
  final String? alimentacaoDescricao;
  final String? veiculoPlaca;
  final String? veiculoModelo;
  final String? equipeNoCarro;
  final String lastModified;

  DiarioDeCampo({
    this.id,
    required this.dataRelatorio,
    required this.nomeLider,
    required this.projetoId,
    required this.talhaoId,
    this.kmInicial,
    this.kmFinal,
    this.localizacaoDestino,
    this.pedagioValor,
    this.abastecimentoValor,
    this.alimentacaoMarmitasQtd,
    this.alimentacaoRefeicaoValor,
    this.alimentacaoDescricao,
    this.veiculoPlaca,
    this.veiculoModelo,
    this.equipeNoCarro,
    required this.lastModified,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'data_relatorio': dataRelatorio,
      'nome_lider': nomeLider,
      'projeto_id': projetoId,
      'talhao_id': talhaoId,
      'km_inicial': kmInicial,
      'km_final': kmFinal,
      'localizacao_destino': localizacaoDestino,
      'pedagio_valor': pedagioValor,
      'abastecimento_valor': abastecimentoValor,
      'alimentacao_marmitas_qtd': alimentacaoMarmitasQtd,
      'alimentacao_refeicao_valor': alimentacaoRefeicaoValor,
      'alimentacao_descricao': alimentacaoDescricao,
      'veiculo_placa': veiculoPlaca,
      'veiculo_modelo': veiculoModelo,
      'equipe_no_carro': equipeNoCarro,
      'lastModified': lastModified,
    };
  }

  factory DiarioDeCampo.fromMap(Map<String, dynamic> map) {
    return DiarioDeCampo(
      id: map['id'],
      dataRelatorio: map['data_relatorio'],
      nomeLider: map['nome_lider'],
      projetoId: map['projeto_id'],
      talhaoId: map['talhao_id'],
      kmInicial: map['km_inicial'],
      kmFinal: map['km_final'],
      localizacaoDestino: map['localizacao_destino'],
      pedagioValor: map['pedagio_valor'],
      abastecimentoValor: map['abastecimento_valor'],
      alimentacaoMarmitasQtd: map['alimentacao_marmitas_qtd'],
      alimentacaoRefeicaoValor: map['alimentacao_refeicao_valor'],
      alimentacaoDescricao: map['alimentacao_descricao'],
      veiculoPlaca: map['veiculo_placa'],
      veiculoModelo: map['veiculo_modelo'],
      equipeNoCarro: map['equipe_no_carro'],
      lastModified: map['lastModified'],
    );
  }
}
// lib/data/datasources/local/database_constants.dart

class DbProjetos {
  static const String tableName = 'projetos';
  static const String id = 'id';
  static const String licenseId = 'licenseId';
  static const String nome = 'nome';
  static const String empresa = 'empresa';
  static const String responsavel = 'responsavel';
  static const String dataCriacao = 'dataCriacao';
  static const String status = 'status';
  static const String delegadoPorLicenseId = 'delegado_por_license_id';
  static const String referenciaRf = 'referencia_rf';
  static const String lastModified = 'lastModified';
}

class DbAtividades {
  static const String tableName = 'atividades';
  static const String id = 'id';
  static const String projetoId = 'projetoId';
  static const String tipo = 'tipo';
  static const String descricao = 'descricao';
  static const String dataCriacao = 'dataCriacao';
  static const String metodoCubagem = 'metodoCubagem';
  static const String lastModified = 'lastModified';
}

class DbFazendas {
  static const String tableName = 'fazendas';
  static const String id = 'id';
  static const String atividadeId = 'atividadeId';
  static const String nome = 'nome';
  static const String municipio = 'municipio';
  static const String estado = 'estado';
  static const String lastModified = 'lastModified';
}

class DbTalhoes {
  static const String tableName = 'talhoes';
  static const String id = 'id';
  static const String fazendaId = 'fazendaId';
  static const String fazendaAtividadeId = 'fazendaAtividadeId';
  static const String projetoId = 'projetoId';
  static const String nome = 'nome';
  static const String areaHa = 'areaHa';
  static const String idadeAnos = 'idadeAnos';
  static const String especie = 'especie';
  static const String espacamento = 'espacamento';
  static const String bloco = 'bloco';
  static const String up = 'up';
  static const String materialGenetico = 'material_genetico';
  static const String dataPlantio = 'data_plantio';
  static const String lastModified = 'lastModified';
}

class DbParcelas {
  static const String tableName = 'parcelas';
  static const String id = 'id';
  static const String uuid = 'uuid';
  static const String talhaoId = 'talhaoId';
  static const String nomeFazenda = 'nomeFazenda';
  static const String nomeTalhao = 'nomeTalhao';
  static const String idParcela = 'idParcela';
  static const String areaMetrosQuadrados = 'areaMetrosQuadrados';
  static const String observacao = 'observacao';
  static const String latitude = 'latitude';
  static const String longitude = 'longitude';
  static const String altitude = 'altitude';
  static const String dataColeta = 'dataColeta';
  static const String status = 'status';
  static const String exportada = 'exportada';
  static const String isSynced = 'isSynced';
  static const String idFazenda = 'idFazenda';
  static const String photoPaths = 'photoPaths';
  static const String nomeLider = 'nomeLider';
  static const String projetoId = 'projetoId';
  static const String municipio = 'municipio';
  static const String estado = 'estado';
  static const String up = 'up';
  static const String referenciaRf = 'referencia_rf';
  static const String ciclo = 'ciclo';
  static const String rotacao = 'rotacao';
  static const String tipoParcela = 'tipo_parcela';
  static const String formaParcela = 'forma_parcela';
  static const String lado1 = 'lado1';
  static const String lado2 = 'lado2';
  static const String declividade = 'declividade';
  static const String lastModified = 'lastModified';
}

class DbArvores {
  static const String tableName = 'arvores';
  static const String id = 'id';
  static const String parcelaId = 'parcelaId';
  static const String cap = 'cap';
  static const String altura = 'altura';
  static const String alturaDano = 'alturaDano';
  static const String linha = 'linha';
  static const String posicaoNaLinha = 'posicaoNaLinha';
  static const String fimDeLinha = 'fimDeLinha';
  static const String dominante = 'dominante';
  static const String codigo = 'codigo';
  static const String codigo2 = 'codigo2';
  static const String codigo3 = 'codigo3';
  static const String tora = 'tora';
  static const String observacao = 'observacao';
  static const String capAuditoria = 'capAuditoria';
  static const String alturaAuditoria = 'alturaAuditoria';
  static const String lastModified = 'lastModified';
}

class DbConfigCodigos {
  static const String tableName = 'config_codigos';
  static const String id = 'id'; // 101, 102...
  static const String projetoId = 'projetoId';
  static const String codigoLabel = 'codigoLabel'; // A, B, CA...
  static const String descricao = 'descricao';
  static const String fusteObrigatorio = 'fuste'; // S, N
  static const String capObrigatorio = 'cap'; // S, N, C
  static const String alturaObrigatoria = 'altura'; // S, N, C, #
  static const String dominantePermitido = 'dominante'; // S, N
}

class DbCubagensArvores {
  static const String tableName = 'cubagens_arvores';
  static const String id = 'id';
  static const String talhaoId = 'talhaoId';
  static const String idFazenda = 'id_fazenda';
  static const String nomeFazenda = 'nome_fazenda';
  static const String nomeTalhao = 'nome_talhao';
  static const String identificador = 'identificador';
  static const String alturaTotal = 'alturaTotal';
  static const String tipoMedidaCAP = 'tipoMedidaCAP';
  static const String valorCAP = 'valorCAP';
  static const String alturaBase = 'alturaBase';
  static const String classe = 'classe';
  static const String observacao = 'observacao';
  static const String latitude = 'latitude';
  static const String longitude = 'longitude';
  static const String metodoCubagem = 'metodoCubagem';
  static const String rf = 'rf';
  static const String dataColeta = 'dataColeta';
  static const String exportada = 'exportada';
  static const String isSynced = 'isSynced';
  static const String nomeLider = 'nomeLider';
  static const String lastModified = 'lastModified';
}

class DbCubagensSecoes {
  static const String tableName = 'cubagens_secoes';
  static const String id = 'id';
  static const String cubagemArvoreId = 'cubagemArvoreId';
  static const String alturaMedicao = 'alturaMedicao';
  static const String circunferencia = 'circunferencia';
  static const String casca1Mm = 'casca1_mm';
  static const String casca2Mm = 'casca2_mm';
  static const String lastModified = 'lastModified';
}

class DbSortimentos {
  static const String tableName = 'sortimentos';
  static const String id = 'id';
  static const String nome = 'nome';
  static const String comprimento = 'comprimento';
  static const String diametroMinimo = 'diametroMinimo';
  static const String diametroMaximo = 'diametroMaximo';
}

class DbDiarioDeCampo {
  static const String tableName = 'diario_de_campo';
  static const String id = 'id';
  static const String dataRelatorio = 'data_relatorio';
  static const String nomeLider = 'nome_lider';
  static const String projetoId = 'projeto_id';
  static const String talhaoId = 'talhao_id';
  static const String kmInicial = 'km_inicial';
  static const String kmFinal = 'km_final';
  static const String localizacaoDestino = 'localizacao_destino';
  static const String pedagioValor = 'pedagio_valor';
  static const String abastecimentoValor = 'abastecimento_valor';
  static const String alimentacaoMarmitasQtd = 'alimentacao_marmitas_qtd';
  static const String alimentacaoRefeicaoValor = 'alimentacao_refeicao_valor';
  static const String alimentacaoDescricao = 'alimentacao_descricao';
  static const String outrasDespesasValor = 'outras_despesas_valor';
  static const String outrasDespesasDescricao = 'outras_despesas_descricao';
  static const String veiculoPlaca = 'veiculo_placa';
  static const String veiculoModelo = 'veiculo_modelo';
  static const String equipeNoCarro = 'equipe_no_carro';
  static const String lastModified = 'lastModified';
}
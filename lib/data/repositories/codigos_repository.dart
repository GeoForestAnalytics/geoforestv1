import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:geoforestv1/models/codigo_florestal_model.dart';

class CodigosRepository {

  /// Classifica a string livre de tipo de atividade (digitada pelo usuário
  /// no cadastro da Atividade) numa categoria canônica de tabela de códigos.
  String classificarTipo(String tipoAtividade) {
    final t = tipoAtividade.toLowerCase();
    if (t.contains('ifc')) return 'IFC';
    if (t.contains('qualidade') || t.contains('ifq')) return 'IFQ';
    if (t.contains('sobreviv') || t.contains('ifs')) return 'IFS';
    if (t.contains('biomassa') || t.contains('bio')) return 'BIO';
    return 'IPC';
  }

  String _getFileName(String tipoAtividade) {
    switch (classificarTipo(tipoAtividade)) {
      case 'IFC':
        return 'assets/data/codigos/codigos_ifc.csv';
      case 'IFQ':
        return 'assets/data/codigos/codigos_ifq.csv';
      case 'IFS':
        return 'assets/data/codigos/codigos_ifs.csv';
      case 'BIO':
        return 'assets/data/codigos/codigos_bio.csv';
      default:
        return 'assets/data/codigos/codigos_ipc.csv';
    }
  }

  Future<List<CodigoFlorestal>> carregarCodigos(String tipoAtividade) async {
    try {
      final rows = await _carregarLinhasCsv(tipoAtividade, comCabecalho: false);
      return rows.map((r) => CodigoFlorestal.fromCsv(r)).toList();
    } catch (e) {
      print("Erro lendo CSV de códigos: $e");
      return [];
    }
  }

  /// Retorna as linhas brutas (com cabeçalho) do CSV de códigos do tipo de
  /// atividade informado. Usado para montar a aba de legenda de códigos
  /// na exportação de parcelas.
  Future<List<List<dynamic>>> carregarLinhasParaExport(String tipoAtividade) async {
    try {
      return await _carregarLinhasCsv(tipoAtividade, comCabecalho: true);
    } catch (e) {
      print("Erro lendo CSV de códigos: $e");
      return [];
    }
  }

  Future<List<List<dynamic>>> _carregarLinhasCsv(String tipoAtividade, {required bool comCabecalho}) async {
    final path = _getFileName(tipoAtividade);
    final csvData = await rootBundle.loadString(path);

    // Lê o CSV
    List<List<dynamic>> rows = const CsvToListConverter(
      fieldDelimiter: ';',
      eol: '\n',
      shouldParseNumbers: false // Importante para ler 'N' como texto, não null
    ).convert(csvData);

    final temCabecalho = rows.isNotEmpty && rows[0][0].toString().toLowerCase().contains('sigla');
    if (temCabecalho && !comCabecalho) {
      rows.removeAt(0);
    }
    return rows;
  }
}

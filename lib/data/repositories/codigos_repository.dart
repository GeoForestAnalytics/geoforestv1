import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:geoforestv1/models/codigo_florestal_model.dart';

class CodigosRepository {
  
  String _getFileName(String tipoAtividade) {
    final t = tipoAtividade.toLowerCase();
    // Mapeamento Inteligente
    if (t.contains('ifc')) return 'assets/data/codigos/codigos_ifc.csv';
    if (t.contains('qualidade') || t.contains('ifq')) return 'assets/data/codigos/codigos_ifq.csv';
    if (t.contains('sobreviv') || t.contains('ifs')) return 'assets/data/codigos/codigos_ifs.csv';
    if (t.contains('biomassa') || t.contains('bio')) return 'assets/data/codigos/codigos_bio.csv';
    
    // Padrão (IPC ou qualquer outro)
    return 'assets/data/codigos/codigos_ipc.csv'; 
  }

  Future<List<CodigoFlorestal>> carregarCodigos(String tipoAtividade) async {
    try {
      final path = _getFileName(tipoAtividade);
      final csvData = await rootBundle.loadString(path);
      
      // Lê o CSV
      List<List<dynamic>> rows = const CsvToListConverter(
        fieldDelimiter: ';', 
        eol: '\n',
        shouldParseNumbers: false // Importante para ler 'N' como texto, não null
      ).convert(csvData);

      // Remove cabeçalho se a primeira coluna for "Sigla"
      if (rows.isNotEmpty && rows[0][0].toString().toLowerCase().contains('sigla')) {
        rows.removeAt(0);
      }

      return rows.map((r) => CodigoFlorestal.fromCsv(r)).toList();
    } catch (e) {
      print("Erro lendo CSV de códigos: $e");
      return [];
    }
  }
}
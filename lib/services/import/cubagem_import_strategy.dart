// lib/services/import/cubagem_import_strategy.dart

import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/cubagem_secao_model.dart';
import 'package:sqflite/sqflite.dart';
import 'csv_import_strategy.dart'; // Importa a base
import 'package:intl/intl.dart'; // <<< ADICIONAR ESTE IMPORT >>>

class CubagemImportStrategy extends BaseImportStrategy {
  CubagemImportStrategy({required super.txn, required super.projeto, super.nomeDoResponsavel});
  
  @override
  Future<ImportResult> processar(List<Map<String, dynamic>> dataRows) async {
    final result = ImportResult();
    final now = DateTime.now().toIso8601String();

    for (final row in dataRows) {
      result.linhasProcessadas++;
      
      final talhao = await getOrCreateHierarchy(row, result);
      if (talhao == null) continue;

      final idArvore = BaseImportStrategy.getValue(row, ['identificador_arvore', 'id_db_arvore']);
      if (idArvore == null) continue;

      CubagemArvore? arvoreCubagem = (await txn.query('cubagens_arvores', where: 'talhaoId = ? AND identificador = ?', whereArgs: [talhao.id!, idArvore])).map(CubagemArvore.fromMap).firstOrNull;
      
      if (arvoreCubagem == null) {
        
        // <<< INÍCIO DA CORREÇÃO >>>
        // Lógica para ler e interpretar a data do CSV
        final dataColetaStr = BaseImportStrategy.getValue(row, ['data_coleta']);
        DateTime? dataColetaFinal;
        if (dataColetaStr != null && dataColetaStr.isNotEmpty) {
          try { 
            // Tenta o formato completo primeiro
            dataColetaFinal = DateFormat('dd/MM/yyyy HH:mm').parseStrict(dataColetaStr); 
          } catch (_) {
            try {
              // Tenta apenas a data se o formato completo falhar
              dataColetaFinal = DateFormat('dd/MM/yyyy').parseStrict(dataColetaStr); 
            } catch (e) {
              dataColetaFinal = null; // Deixa nulo se não conseguir interpretar
            }
          }
        }
        // <<< FIM DA CORREÇÃO >>>
        
        final dadosArvore = CubagemArvore(
            talhaoId: talhao.id!, 
            idFazenda: talhao.fazendaId, 
            nomeFazenda: talhao.fazendaNome ?? 'N/A', 
            nomeTalhao: talhao.nome, 
            identificador: idArvore, 
            alturaTotal: double.tryParse(BaseImportStrategy.getValue(row, ['altura_total_m', 'altura_m'])?.replaceAll(',', '.') ?? '0') ?? 0, 
            valorCAP: double.tryParse(BaseImportStrategy.getValue(row, ['valor_cap', 'cap_cm'])?.replaceAll(',', '.') ?? '0') ?? 0, 
            alturaBase: double.tryParse(BaseImportStrategy.getValue(row, ['altura_base_m'])?.replaceAll(',', '.') ?? '0') ?? 0, 
            tipoMedidaCAP: BaseImportStrategy.getValue(row, ['tipo_medida_cap']) ?? 'fita', 
            classe: BaseImportStrategy.getValue(row, ['classe']), isSynced: false,
            nomeLider: BaseImportStrategy.getValue(row, ['lider_equipe']) ?? nomeDoResponsavel,
            dataColeta: dataColetaFinal // <-- Passa a data lida para o objeto
        );
        final map = dadosArvore.toMap();
        map['lastModified'] = now;
        final cubagemId = await txn.insert('cubagens_arvores', map);
        arvoreCubagem = dadosArvore.copyWith(id: cubagemId);
        result.cubagensCriadas++;
      }
      
      final alturaMedicaoStr = BaseImportStrategy.getValue(row, ['altura_medicao_secao_m', 'altura_medicao_m']);
      if (alturaMedicaoStr != null) {
          final alturaMedicao = double.tryParse(alturaMedicaoStr.replaceAll(',', '.')) ?? -1;
          if (alturaMedicao >= 0) {
              final novaSecao = CubagemSecao(
                  cubagemArvoreId: arvoreCubagem.id!, alturaMedicao: alturaMedicao, 
                  circunferencia: double.tryParse(BaseImportStrategy.getValue(row, ['circunferencia_secao_cm', 'circunferencia_cm'])?.replaceAll(',', '.') ?? '0') ?? 0, 
                  casca1_mm: double.tryParse(BaseImportStrategy.getValue(row, ['casca1_mm'])?.replaceAll(',', '.') ?? '0') ?? 0, 
                  casca2_mm: double.tryParse(BaseImportStrategy.getValue(row, ['casca2_mm'])?.replaceAll(',', '.') ?? '0') ?? 0
              );
              final secaoMap = novaSecao.toMap();
              secaoMap['lastModified'] = now;
              await txn.insert('cubagens_secoes', secaoMap, conflictAlgorithm: ConflictAlgorithm.replace);
              result.secoesCriadas++;
          }
      }
    }
    return result;
  }
}
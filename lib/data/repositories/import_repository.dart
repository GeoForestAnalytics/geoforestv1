// lib/data/repositories/import_repository.dart

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';

// Repositórios
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';

// Modelos
import 'package:geoforestv1/models/projeto_model.dart';

// Importa as estratégias
import 'package:geoforestv1/services/import/csv_import_strategy.dart';
import 'package:geoforestv1/services/import/planejamento_import_strategy.dart';
import 'package:geoforestv1/services/import/inventario_import_strategy.dart';
import 'package:geoforestv1/services/import/cubagem_import_strategy.dart';
import 'package:geoforestv1/services/import/planejamento_cubagem_import_strategy.dart';

enum TipoImportacao { inventario, cubagem, planejamento, planejamentoCubagem, desconhecido }

class ImportRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ProjetoRepository _projetoRepository = ProjetoRepository();
  
  Future<String> importarProjetoCompleto(String fileContent) async {
    return "Funcionalidade a ser revisada";
  }

  /// Identifica o tipo de arquivo e retorna a estratégia de importação correta.
  (CsvImportStrategy?, TipoImportacao) _getImportStrategy({
    required List<String> headers,
    required Transaction txn,
    required Projeto projeto,
    String? nomeDoResponsavel,
  }) {
    // Detecção flexível de cabeçalhos
    bool hasTreeData = headers.contains('cap_cm') || headers.contains('cap') || headers.contains('cod_1') || headers.contains('codigo_arvore');
    bool hasCubingMeasurementData = headers.contains('circunferencia_secao_cm') || headers.contains('circunferencia_cm');
    bool hasPlanningData = headers.contains('medir ?') || (headers.contains('long (x)') && headers.contains('lat (y)'));
    bool hasCubingIdentifier = headers.contains('identificador_arvore');

    // 1. É um PLANO DE CUBAGEM?
    if (hasCubingIdentifier && hasPlanningData && !hasCubingMeasurementData) {
      return (PlanejamentoCubagemImportStrategy(txn: txn, projeto: projeto, nomeDoResponsavel: nomeDoResponsavel), TipoImportacao.planejamentoCubagem);
    }
    
    // 2. É um PLANO DE AMOSTRAGEM (parcelas)?
    if (hasPlanningData && !hasTreeData && !hasCubingMeasurementData) {
      return (PlanejamentoImportStrategy(txn: txn, projeto: projeto, nomeDoResponsavel: nomeDoResponsavel), TipoImportacao.planejamento);
    } 
    
    // 3. É um INVENTÁRIO já coletado?
    if (hasTreeData) {
      return (InventarioImportStrategy(txn: txn, projeto: projeto, nomeDoResponsavel: nomeDoResponsavel), TipoImportacao.inventario);
    } 
    
    // 4. É uma CUBAGEM já coletada?
    if (hasCubingMeasurementData) {
      return (CubagemImportStrategy(txn: txn, projeto: projeto, nomeDoResponsavel: nomeDoResponsavel), TipoImportacao.cubagem);
    }

    return (null, TipoImportacao.desconhecido);
  }

  /// Função principal que coordena a importação.
  Future<String> importarCsvUniversal({
    required String csvContent,
    required int projetoIdAlvo,
  }) async {
    final Projeto? projeto = await _projetoRepository.getProjetoById(projetoIdAlvo);
    if (projeto == null) return "Erro Crítico: O projeto de destino não foi encontrado.";
    if (csvContent.isEmpty) return "Erro: O arquivo CSV está vazio.";
    
    final firstLine = csvContent.split('\n').first;
    final commaCount = ','.allMatches(firstLine).length;
    final semicolonCount = ';'.allMatches(firstLine).length;
    final tabCount = '\t'.allMatches(firstLine).length;
    
    String detectedDelimiter = ';';
    if (commaCount > semicolonCount && commaCount > tabCount) detectedDelimiter = ',';
    else if (tabCount > semicolonCount && tabCount > commaCount) detectedDelimiter = '\t';
    
    final List<List<dynamic>> rows = CsvToListConverter(
      fieldDelimiter: detectedDelimiter, 
      eol: '\n', 
      allowInvalid: true
    ).convert(csvContent);
    
    if (rows.length < 2) return "Erro: O arquivo CSV está vazio ou contém apenas o cabeçalho.";
    
    final headers = rows.first.map((h) => h.toString().trim().toLowerCase()).toList();
    final dataRows = rows.sublist(1)
      .where((row) => row.any((cell) => cell != null && cell.toString().trim().isNotEmpty))
      .map((row) => Map<String, dynamic>.fromIterables(headers, row))
      .toList();

    try {
      final prefs = await SharedPreferences.getInstance();
      String? nomeDoResponsavel = prefs.getString('nome_lider');
      if (nomeDoResponsavel == null || nomeDoResponsavel.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          nomeDoResponsavel = user.displayName ?? user.email;
        }
      }
      
      ImportResult finalResult = ImportResult();
      TipoImportacao tipoArquivo = TipoImportacao.desconhecido;

      final db = await _dbHelper.database;
      await db.transaction((txn) async {
        final (strategy, tipo) = _getImportStrategy(
          headers: headers,
          txn: txn,
          projeto: projeto,
          nomeDoResponsavel: nomeDoResponsavel
        );
        
        tipoArquivo = tipo;
        if (strategy == null) {
          throw Exception("Formato do CSV não reconhecido. Verifique as colunas do cabeçalho.");
        }

        finalResult = await strategy.processar(dataRows);
      });

      // Relatório final baseado no tipo detectado
      String report;
      if (tipoArquivo == TipoImportacao.planejamento) {
        report = "Importação de Plano de Amostragem Concluída!\n\n"
                 "Linhas no arquivo: ${finalResult.linhasProcessadas}\n"
                 "Parcelas ignoradas (Medir != SIM): ${finalResult.parcelasIgnoradas}\n\n"
                 "Itens Criados no Banco:\n"
                 " - Atividades: ${finalResult.atividadesCriadas}\n"
                 " - Fazendas: ${finalResult.fazendasCriadas}\n"
                 " - Talhões: ${finalResult.talhoesCriados}\n"
                 " - Parcelas: ${finalResult.parcelasCriadas}";
      } else if (tipoArquivo == TipoImportacao.planejamentoCubagem) {
        report = "Importação de Plano de Cubagem Concluída!\n\n"
                 "Linhas no arquivo: ${finalResult.linhasProcessadas}\n"
                 "Árvores ignoradas (Medir != SIM): ${finalResult.parcelasIgnoradas}\n\n"
                 "Itens Criados no Banco:\n"
                 " - Atividades: ${finalResult.atividadesCriadas}\n"
                 " - Fazendas: ${finalResult.fazendasCriadas}\n"
                 " - Talhões: ${finalResult.talhoesCriados}\n"
                 " - Árvores de Cubagem (placeholders): ${finalResult.cubagensCriadas}";
      } else {
        report = "Importação Concluída para '${projeto.nome}'!\n\n"
                 "Linhas: ${finalResult.linhasProcessadas}\n"
                 "Atividades Novas: ${finalResult.atividadesCriadas}\n"
                 "Fazendas Novas: ${finalResult.fazendasCriadas}\n"
                 "Talhões Novos: ${finalResult.talhoesCriados}\n"
                 "Parcelas Novas/Atualizadas: ${finalResult.parcelasCriadas}/${finalResult.parcelasAtualizadas}\n"
                 "Árvores Inseridas: ${finalResult.arvoresCriadas}\n"
                 "Cubagens Novas/Atualizadas: ${finalResult.cubagensCriadas}/${finalResult.cubagensAtualizadas}\n"
                 "Seções Inseridas: ${finalResult.secoesCriadas}";
      }
      return report;

    } catch(e, s) {
      debugPrint("Erro CRÍTICO na importação universal: $e\n$s");
      return "Ocorreu um erro grave durante a importação. Erro: ${e.toString()}";
    }
  }
}
// lib/data/repositories/import_repository.dart (VERSÃO FINAL COM CUBAGEM)


import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';


// Repositórios
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';

// Modelos
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/cubagem_arvore_model.dart';
import 'package:geoforestv1/models/cubagem_secao_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';

enum TipoImportacao { inventario, cubagem, desconhecido }

class ImportRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final ProjetoRepository _projetoRepository = ProjetoRepository();

  Future<String> importarProjetoCompleto(String fileContent) async {
    // ... (seu código de importação GeoJSON permanece aqui)
    return "Funcionalidade a ser revisada";
  }

  Future<String> importarCsvUniversal(String csvContent, {required int projetoIdAlvo}) async {
    final db = await _dbHelper.database;
    int linhasProcessadas = 0, atividadesCriadas = 0, fazendasCriadas = 0, talhoesCriados = 0;
    int parcelasCriadas = 0, arvoresCriadas = 0, cubagensCriadas = 0, secoesCriadas = 0;

    final Projeto? projeto = await _projetoRepository.getProjetoById(projetoIdAlvo);
    if (projeto == null) {
      return "Erro Crítico: O projeto de destino selecionado não foi encontrado.";
    }
    
    if (csvContent.isEmpty) return "Erro: O arquivo CSV está vazio.";
    
    // Lógica de detecção de delimitador (permanece a mesma)
    final firstLine = csvContent.split('\n').first;
    final commaCount = ','.allMatches(firstLine).length;
    final semicolonCount = ';'.allMatches(firstLine).length;
    final tabCount = '\t'.allMatches(firstLine).length;
    String detectedDelimiter = ',';
    if (semicolonCount > commaCount && semicolonCount > tabCount) {
      detectedDelimiter = ';';
    } else if (tabCount > commaCount && tabCount > semicolonCount) {
      detectedDelimiter = '\t';
    }
    
    final List<List<dynamic>> rows = CsvToListConverter(fieldDelimiter: detectedDelimiter, eol: '\n', allowInvalid: true).convert(csvContent);
    if (rows.length < 2) return "Erro: O arquivo CSV está vazio ou contém apenas o cabeçalho.";
    final headers = rows.first.map((h) => h.toString().trim().toLowerCase()).toList();
    final dataRows = rows.sublist(1).where((row) => row.any((cell) => cell != null && cell.toString().trim().isNotEmpty)).map((row) => Map<String, dynamic>.fromIterables(headers, row)).toList();

    String? getValue(Map<String, dynamic> row, List<String> possibleKeys) {
      for (final key in possibleKeys) {
        if (row.containsKey(key.toLowerCase())) {
          final value = row[key.toLowerCase()]?.toString();
          return (value == null || value.toLowerCase() == 'null' || value.trim().isEmpty) ? null : value;
        }
      }
      return null;
    }

    try {
      await db.transaction((txn) async {
        for (final row in dataRows) {
          linhasProcessadas++;
          
          final tipoAtividadeStr = getValue(row, ['atividade', 'tipo_atividade'])?.toUpperCase();
          if (tipoAtividadeStr == null) continue;

          // 1. Atividade
          Atividade? atividade = (await txn.query('atividades', where: 'projetoId = ? AND tipo = ?', whereArgs: [projeto.id!, tipoAtividadeStr])).map(Atividade.fromMap).firstOrNull;
          if (atividade == null) {
              atividade = Atividade(projetoId: projeto.id!, tipo: tipoAtividadeStr, descricao: 'Importado via CSV', dataCriacao: DateTime.now());
              final aId = await txn.insert('atividades', atividade.toMap());
              atividade = atividade.copyWith(id: aId);
              atividadesCriadas++;
          }

          // 2. Fazenda
          final nomeFazenda = getValue(row, ['fazenda', 'nome_fazenda']) ?? 'Fazenda Padrão';
          final idFazenda = getValue(row, ['codigo_fazenda', 'id_fazenda']) ?? nomeFazenda;
          Fazenda? fazenda = (await txn.query('fazendas', where: 'id = ? AND atividadeId = ?', whereArgs: [idFazenda, atividade.id!])).map(Fazenda.fromMap).firstOrNull;
          if (fazenda == null) {
              fazenda = Fazenda(id: idFazenda, atividadeId: atividade.id!, nome: nomeFazenda, municipio: getValue(row, ['municipio']) ?? 'N/I', estado: getValue(row, ['estado']) ?? 'N/I');
              await txn.insert('fazendas', fazenda.toMap());
              fazendasCriadas++;
          }

          // 3. Talhão
          final nomeTalhao = getValue(row, ['talhao', 'nome_talhao']) ?? 'Talhão Padrão';
          Talhao? talhao = (await txn.query('talhoes', where: 'nome = ? AND fazendaId = ? AND fazendaAtividadeId = ?', whereArgs: [nomeTalhao, fazenda.id, fazenda.atividadeId])).map(Talhao.fromMap).firstOrNull;
          if(talhao == null) {
              talhao = Talhao(fazendaId: fazenda.id, fazendaAtividadeId: fazenda.atividadeId, nome: nomeTalhao);
              final tId = await txn.insert('talhoes', talhao.toMap());
              talhao = talhao.copyWith(id: tId);
              talhoesCriados++;
          }
          
          TipoImportacao tipoLinha = ['IPC', 'IFC', 'AUD', 'IFS', 'BIO'].contains(tipoAtividadeStr) ? TipoImportacao.inventario : (tipoAtividadeStr == 'CUB' ? TipoImportacao.cubagem : TipoImportacao.desconhecido);

          // Lógica de Inventário
          if (tipoLinha == TipoImportacao.inventario) {
              final idParcelaColeta = getValue(row, ['id_coleta_parcela', 'id_parcela']);
              if (idParcelaColeta == null) continue;
              Parcela? parcela = (await txn.query('parcelas', where: 'idParcela = ? AND talhaoId = ?', whereArgs: [idParcelaColeta, talhao.id!])).map(Parcela.fromMap).firstOrNull;
              int parcelaDbId;
              if(parcela == null) {
                  final novaParcela = Parcela(
                      talhaoId: talhao.id!, idParcela: idParcelaColeta,
                      areaMetrosQuadrados: double.tryParse(getValue(row, ['area_m2'])?.replaceAll(',', '.') ?? '0') ?? 0,
                      status: StatusParcela.concluida, dataColeta: DateTime.now(),
                      nomeFazenda: fazenda.nome, nomeTalhao: talhao.nome, isSynced: false, projetoId: projeto.id 
                  );
                  parcelaDbId = await txn.insert('parcelas', novaParcela.toMap());
                  parcelasCriadas++;
              } else {
                  parcelaDbId = parcela.dbId!;
              }
              final codigoStr = getValue(row, ['codigo_arvore', 'codigo']);
              if (codigoStr != null) {
                  final dominante = getValue(row, ['dominante'])?.toLowerCase() == 'sim' || getValue(row, ['dominante'])?.toLowerCase() == 'true';
                  final novaArvore = Arvore(cap: double.tryParse(getValue(row, ['cap_cm'])?.replaceAll(',', '.') ?? '0.0') ?? 0.0, altura: double.tryParse(getValue(row, ['altura_m'])?.replaceAll(',', '.') ?? ''), linha: int.tryParse(getValue(row, ['linha']) ?? '0') ?? 0, posicaoNaLinha: int.tryParse(getValue(row, ['posicao_na_linha']) ?? '0') ?? 0, dominante: dominante, codigo: Codigo.values.firstWhere((e) => e.name.toLowerCase() == codigoStr.toLowerCase(), orElse: () => Codigo.normal), fimDeLinha: false);
                  final arvoreMap = novaArvore.toMap();
                  arvoreMap['parcelaId'] = parcelaDbId;
                  await txn.insert('arvores', arvoreMap);
                  arvoresCriadas++;
              }
          } 
          // ===================================================================
          // <<< LÓGICA DE CUBAGEM REINTEGRADA E CORRIGIDA >>>
          // ===================================================================
          else if (tipoLinha == TipoImportacao.cubagem) {
              final idArvore = getValue(row, ['identificador_arvore', 'id_db_arvore']);
              if (idArvore == null) continue;

              CubagemArvore? arvoreCubagem = (await txn.query('cubagens_arvores', where: 'talhaoId = ? AND identificador = ?', whereArgs: [talhao.id!, idArvore])).map(CubagemArvore.fromMap).firstOrNull;

              if (arvoreCubagem == null) {
                arvoreCubagem = CubagemArvore(
                    talhaoId: talhao.id!, idFazenda: fazenda.id, nomeFazenda: fazenda.nome, nomeTalhao: talhao.nome, 
                    identificador: idArvore, 
                    alturaTotal: double.tryParse(getValue(row, ['altura_total_m'])?.replaceAll(',', '.') ?? '0') ?? 0, 
                    valorCAP: double.tryParse(getValue(row, ['valor_cap', 'cap_cm'])?.replaceAll(',', '.') ?? '0') ?? 0, 
                    alturaBase: double.tryParse(getValue(row, ['altura_base_m'])?.replaceAll(',', '.') ?? '0') ?? 0, 
                    tipoMedidaCAP: getValue(row, ['tipo_medida_cap']) ?? 'fita', 
                    isSynced: false
                );
                final cubagemId = await txn.insert('cubagens_arvores', arvoreCubagem.toMap());
                arvoreCubagem = arvoreCubagem.copyWith(id: cubagemId);
                cubagensCriadas++;
              }

              final alturaMedicaoStr = getValue(row, ['altura_medicao_secao_m', 'altura_medicao_m']);
              if (alturaMedicaoStr != null) {
                  final alturaMedicao = double.tryParse(alturaMedicaoStr.replaceAll(',', '.')) ?? -1;
                  if (alturaMedicao >= 0) {
                      final novaSecao = CubagemSecao(
                          cubagemArvoreId: arvoreCubagem.id!, 
                          alturaMedicao: alturaMedicao, 
                          circunferencia: double.tryParse(getValue(row, ['circunferencia_secao_cm', 'circunferencia_cm'])?.replaceAll(',', '.') ?? '0') ?? 0, 
                          casca1_mm: double.tryParse(getValue(row, ['casca1_mm'])?.replaceAll(',', '.') ?? '0') ?? 0, 
                          casca2_mm: double.tryParse(getValue(row, ['casca2_mm'])?.replaceAll(',', '.') ?? '0') ?? 0
                      );
                      await txn.insert('cubagens_secoes', novaSecao.toMap());
                      secoesCriadas++;
                  }
              }
          }
        }
      });
      return "Importação Concluída para o projeto '${projeto.nome}'!\n\nLinhas Processadas: $linhasProcessadas\nAtividades Novas: $atividadesCriadas\nFazendas Novas: $fazendasCriadas\nTalhões Novos: $talhoesCriados\nParcelas Novas: $parcelasCriadas\nÁrvores Inseridas: $arvoresCriadas\nCubagens Inseridas: $cubagensCriadas\nSeções Inseridas: $secoesCriadas";
    } catch(e, s) {
      debugPrint("Erro CRÍTICO na importação universal: $e\n$s");
      return "Ocorreu um erro grave durante a importação. Verifique o console de debug. Erro: ${e.toString()}";
    }
  }
}
// lib/data/repositories/import_repository.dart

import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
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

  /// Importa uma estrutura completa de projeto a partir de um arquivo GeoJSON.
  Future<String> importarProjetoCompleto(String fileContent) async {
    final db = await _dbHelper.database;
    int projetosCriados = 0;
    int atividadesCriadas = 0;
    int fazendasCriadas = 0;
    int talhoesCriados = 0;
    int parcelasCriadas = 0;

    try {
      final Map<String, dynamic> geoJson = jsonDecode(fileContent);
      final List<dynamic> features = geoJson['features'];
      
      await db.transaction((txn) async {
        for (final feature in features) {
          final properties = feature['properties'];
          
          Projeto? projeto = await txn.query('projetos', where: 'nome = ?', whereArgs: [properties['projeto_nome']]).then((list) => list.isEmpty ? null : Projeto.fromMap(list.first));
          if (projeto == null) {
            projeto = Projeto(nome: properties['projeto_nome'], empresa: properties['empresa'], responsavel: properties['responsavel'], dataCriacao: DateTime.now());
            final projetoId = await txn.insert('projetos', projeto.toMap());
            projeto = projeto.copyWith(id: projetoId);
            projetosCriados++;
          }

          Atividade? atividade = await txn.query('atividades', where: 'tipo = ? AND projetoId = ?', whereArgs: [properties['atividade_tipo'], projeto.id]).then((list) => list.isEmpty ? null : Atividade.fromMap(list.first));
          if (atividade == null) {
            atividade = Atividade(projetoId: projeto.id!, tipo: properties['atividade_tipo'], descricao: properties['atividade_descricao'] ?? '', dataCriacao: DateTime.now());
            final atividadeId = await txn.insert('atividades', atividade.toMap());
            atividade = atividade.copyWith(id: atividadeId);
            atividadesCriadas++;
          }
          
          Fazenda? fazenda = await txn.query('fazendas', where: 'id = ? AND atividadeId = ?', whereArgs: [properties['fazenda_id'], atividade.id]).then((list) => list.isEmpty ? null : Fazenda.fromMap(list.first));
          if (fazenda == null) {
            fazenda = Fazenda(id: properties['fazenda_id'], atividadeId: atividade.id!, nome: properties['fazenda_nome'], municipio: properties['municipio'], estado: properties['estado']);
            await txn.insert('fazendas', fazenda.toMap());
            fazendasCriadas++;
          }
          
          Talhao? talhao = await txn.query('talhoes', where: 'nome = ? AND fazendaId = ? AND fazendaAtividadeId = ?', whereArgs: [properties['talhao_nome'], fazenda.id, fazenda.atividadeId]).then((list) => list.isEmpty ? null : Talhao.fromMap(list.first));
          if (talhao == null) {
            talhao = Talhao(fazendaId: fazenda.id, fazendaAtividadeId: fazenda.atividadeId, nome: properties['talhao_nome'], especie: properties['especie'], areaHa: properties['area_ha'], idadeAnos: properties['idade_anos'], espacamento: properties['espacam']);
            final talhaoId = await txn.insert('talhoes', talhao.toMap());
            talhao = talhao.copyWith(id: talhaoId);
            talhoesCriados++;
          }
          
          Parcela? parcela = await txn.query('parcelas', where: 'idParcela = ? AND talhaoId = ?', whereArgs: [properties['parcela_id_plano'], talhao.id]).then((list) => list.isEmpty ? null : Parcela.fromMap(list.first));
          if (parcela == null) {
            final geometry = feature['geometry'];
            parcela = Parcela(talhaoId: talhao.id!, idParcela: properties['parcela_id_plano'], areaMetrosQuadrados: properties['area_m2'] ?? 0.0, status: StatusParcela.pendente, dataColeta: DateTime.now(), latitude: geometry != null ? geometry['coordinates'][0][0][1] : null, longitude: geometry != null ? geometry['coordinates'][0][0][0] : null, nomeFazenda: fazenda.nome, nomeTalhao: talhao.nome);
            await txn.insert('parcelas', parcela.toMap());
            parcelasCriadas++;
          }
        }
      });
      return "Importação concluída!\nProjetos: $projetosCriados\nAtividades: $atividadesCriadas\nFazendas: $fazendasCriadas\nTalhões: $talhoesCriados\nParcelas: $parcelasCriadas";
    } catch (e) {
      debugPrint("Erro ao importar projeto: $e");
      return "Erro ao importar: O arquivo pode estar mal formatado ou os dados são inválidos. ($e)";
    }
  }

  /// Importa dados de um CSV flexível para um projeto alvo.
  Future<String> importarCsvUniversal(String csvContent, {required int projetoIdAlvo}) async {
    final db = await _dbHelper.database;
    int linhasProcessadas = 0, atividadesCriadas = 0, fazendasCriadas = 0, talhoesCriados = 0;
    int parcelasCriadas = 0, arvoresCriadas = 0, cubagensCriadas = 0, secoesCriadas = 0;

    final Projeto? projeto = await _projetoRepository.getProjetoById(projetoIdAlvo);
    if (projeto == null) {
      return "Erro Crítico: O projeto de destino selecionado não foi encontrado no banco de dados.";
    }
    
    if (csvContent.isEmpty) return "Erro: O arquivo CSV está vazio.";
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
    debugPrint("Separador universal detectado: '$detectedDelimiter'");
    
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

    Map<String, Atividade> atividadeCache = {};
    Map<String, Fazenda> fazendaCache = {};
    Map<String, Talhao> talhaoCache = {};
    Map<String, int> parcelaIdCache = {};
    Map<String, CubagemArvore> cubagemCache = {};

    try {
      await db.transaction((txn) async {
        for (final row in dataRows) {
          linhasProcessadas++;
          
          final tipoAtividadeStr = getValue(row, ['atividade', 'tipo_atividade'])?.toUpperCase();
          if (tipoAtividadeStr == null) continue;
          
          final tipoAtividadeKey = '${projeto.id}-$tipoAtividadeStr';
          Atividade atividade;
          if(atividadeCache.containsKey(tipoAtividadeKey)) {
            atividade = atividadeCache[tipoAtividadeKey]!;
          } else {
              final aList = await txn.query('atividades', where: 'projetoId = ? AND tipo = ?', whereArgs: [projeto.id!, tipoAtividadeStr]);
              if(aList.isNotEmpty) {
                  atividade = Atividade.fromMap(aList.first);
              } else {
                  atividade = Atividade(projetoId: projeto.id!, tipo: tipoAtividadeStr, descricao: 'Importado via CSV', dataCriacao: DateTime.now());
                  final aId = await txn.insert('atividades', atividade.toMap());
                  atividade = atividade.copyWith(id: aId);
                  atividadesCriadas++;
              }
              atividadeCache[tipoAtividadeKey] = atividade;
          }

          final nomeFazenda = getValue(row, ['fazenda', 'nome_fazenda']) ?? 'Fazenda Padrão';
          final idFazenda = getValue(row, ['codigo_fazenda', 'id_fazenda']) ?? nomeFazenda;
          final fazendaKey = '${atividade.id}-$idFazenda';
          
          Fazenda fazenda;
          if(fazendaCache.containsKey(fazendaKey)) {
              fazenda = fazendaCache[fazendaKey]!;
          } else {
              final fList = await txn.query('fazendas', where: 'id = ? AND atividadeId = ?', whereArgs: [idFazenda, atividade.id!]);
              if(fList.isNotEmpty) {
                  fazenda = Fazenda.fromMap(fList.first);
              } else {
                  fazenda = Fazenda(id: idFazenda, atividadeId: atividade.id!, nome: nomeFazenda, municipio: getValue(row, ['municipio']) ?? 'N/I', estado: getValue(row, ['estado']) ?? 'N/I');
                  await txn.insert('fazendas', fazenda.toMap());
                  fazendasCriadas++;
              }
              fazendaCache[fazendaKey] = fazenda;
          }
          
          final nomeTalhao = getValue(row, ['talhao', 'nome_talhao']) ?? 'Talhão Padrão';
          final talhaoKey = '${fazenda.id}-${fazenda.atividadeId}-$nomeTalhao';
          
          Talhao talhao;
          if(talhaoCache.containsKey(talhaoKey)) {
              talhao = talhaoCache[talhaoKey]!;
          } else {
              final tList = await txn.query('talhoes', where: 'nome = ? AND fazendaId = ? AND fazendaAtividadeId = ?', whereArgs: [nomeTalhao, fazenda.id, fazenda.atividadeId]);
              if (tList.isNotEmpty) {
                  talhao = Talhao.fromMap(tList.first);
              } else {
                  talhao = Talhao(fazendaId: fazenda.id, fazendaAtividadeId: fazenda.atividadeId, nome: nomeTalhao);
                  final tId = await txn.insert('talhoes', talhao.toMap());
                  talhao = talhao.copyWith(id: tId);
                  talhoesCriados++;
              }
              talhaoCache[talhaoKey] = talhao;
          }
          
          TipoImportacao tipoLinha = ['IPC', 'IFC', 'AUD', 'IFS', 'BIO'].contains(tipoAtividadeStr) ? TipoImportacao.inventario : (tipoAtividadeStr == 'CUB' ? TipoImportacao.cubagem : TipoImportacao.desconhecido);

          if (tipoLinha == TipoImportacao.inventario) {
              final idParcelaColeta = getValue(row, ['id_coleta_parcela', 'id_parcela']);
              if (idParcelaColeta == null) continue;

              final parcelaKey = '${talhao.id}-$idParcelaColeta';
              int parcelaDbId;

              if (parcelaIdCache.containsKey(parcelaKey)) {
                  parcelaDbId = parcelaIdCache[parcelaKey]!;
              } else {
                  final parcelasDoBanco = await txn.query('parcelas', where: 'idParcela = ? AND talhaoId = ?', whereArgs: [idParcelaColeta, talhao.id!]);
                  if (parcelasDoBanco.isEmpty) {
                      final novaParcela = Parcela(
                          talhaoId: talhao.id!,
                          idParcela: idParcelaColeta,
                          areaMetrosQuadrados: double.tryParse(getValue(row, ['area_m2'])?.replaceAll(',', '.') ?? '0') ?? 0,
                          status: StatusParcela.concluida,
                          dataColeta: DateTime.now(),
                          nomeFazenda: fazenda.nome,
                          nomeTalhao: talhao.nome,
                          isSynced: false,
                          projetoId: projeto.id 
                      );
                      parcelaDbId = await txn.insert('parcelas', novaParcela.toMap());
                      parcelasCriadas++;
                  } else {
                      parcelaDbId = Parcela.fromMap(parcelasDoBanco.first).dbId!;
                  }
                  parcelaIdCache[parcelaKey] = parcelaDbId;
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

          } else if (tipoLinha == TipoImportacao.cubagem) {
              final idArvore = getValue(row, ['identificador_arvore', 'id_db_arvore']);
              if (idArvore == null) continue;

              final arvoreKey = '${talhao.id}-$idArvore';
              CubagemArvore arvoreCubagem;

              if (cubagemCache.containsKey(arvoreKey)) {
                  arvoreCubagem = cubagemCache[arvoreKey]!;
              } else {
                  final cubagensDoBanco = await txn.query('cubagens_arvores', where: 'talhaoId = ? AND identificador = ?', whereArgs: [talhao.id!, idArvore]);
                  if (cubagensDoBanco.isEmpty) {
                    arvoreCubagem = CubagemArvore(talhaoId: talhao.id!, idFazenda: fazenda.id, nomeFazenda: fazenda.nome, nomeTalhao: talhao.nome, identificador: idArvore, alturaTotal: double.tryParse(getValue(row, ['altura_total_m'])?.replaceAll(',', '.') ?? '0') ?? 0, valorCAP: double.tryParse(getValue(row, ['valor_cap', 'cap_cm'])?.replaceAll(',', '.') ?? '0') ?? 0, alturaBase: double.tryParse(getValue(row, ['altura_base_m'])?.replaceAll(',', '.') ?? '0') ?? 0, tipoMedidaCAP: getValue(row, ['tipo_medida_cap']) ?? 'fita', isSynced: false);
                    final cubagemId = await txn.insert('cubagens_arvores', arvoreCubagem.toMap());
                    arvoreCubagem = arvoreCubagem.copyWith(id: cubagemId);
                    cubagensCriadas++;
                  } else {
                    arvoreCubagem = CubagemArvore.fromMap(cubagensDoBanco.first);
                  }
                  cubagemCache[arvoreKey] = arvoreCubagem;
              }

              final alturaMedicaoStr = getValue(row, ['altura_medicao_secao_m', 'altura_medicao_m']);
              if (alturaMedicaoStr != null) {
                  final alturaMedicao = double.tryParse(alturaMedicaoStr.replaceAll(',', '.')) ?? -1;
                  if (alturaMedicao >= 0) {
                      final novaSecao = CubagemSecao(cubagemArvoreId: arvoreCubagem.id!, alturaMedicao: alturaMedicao, circunferencia: double.tryParse(getValue(row, ['circunferencia_secao_cm', 'circunferencia_cm'])?.replaceAll(',', '.') ?? '0') ?? 0, casca1_mm: double.tryParse(getValue(row, ['casca1_mm'])?.replaceAll(',', '.') ?? '0') ?? 0, casca2_mm: double.tryParse(getValue(row, ['casca2_mm'])?.replaceAll(',', '.') ?? '0') ?? 0);
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
      return "Ocorreu um erro grave durante a importação. Verifique o console de debug para mais detalhes. Erro: ${e.toString()}";
    }
  }
}
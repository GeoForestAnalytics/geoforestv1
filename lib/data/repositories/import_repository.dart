// lib/data/repositories/import_repository.dart (VERSÃO FINAL E COMPLETA)

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';

// Repositórios e Constantes
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';
import 'package:geoforestv1/utils/constants.dart';

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
    return "Funcionalidade a ser revisada";
  }

  Future<String> importarCsvUniversal(String csvContent, {required int projetoIdAlvo}) async {
    final db = await _dbHelper.database;
    int linhasProcessadas = 0, atividadesCriadas = 0, fazendasCriadas = 0, talhoesCriados = 0;
    int parcelasCriadas = 0, arvoresCriadas = 0, cubagensCriadas = 0, secoesCriadas = 0;
    int parcelasAtualizadas = 0, cubagensAtualizadas = 0;

    final Projeto? projeto = await _projetoRepository.getProjetoById(projetoIdAlvo);
    if (projeto == null) return "Erro Crítico: O projeto de destino não foi encontrado.";
    if (csvContent.isEmpty) return "Erro: O arquivo CSV está vazio.";
    
    final firstLine = csvContent.split('\n').first;
    final commaCount = ','.allMatches(firstLine).length;
    final semicolonCount = ';'.allMatches(firstLine).length;
    final tabCount = '\t'.allMatches(firstLine).length;
    String detectedDelimiter = ',';
    if (semicolonCount > commaCount && semicolonCount > tabCount) detectedDelimiter = ';';
    else if (tabCount > commaCount && tabCount > semicolonCount) detectedDelimiter = '\t';
    
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
      final prefs = await SharedPreferences.getInstance();
      String? nomeDoResponsavel = prefs.getString('nome_lider');
      if (nomeDoResponsavel == null || nomeDoResponsavel.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          nomeDoResponsavel = user.displayName ?? user.email;
        }
      }

      await db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();
        
        for (final row in dataRows) {
          linhasProcessadas++;
          
          final tipoAtividadeStr = getValue(row, ['atividade', 'tipo_atividade'])?.toUpperCase();
          if (tipoAtividadeStr == null) continue;

          Atividade? atividade = (await txn.query('atividades', where: 'projetoId = ? AND tipo = ?', whereArgs: [projeto.id!, tipoAtividadeStr])).map(Atividade.fromMap).firstOrNull;
          if (atividade == null) {
              atividade = Atividade(projetoId: projeto.id!, tipo: tipoAtividadeStr, descricao: 'Importado via CSV', dataCriacao: DateTime.now());
              final map = atividade.toMap();
              map['lastModified'] = now;
              final aId = await txn.insert('atividades', map);
              atividade = atividade.copyWith(id: aId);
              atividadesCriadas++;
          }

          final nomeFazenda = getValue(row, ['fazenda', 'nome_fazenda']);
          if (nomeFazenda == null) continue;
          final idFazenda = getValue(row, ['codigo_fazenda', 'id_fazenda']) ?? nomeFazenda;
          Fazenda? fazenda = (await txn.query('fazendas', where: 'id = ? AND atividadeId = ?', whereArgs: [idFazenda, atividade.id!])).map(Fazenda.fromMap).firstOrNull;
          if (fazenda == null) {
              fazenda = Fazenda(id: idFazenda, atividadeId: atividade.id!, nome: nomeFazenda, municipio: getValue(row, ['municipio']) ?? 'N/I', estado: getValue(row, ['estado']) ?? 'N/I');
              final map = fazenda.toMap();
              map['lastModified'] = now;
              await txn.insert('fazendas', map);
              fazendasCriadas++;
          }

          final nomeTalhao = getValue(row, ['talhao', 'nome_talhao']);
          if (nomeTalhao == null) continue;
          Talhao? talhao = (await txn.query('talhoes', where: 'nome = ? AND fazendaId = ? AND fazendaAtividadeId = ?', whereArgs: [nomeTalhao, fazenda.id, fazenda.atividadeId])).map(Talhao.fromMap).firstOrNull;
          
          if(talhao == null) {
              talhao = Talhao(
                fazendaId: fazenda.id, 
                fazendaAtividadeId: fazenda.atividadeId, 
                nome: nomeTalhao, 
                projetoId: projeto.id,
                areaHa: double.tryParse(getValue(row, ['area_talhao_ha', 'area_talhão'])?.replaceAll(',', '.') ?? ''),
                especie: getValue(row, ['especie']),
                espacamento: getValue(row, ['espacamento', 'espacame']),
                idadeAnos: double.tryParse(getValue(row, ['idade_anos', 'idade'])?.replaceAll(',', '.') ?? ''),
              );
              final map = talhao.toMap();
              map['lastModified'] = now;
              final tId = await txn.insert('talhoes', map);
              talhao = talhao.copyWith(id: tId);
              talhoesCriados++;
          } else {
              final talhaoAtualizado = talhao.copyWith(
                areaHa: double.tryParse(getValue(row, ['area_talhao_ha', 'area_talhão'])?.replaceAll(',', '.') ?? talhao.areaHa?.toString() ?? ''),
                especie: getValue(row, ['especie']) ?? talhao.especie,
                espacamento: getValue(row, ['espacamento', 'espacame']) ?? talhao.espacamento,
                idadeAnos: double.tryParse(getValue(row, ['idade_anos', 'idade'])?.replaceAll(',', '.') ?? talhao.idadeAnos?.toString() ?? ''),
              );
              final map = talhaoAtualizado.toMap();
              map['lastModified'] = now;
              await txn.update('talhoes', map, where: 'id = ?', whereArgs: [talhao.id]);
          }
          
          final tipoLinha = ['IPC', 'IFC', 'AUD', 'IFS', 'BIO', 'IFQ'].any((e) => tipoAtividadeStr.contains(e)) ? TipoImportacao.inventario : (tipoAtividadeStr.contains('CUB') ? TipoImportacao.cubagem : TipoImportacao.desconhecido);

          if (tipoLinha == TipoImportacao.inventario) {
              final idParcelaColeta = getValue(row, ['id_coleta_parcela', 'id_parcela']);
              if (idParcelaColeta == null) continue;
              
              Parcela? parcela = (await txn.query('parcelas', where: 'idParcela = ? AND talhaoId = ?', whereArgs: [idParcelaColeta, talhao.id!])).map(Parcela.fromMap).firstOrNull;
              int parcelaDbId;

              if(parcela == null) {
                  double? latitudeFinal, longitudeFinal;
                  final latStr = getValue(row, ['latitude', 'lat']);
                  final lonStr = getValue(row, ['longitude', 'lon', 'lng']);
                  if (latStr != null && lonStr != null) {
                      latitudeFinal = double.tryParse(latStr.replaceAll(',', '.'));
                      longitudeFinal = double.tryParse(lonStr.replaceAll(',', '.'));
                  } else {
                      final eastingStr = getValue(row, ['easting', 'este']);
                      final northingStr = getValue(row, ['northing', 'norte']);
                      if (eastingStr != null && northingStr != null) {
                          final easting = double.tryParse(eastingStr.replaceAll(',', '.'));
                          final northing = double.tryParse(northingStr.replaceAll(',', '.'));
                          if (easting != null && northing != null) {
                              final nomeZona = prefs.getString('zona_utm_selecionada') ?? 'SIRGAS 2000 / UTM Zona 22S';
                              final codigoEpsg = zonasUtmSirgas2000[nomeZona] ?? 31982;
                              final projUTM = proj4.Projection.get('EPSG:$codigoEpsg') ?? proj4.Projection.parse(proj4Definitions[codigoEpsg]!);
                              final projWGS84 = proj4.Projection.get('EPSG:4326') ?? proj4.Projection.parse('+proj=longlat +datum=WGS84 +no_defs');
                              var pontoWGS84 = projUTM.transform(projWGS84, proj4.Point(x: easting, y: northing));
                              latitudeFinal = pontoWGS84.y;
                              longitudeFinal = pontoWGS84.x;
                          }
                      }
                  }

                  final statusStr = getValue(row, ['status_parcela']) ?? 'pendente';
                  final novaParcela = Parcela(
                      talhaoId: talhao.id!, 
                      idParcela: idParcelaColeta,
                      areaMetrosQuadrados: double.tryParse(getValue(row, ['area_m2'])?.replaceAll(',', '.') ?? '0.0') ?? 0.0,
                      status: StatusParcela.values.firstWhere((e) => e.name == statusStr, orElse: ()=> StatusParcela.pendente), 
                      dataColeta: DateTime.tryParse(getValue(row, ['data_coleta']) ?? ''),
                      nomeFazenda: fazenda.nome, 
                      nomeTalhao: talhao.nome, 
                      isSynced: false, 
                      projetoId: projeto.id,
                      latitude: latitudeFinal,
                      longitude: longitudeFinal,
                      largura: double.tryParse(getValue(row, ['largura_m'])?.replaceAll(',', '.') ?? ''),
                      comprimento: double.tryParse(getValue(row, ['comprimento_m'])?.replaceAll(',', '.') ?? ''),
                      raio: double.tryParse(getValue(row, ['raio_m'])?.replaceAll(',', '.') ?? ''),
                      observacao: getValue(row, ['observacao_parcela']),
                      nomeLider: getValue(row, ['lider_equipe']) ?? nomeDoResponsavel
                  );
                  final map = novaParcela.toMap();
                  map['lastModified'] = now;
                  parcelaDbId = await txn.insert('parcelas', map);
                  parcelasCriadas++;
              } else {
                  final map = parcela.toMap();
                  map['lastModified'] = now;
                  await txn.update('parcelas', map, where: 'id = ?', whereArgs: [parcela.dbId!]);
                  parcelaDbId = parcela.dbId!;
                  parcelasAtualizadas++;
              }

              final codigoStr = getValue(row, ['codigo_arvore', 'codigo']);
              if (codigoStr != null) {
                  final dominante = getValue(row, ['dominante'])?.toLowerCase() == 'sim' || getValue(row, ['dominante'])?.toLowerCase() == 'true';
                  final codigo2Str = getValue(row, ['codigo_arvore_2']);
                  
                  Codigo2? finalCodigo2;
                  if (codigo2Str != null) {
                      final matchingCodes = Codigo2.values.where((e) => e.name.toLowerCase() == codigo2Str.toLowerCase());
                      if (matchingCodes.isNotEmpty) {
                          finalCodigo2 = matchingCodes.first;
                      }
                  }

                  final novaArvore = Arvore(
                    cap: double.tryParse(getValue(row, ['cap_cm'])?.replaceAll(',', '.') ?? '0.0') ?? 0.0, 
                    altura: double.tryParse(getValue(row, ['altura_m'])?.replaceAll(',', '.') ?? ''), 
                    linha: int.tryParse(getValue(row, ['linha']) ?? '0') ?? 0, 
                    posicaoNaLinha: int.tryParse(getValue(row, ['posicao_na_linha']) ?? '0') ?? 0, 
                    dominante: dominante, 
                    codigo: Codigo.values.firstWhere((e) => e.name.toLowerCase() == codigoStr.toLowerCase(), orElse: () => Codigo.normal),
                    codigo2: finalCodigo2,
                    fimDeLinha: false
                  );
                  final arvoreMap = novaArvore.toMap();
                  arvoreMap['parcelaId'] = parcelaDbId;
                  arvoreMap['lastModified'] = now;
                  await txn.insert('arvores', arvoreMap);
                  arvoresCriadas++;
              }
          } 
          else if (tipoLinha == TipoImportacao.cubagem) {
              
              final idArvore = getValue(row, ['identificador_arvore', 'id_db_arvore']);
              if (idArvore == null) continue;

              CubagemArvore? arvoreCubagem = (await txn.query('cubagens_arvores', where: 'talhaoId = ? AND identificador = ?', whereArgs: [talhao.id!, idArvore])).map(CubagemArvore.fromMap).firstOrNull;
              
              if (arvoreCubagem == null) {
                final dadosArvore = CubagemArvore(
                    talhaoId: talhao.id!, 
                    idFazenda: fazenda.id, 
                    nomeFazenda: fazenda.nome, 
                    nomeTalhao: talhao.nome, 
                    identificador: idArvore, 
                    alturaTotal: double.tryParse(getValue(row, ['altura_total_m', 'altura_m'])?.replaceAll(',', '.') ?? '0') ?? 0, 
                    valorCAP: double.tryParse(getValue(row, ['valor_cap', 'cap_cm'])?.replaceAll(',', '.') ?? '0') ?? 0, 
                    alturaBase: double.tryParse(getValue(row, ['altura_base_m'])?.replaceAll(',', '.') ?? '0') ?? 0, 
                    tipoMedidaCAP: getValue(row, ['tipo_medida_cap']) ?? 'fita', 
                    classe: getValue(row, ['classe']),
                    isSynced: false,
                    nomeLider: getValue(row, ['lider_equipe']) ?? nomeDoResponsavel
                );
                
                final map = dadosArvore.toMap();
                map['lastModified'] = now;
                
                final cubagemId = await txn.insert('cubagens_arvores', map);
                arvoreCubagem = dadosArvore.copyWith(id: cubagemId);
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
                      final secaoMap = novaSecao.toMap();
                      secaoMap['lastModified'] = now;
                      await txn.insert('cubagens_secoes', secaoMap, conflictAlgorithm: ConflictAlgorithm.replace);
                      secoesCriadas++;
                  }
              }
          }
        }
      });
      return "Importação Concluída para '${projeto.nome}'!\n\nLinhas: $linhasProcessadas\nAtividades Novas: $atividadesCriadas\nFazendas Novas: $fazendasCriadas\nTalhões Novos: $talhoesCriados\nParcelas Novas/Atualizadas: $parcelasCriadas/$parcelasAtualizadas\nÁrvores Inseridas: $arvoresCriadas\nCubagens Novas/Atualizadas: $cubagensCriadas/$cubagensAtualizadas\nSeções Inseridas: $secoesCriadas";
    } catch(e, s) {
      debugPrint("Erro CRÍTICO na importação universal: $e\n$s");
      return "Ocorreu um erro grave durante a importação. Verifique o console de debug. Erro: ${e.toString()}";
    }
  }
}
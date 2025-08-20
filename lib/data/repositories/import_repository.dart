// lib/data/repositories/import_repository.dart (VERSÃO FINAL COM TODAS AS CORREÇÕES)

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart'; // <<< IMPORT NECESSÁRIO

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
        // Lógica aprimorada para encontrar a chave original mesmo com sanitização
        final sanitizedKey = key.replaceAll(RegExp(r'[^a-z0-9]'), '');
        final originalKey = row.keys.firstWhereOrNull(
          (k) => k.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') == sanitizedKey
        );

        if (originalKey != null) {
          final value = row[originalKey]?.toString();
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
        
        Parcela? parcelaCache;
        int? parcelaCacheDbId;

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
          
          final idFazenda = getValue(row, ['fazenda_id', 'codigo_fazenda', 'id_fazenda']) ?? nomeFazenda;
          
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
                areaHa: double.tryParse(getValue(row, ['area_ha', 'area_talhao_ha'])?.replaceAll(',', '.') ?? ''),
                especie: getValue(row, ['especie', 'material']),
                espacamento: getValue(row, ['espacamento', 'espacamen']),
                idadeAnos: double.tryParse(getValue(row, ['idade_anos', 'idade'])?.replaceAll(',', '.') ?? ''),
              );
              final map = talhao.toMap();
              map['lastModified'] = now;
              final tId = await txn.insert('talhoes', map);
              talhao = talhao.copyWith(id: tId);
              talhoesCriados++;
          } else {
              final areaHaStr = getValue(row, ['area_ha', 'area_talhao_ha']);
              final areaHaFinal = areaHaStr != null ? double.tryParse(areaHaStr.replaceAll(',', '.')) : talhao.areaHa;
              
              final talhaoAtualizado = talhao.copyWith(
                areaHa: areaHaFinal,
                especie: getValue(row, ['especie', 'material']) ?? talhao.especie,
                espacamento: getValue(row, ['espacamento', 'espacamen']) ?? talhao.espacamento,
                idadeAnos: double.tryParse(getValue(row, ['idade_anos', 'idade'])?.replaceAll(',', '.') ?? talhao.idadeAnos?.toString() ?? ''),
              );
              final map = talhaoAtualizado.toMap();
              map['lastModified'] = now;
              await txn.update('talhoes', map, where: 'id = ?', whereArgs: [talhao.id]);
          }
          
          final tipoLinha = ['IPC', 'IFC', 'AUD', 'IFS', 'BIO', 'IFQ'].any((e) => tipoAtividadeStr.contains(e)) ? TipoImportacao.inventario : (tipoAtividadeStr.contains('CUB') ? TipoImportacao.cubagem : TipoImportacao.desconhecido);

          if (tipoLinha == TipoImportacao.inventario) {
              final idParcelaColeta = getValue(row, ['parcela', 'id_parcela']);
              if (idParcelaColeta == null) continue;
              
              int parcelaDbId;

              if (parcelaCache?.talhaoId != talhao.id! || parcelaCache?.idParcela != idParcelaColeta) {
                Parcela? parcelaExistente = (await txn.query('parcelas', where: 'idParcela = ? AND talhaoId = ?', whereArgs: [idParcelaColeta, talhao.id!])).map(Parcela.fromMap).firstOrNull;

                if (parcelaExistente == null) {
                    double? latitudeFinal, longitudeFinal;
                    final eastingStr = getValue(row, ['coord_x', 'easting']);
                    final northingStr = getValue(row, ['coord_y', 'northing']);
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
                    
                    final dataColetaStr = getValue(row, ['data de medição', 'data_coleta']);
                    DateTime dataColetaFinal;
                    if (dataColetaStr != null && dataColetaStr.isNotEmpty) {
                      try {
                        dataColetaFinal = DateFormat('dd/MM/yyyy').parseStrict(dataColetaStr);
                      } catch (e) {
                        dataColetaFinal = DateTime.now();
                      }
                    } else {
                      dataColetaFinal = DateTime.now();
                    }
                    
                    final lado1 = double.tryParse(getValue(row, ['lado 1'])?.replaceAll(',', '.') ?? '0') ?? 0.0;
                    final lado2 = double.tryParse(getValue(row, ['lado 2'])?.replaceAll(',', '.') ?? '0') ?? 0.0;

                    final novaParcela = Parcela(
                        talhaoId: talhao.id!, 
                        idParcela: idParcelaColeta,
                        idFazenda: fazenda.id,
                        areaMetrosQuadrados: lado1 * lado2,
                        status: StatusParcela.concluida, 
                        dataColeta: dataColetaFinal,
                        nomeFazenda: fazenda.nome, 
                        nomeTalhao: talhao.nome, 
                        isSynced: false, 
                        projetoId: projeto.id,
                        up: getValue(row, ['up', 'rf']),
                        referenciaRf: getValue(row, ['rf']),
                        ciclo: getValue(row, ['ciclo']),
                        rotacao: int.tryParse(getValue(row, ['rotação']) ?? ''),
                        tipoParcela: getValue(row, ['tipo']),
                        formaParcela: getValue(row, ['forma']),
                        lado1: lado1,
                        lado2: lado2,
                        latitude: latitudeFinal,
                        longitude: longitudeFinal,
                        observacao: getValue(row, ['obsparcela']),
                        nomeLider: getValue(row, ['equipe']) ?? nomeDoResponsavel
                    );
                    final map = novaParcela.toMap();
                    map['lastModified'] = now;
                    parcelaDbId = await txn.insert('parcelas', map);
                    parcelaCache = novaParcela.copyWith(dbId: parcelaDbId);
                    parcelaCacheDbId = parcelaDbId;
                    parcelasCriadas++;
                } else {
                    final parcelaAtualizada = parcelaExistente.copyWith(
                      up: getValue(row, ['up', 'rf'])
                    );
                    final map = parcelaAtualizada.toMap();
                    map['lastModified'] = now;
                    await txn.update('parcelas', map, where: 'id = ?', whereArgs: [parcelaExistente.dbId!]);
                    
                    parcelaCache = parcelaAtualizada;
                    parcelaCacheDbId = parcelaExistente.dbId!;
                    parcelasAtualizadas++;
                }
              }
              
              parcelaDbId = parcelaCacheDbId!;

              final capStr = getValue(row, ['cap']);
              if (capStr != null) {
                  Codigo _mapCodigo(String? cod) {
                    if (cod == null) return Codigo.normal;
                    switch(cod.toUpperCase()){
                      case 'F': return Codigo.falha;
                      case 'M': return Codigo.morta;
                      case 'Q': return Codigo.quebrada;
                      case 'B': return Codigo.bifurcada;
                      case 'C': return Codigo.caida;
                      case 'A': return Codigo.ataquemacaco;
                      case 'R': return Codigo.regenaracao;
                      case 'I': return Codigo.inclinada;
                      default: return Codigo.normal;
                    }
                  }

                  final codigo1Str = getValue(row, ['cod_1']);
                  final codigo2Str = getValue(row, ['cod_2']);

                  final novaArvore = Arvore(
                    cap: (double.tryParse(capStr.replaceAll(',', '.')) ?? 0.0) / 10.0,
                    altura: (double.tryParse(getValue(row, ['altura'])?.replaceAll(',', '.') ?? '0.0') ?? 0.0) / 10.0,
                    linha: int.tryParse(getValue(row, ['linha']) ?? '0') ?? 0, 
                    posicaoNaLinha: int.tryParse(getValue(row, ['arvore']) ?? '0') ?? 0, 
                    dominante: getValue(row, ['dominante'])?.toLowerCase() == 'h', 
                    codigo: _mapCodigo(codigo1Str),
                    codigo2: codigo2Str != null ? Codigo2.values.firstWhereOrNull((e) => e.name.toUpperCase().startsWith(codigo2Str.toUpperCase())) : null,
                    codigo3: getValue(row, ['cod_3']),
                    tora: int.tryParse(getValue(row, ['tora']) ?? '1'),
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
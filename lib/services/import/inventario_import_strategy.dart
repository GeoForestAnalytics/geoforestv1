// lib/services/import/inventario_import_strategy.dart (VERSÃO CORRIGIDA PARA CÓDIGOS DINÂMICOS)

import 'package:collection/collection.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'csv_import_strategy.dart'; 
import 'package:intl/intl.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'dart:math' as math; 

class InventarioImportStrategy extends BaseImportStrategy {
  InventarioImportStrategy({required super.txn, required super.projeto, super.nomeDoResponsavel});
  
  Parcela? parcelaCache;
  int? parcelaCacheDbId;

  // AGORA RETORNA STRING (ID DO EXCEL)
  String _mapCodigo(String? cod) {
    if (cod == null) return '101'; // Default: Normal
    
    final codTratado = cod.trim().toUpperCase();

    // Mapeamento baseado na sua tabela de excel (Imagem enviada)
    if (codTratado.contains('NORMAL')) return '101';
    if (codTratado == 'A' || codTratado.contains('BIFURCADA ACIMA')) return '102';
    if (codTratado == 'B' || codTratado.contains('BIFURCADA ABAIXO')) return '103';
    if (codTratado == 'CA' || codTratado.contains('CAIDA')) return '104';
    if (codTratado == 'CR' || codTratado.contains('RAIZ')) return '105';
    if (codTratado == 'D' || codTratado.contains('DOMINADA')) return '106';
    if (codTratado == 'F' || codTratado.contains('FALHA')) return '107';
    if (codTratado == 'G' || codTratado.contains('GEADA')) return '108';
    if (codTratado == 'H' || codTratado.contains('DOMINANTE')) return '109';
    if (codTratado == 'M' || codTratado.contains('MORTA') || codTratado.contains('SECA')) return '114';
    if (codTratado == 'Q' || codTratado.contains('QUEBRADA')) return '117';
    if (codTratado == 'R' || codTratado.contains('REBROTA')) return '118';
    
    return '101'; // Fallback para Normal
  }

  @override
  Future<ImportResult> processar(List<Map<String, dynamic>> dataRows) async {
    final result = ImportResult();
    final now = DateTime.now().toIso8601String();

    for (final row in dataRows) {
      result.linhasProcessadas++;
      
      final talhao = await getOrCreateHierarchy(row, result);
      if (talhao == null) continue;

      final idParcelaColeta = BaseImportStrategy.getValue(row, ['id_coleta_parcela', 'parcela', 'id_parcela']);
      if (idParcelaColeta == null) continue;
      
      int parcelaDbId;

      if (parcelaCache?.talhaoId != talhao.id! || parcelaCache?.idParcela != idParcelaColeta) {
        Parcela? parcelaExistente = (await txn.query('parcelas', where: 'idParcela = ? AND talhaoId = ?', whereArgs: [idParcelaColeta, talhao.id!])).map(Parcela.fromMap).firstOrNull;

        if (parcelaExistente == null) {
            final dataColetaStr = BaseImportStrategy.getValue(row, ['data_coleta', 'data de medição']);
            DateTime dataColetaFinal;
            if (dataColetaStr != null && dataColetaStr.isNotEmpty) {
              try { 
                dataColetaFinal = DateTime.parse(dataColetaStr);
              } catch (_) {
                try {
                  dataColetaFinal = DateFormat('dd/MM/yyyy').parseStrict(dataColetaStr); 
                } catch (e) {
                  dataColetaFinal = DateTime.now();
                }
              }
            } else { dataColetaFinal = DateTime.now(); }
            
            final lado1 = double.tryParse(BaseImportStrategy.getValue(row, ['lado1_m', 'lado 1'])?.replaceAll(',', '.') ?? '');
            final lado2 = double.tryParse(BaseImportStrategy.getValue(row, ['lado2_m', 'lado 2'])?.replaceAll(',', '.') ?? '');
            final areaDoCsv = double.tryParse(BaseImportStrategy.getValue(row, ['area_m2', 'areaparcela'])?.replaceAll(',', '.') ?? '');

            double areaFinal = 0.0;
            String formaFinal = 'Retangular';

            if (areaDoCsv != null && areaDoCsv > 0) {
              areaFinal = areaDoCsv;
              if (lado2 == null || lado2 == 0.0) {
                formaFinal = 'Circular';
              }
            } else {
              if (lado1 != null && lado2 != null && lado1 > 0 && lado2 > 0) {
                areaFinal = lado1 * lado2;
                formaFinal = 'Retangular';
              } else if (lado1 != null && lado1 > 0) {
                areaFinal = math.pi * math.pow(lado1, 2);
                formaFinal = 'Circular';
              }
            }

            double? latitudeFinal, longitudeFinal;
            final eastingStr = BaseImportStrategy.getValue(row, ['easting']);
            final northingStr = BaseImportStrategy.getValue(row, ['northing']);
            final zonaStr = BaseImportStrategy.getValue(row, ['zonautm']) ?? '22S'; 

            if (eastingStr != null && northingStr != null) {
                final easting = double.tryParse(eastingStr.replaceAll(',', '.'));
                final northing = double.tryParse(northingStr.replaceAll(',', '.'));
                final zonaNum = int.tryParse(zonaStr.replaceAll(RegExp(r'[^0-9]'), ''));

                if (easting != null && northing != null && zonaNum != null) {
                    final epsg = 31978 + (zonaNum - 18);
                    if (proj4Definitions.containsKey(epsg)) {
                        final projUTM = proj4.Projection.get('EPSG:$epsg') ?? proj4.Projection.parse(proj4Definitions[epsg]!);
                        final projWGS84 = proj4.Projection.get('EPSG:4326')!;
                        var pontoWGS84 = projUTM.transform(projWGS84, proj4.Point(x: easting, y: northing));
                        latitudeFinal = pontoWGS84.y;
                        longitudeFinal = pontoWGS84.x;
                    }
                }
            }
            
            final novaParcela = Parcela(
                talhaoId: talhao.id!, 
                idParcela: idParcelaColeta, 
                idFazenda: talhao.fazendaId,
                areaMetrosQuadrados: areaFinal,
                status: StatusParcela.concluida, 
                dataColeta: dataColetaFinal, 
                nomeFazenda: talhao.fazendaNome, 
                nomeTalhao: talhao.nome, 
                isSynced: false, 
                projetoId: projeto.id,
                up: BaseImportStrategy.getValue(row, ['up', 'rf']),
                referenciaRf: BaseImportStrategy.getValue(row, ['up', 'rf']), 
                ciclo: BaseImportStrategy.getValue(row, ['ciclo']),
                rotacao: int.tryParse(BaseImportStrategy.getValue(row, ['rotação']) ?? ''), 
                tipoParcela: BaseImportStrategy.getValue(row, ['tipo']),
                formaParcela: formaFinal,
                lado1: lado1, 
                lado2: (lado2 != null && lado2 > 0) ? lado2 : null,
                latitude: latitudeFinal,
                longitude: longitudeFinal,
                observacao: BaseImportStrategy.getValue(row, ['observacao_parcela', 'obsparcela']), 
                nomeLider: BaseImportStrategy.getValue(row, ['lider_equipe', 'equipe']) ?? nomeDoResponsavel
            );
            final map = novaParcela.toMap();
            map['lastModified'] = now;
            parcelaDbId = await txn.insert('parcelas', map);
            parcelaCache = novaParcela.copyWith(dbId: parcelaDbId);
            parcelaCacheDbId = parcelaDbId;
            result.parcelasCriadas++;
        } else {
            final parcelaAtualizada = parcelaExistente.copyWith(
              up: parcelaExistente.up ?? BaseImportStrategy.getValue(row, ['up', 'rf']),
              referenciaRf: parcelaExistente.referenciaRf ?? BaseImportStrategy.getValue(row, ['up', 'rf'])
            );
            final map = parcelaAtualizada.toMap();
            map['lastModified'] = now;
            await txn.update('parcelas', map, where: 'id = ?', whereArgs: [parcelaExistente.dbId!]);
            parcelaCache = parcelaAtualizada;
            parcelaCacheDbId = parcelaExistente.dbId!;
            result.parcelasAtualizadas++;
        }
      }
      
      parcelaDbId = parcelaCacheDbId!;

      final capStr = BaseImportStrategy.getValue(row, ['cap_cm', 'cap']);
      if (capStr != null) {
          final codigo1Str = BaseImportStrategy.getValue(row, ['codigo_arvore', 'cod_1']);
          final codigo2Str = BaseImportStrategy.getValue(row, ['codigo_arvore_2', 'cod_2']);
          
          final novaArvore = Arvore(
            cap: double.tryParse(capStr.replaceAll(',', '.')) ?? 0.0,
            altura: double.tryParse(BaseImportStrategy.getValue(row, ['altura_m', 'altura'])?.replaceAll(',', '.') ?? ''),
            alturaDano: double.tryParse(BaseImportStrategy.getValue(row, ['altura_dano_m'])?.replaceAll(',', '.') ?? ''),
            linha: int.tryParse(BaseImportStrategy.getValue(row, ['linha']) ?? '0') ?? 0, 
            posicaoNaLinha: int.tryParse(BaseImportStrategy.getValue(row, ['posicao_na_linha', 'arvore']) ?? '0') ?? 0, 
            dominante: BaseImportStrategy.getValue(row, ['dominante'])?.trim().toLowerCase() == 'sim', 
            codigo: _mapCodigo(codigo1Str), // Agora retorna String '101', '102', etc.
            codigo2: codigo2Str ?? '',      // Agora é String
            codigo3: BaseImportStrategy.getValue(row, ['cod_3']),
            tora: int.tryParse(BaseImportStrategy.getValue(row, ['tora']) ?? ''),
            fimDeLinha: false
          );
          final arvoreMap = novaArvore.toMap();
          arvoreMap['parcelaId'] = parcelaDbId;
          arvoreMap['lastModified'] = now;
          await txn.insert('arvores', arvoreMap);
          result.arvoresCriadas++;
      }
    }
    return result;
  }
}
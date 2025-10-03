// lib/services/import/inventario_import_strategy.dart (VERSÃO CORRIGIDA)

import 'package:collection/collection.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'csv_import_strategy.dart'; // Importa a base
import 'package:intl/intl.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'dart:math' as math; // Necessário para o cálculo PI

class InventarioImportStrategy extends BaseImportStrategy {
  InventarioImportStrategy({required super.txn, required super.projeto, super.nomeDoResponsavel});
  
  Parcela? parcelaCache;
  int? parcelaCacheDbId;

  // ... (a função _mapCodigo permanece a mesma)
  Codigo _mapCodigo(String? cod) {
  if (cod == null) return Codigo.Normal;
  
  // 1. Limpa e padroniza o texto de entrada
  final codTratado = cod.trim().toUpperCase();

  // 2. Usa 'contains' para uma verificação flexível
  if (codTratado.contains('MULTIPLA')) return Codigo.Multipla;
  if (codTratado.contains('BIFURCADA')) return Codigo.Bifurcada;
  if (codTratado.contains('QUEBRADA')) return Codigo.Quebrada;
  if (codTratado.contains('MORTA') || codTratado.contains('SECA')) return Codigo.MortaOuSeca;
  if (codTratado.contains('CAIDA')) return Codigo.Caida;
  if (codTratado.contains('FALHA')) return Codigo.Falha;
  if (codTratado.contains('ATAQUEMACACO')) return Codigo.AtaqueMacaco;
  if (codTratado.contains('REGENERACAO') || codTratado.contains('REBROTA')) return Codigo.Rebrota;
  if (codTratado.contains('INCLINADA')) return Codigo.Inclinada;
  if (codTratado.contains('FOGO')) return Codigo.Fogo;
  if (codTratado.contains('FORMIGA')) return Codigo.AtaqueFormiga;
  if (codTratado.contains('OUTRO')) return Codigo.Outro;

  // Verificações de abreviações, se necessário
  switch(codTratado) {
    case 'F': return Codigo.Falha;
    case 'M': return Codigo.MortaOuSeca;
    case 'Q': return Codigo.Quebrada;
    case 'B': return Codigo.Bifurcada;
    case 'C': return Codigo.Caida;
    case 'A': return Codigo.AtaqueMacaco;
    case 'R': return Codigo.Rebrota;
    case 'I': return Codigo.Inclinada;
    case 'NORMAL': return Codigo.Normal;
    default: return Codigo.Normal; // Se nada corresponder, assume como Normal
  }
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
            
            // --- INÍCIO DA LÓGICA DE CORREÇÃO DA ÁREA ---
            final lado1 = double.tryParse(BaseImportStrategy.getValue(row, ['lado1_m', 'lado 1'])?.replaceAll(',', '.') ?? '');
            final lado2 = double.tryParse(BaseImportStrategy.getValue(row, ['lado2_m', 'lado 2'])?.replaceAll(',', '.') ?? '');
            final areaDoCsv = double.tryParse(BaseImportStrategy.getValue(row, ['area_m2', 'areaparcela'])?.replaceAll(',', '.') ?? '');

            double areaFinal = 0.0;
            String formaFinal = 'Retangular';

            if (areaDoCsv != null && areaDoCsv > 0) {
              areaFinal = areaDoCsv;
              // Se a área veio pronta, mas lado2 não, consideramos circular
              if (lado2 == null || lado2 == 0.0) {
                formaFinal = 'Circular';
              }
            } else {
              // Fallback para cálculo manual
              if (lado1 != null && lado2 != null && lado1 > 0 && lado2 > 0) {
                areaFinal = lado1 * lado2;
                formaFinal = 'Retangular';
              } else if (lado1 != null && lado1 > 0) {
                areaFinal = math.pi * math.pow(lado1, 2);
                formaFinal = 'Circular';
              }
            }
            // --- FIM DA LÓGICA DE CORREÇÃO DA ÁREA ---

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
                areaMetrosQuadrados: areaFinal, // <-- USA A ÁREA CORRIGIDA
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
                formaParcela: formaFinal, // <-- USA A FORMA CORRIGIDA
                lado1: lado1, 
                lado2: (lado2 != null && lado2 > 0) ? lado2 : null, // <-- Salva null se for circular
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
            codigo: _mapCodigo(codigo1Str),
            codigo2: codigo2Str != null ? Codigo2.values.firstWhereOrNull((e) => e.name.toUpperCase().startsWith(codigo2Str.toUpperCase())) : null,
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
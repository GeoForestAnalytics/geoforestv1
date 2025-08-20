// lib/services/import/inventario_import_strategy.dart (VERSÃO FINAL COM COORDENADAS E RF)

import 'package:collection/collection.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'csv_import_strategy.dart'; // Importa a base
import 'package:intl/intl.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;

class InventarioImportStrategy extends BaseImportStrategy {
  InventarioImportStrategy({required super.txn, required super.projeto, super.nomeDoResponsavel});
  
  Parcela? parcelaCache;
  int? parcelaCacheDbId;

  Codigo _mapCodigo(String? cod) {
    if (cod == null) return Codigo.normal;
    switch(cod.trim().toUpperCase()){
      case 'FALHA': return Codigo.falha; 
      case 'MORTA': return Codigo.morta;
      case 'QUEBRADA': return Codigo.quebrada;
      case 'BIFURCADA': return Codigo.bifurcada;
      case 'CAIDA': return Codigo.caida;
      case 'ATAQUEMACACO': return Codigo.ataquemacaco;
      case 'REGENERACAO': return Codigo.regenaracao;
      case 'INCLINADA': return Codigo.inclinada;
      case 'FOGO': return Codigo.fogo;
      case 'FORMIGA': return Codigo.formiga;
      case 'OUTRO': return Codigo.outro;
      case 'NORMAL': return Codigo.normal;
      case 'F': return Codigo.falha; case 'M': return Codigo.morta;
      case 'Q': return Codigo.quebrada; case 'B': return Codigo.bifurcada;
      case 'C': return Codigo.caida; case 'A': return Codigo.ataquemacaco;
      case 'R': return Codigo.regenaracao; case 'I': return Codigo.inclinada;
      default: return Codigo.normal;
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
            
            final lado1 = double.tryParse(BaseImportStrategy.getValue(row, ['lado1_m', 'lado 1'])?.replaceAll(',', '.') ?? '0') ?? 0.0;
            final lado2 = double.tryParse(BaseImportStrategy.getValue(row, ['lado2_m', 'lado 2'])?.replaceAll(',', '.') ?? '0') ?? 0.0;

            // <<< CORREÇÃO APLICADA AQUI: LÓGICA DE CONVERSÃO DE COORDENADAS >>>
            double? latitudeFinal, longitudeFinal;
            final eastingStr = BaseImportStrategy.getValue(row, ['easting']);
            final northingStr = BaseImportStrategy.getValue(row, ['northing']);
            // Tenta adivinhar a zona se não estiver no CSV, assumindo 22S como padrão
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
            // <<< FIM DA CORREÇÃO DE COORDENADAS >>>

            final novaParcela = Parcela(
                talhaoId: talhao.id!, 
                idParcela: idParcelaColeta, 
                idFazenda: talhao.fazendaId,
                areaMetrosQuadrados: lado1 * lado2, 
                status: StatusParcela.concluida, 
                dataColeta: dataColetaFinal, 
                nomeFazenda: talhao.fazendaNome, 
                nomeTalhao: talhao.nome, 
                isSynced: false, 
                projetoId: projeto.id, 
                // <<< CORREÇÃO APLICADA AQUI: Lendo RF/UP >>>
                up: BaseImportStrategy.getValue(row, ['up', 'rf']),
                referenciaRf: BaseImportStrategy.getValue(row, ['up', 'rf']), 
                ciclo: BaseImportStrategy.getValue(row, ['ciclo']),
                rotacao: int.tryParse(BaseImportStrategy.getValue(row, ['rotação']) ?? ''), 
                tipoParcela: BaseImportStrategy.getValue(row, ['tipo']),
                formaParcela: BaseImportStrategy.getValue(row, ['forma']), 
                lado1: lado1, 
                lado2: lado2,
                latitude: latitudeFinal,      // Passa a coordenada convertida
                longitude: longitudeFinal,    // Passa a coordenada convertida
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
            // Se a parcela já existe, podemos aproveitar para atualizar o RF e as coordenadas se estiverem faltando
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
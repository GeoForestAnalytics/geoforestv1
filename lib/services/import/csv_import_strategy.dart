import 'package:sqflite/sqflite.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart'; // Importante para as datas

// Modelos e Repositórios necessários
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';

class ImportResult {
  int linhasProcessadas = 0, atividadesCriadas = 0, fazendasCriadas = 0, talhoesCriados = 0;
  int parcelasCriadas = 0, arvoresCriadas = 0, cubagensCriadas = 0, secoesCriadas = 0;
  int parcelasAtualizadas = 0, cubagensAtualizadas = 0, parcelasIgnoradas = 0;
}

abstract class CsvImportStrategy {
  Future<ImportResult> processar(List<Map<String, dynamic>> dataRows);
}

abstract class BaseImportStrategy implements CsvImportStrategy {
  final Transaction txn;
  final Projeto projeto;
  final String? nomeDoResponsavel;
  
  final Map<String, Atividade> atividadesCache = {};
  final Map<String, Fazenda> fazendasCache = {};
  final Map<String, Talhao> talhoesCache = {};

  BaseImportStrategy({required this.txn, required this.projeto, this.nomeDoResponsavel});
  
  static String? getValue(Map<String, dynamic> row, List<String> possibleKeys) {
    for (final key in possibleKeys) {
      final sanitizedSearchKey = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final originalKey = row.keys.firstWhereOrNull(
        (k) => k.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') == sanitizedSearchKey
      );

      if (originalKey != null) {
        final value = row[originalKey]?.toString();
        return (value == null || value.toLowerCase() == 'null' || value.trim().isEmpty) ? null : value;
      }
    }
    return null;
  }

  Future<Talhao?> getOrCreateHierarchy(Map<String, dynamic> row, ImportResult result) async {
    final now = DateTime.now().toIso8601String();
    
    final tipoAtividadeStr = getValue(row, ['atividade'])?.toUpperCase();
    if (tipoAtividadeStr == null) return null;

    Atividade? atividade = atividadesCache[tipoAtividadeStr];
    if (atividade == null) {
        atividade = (await txn.query('atividades', where: 'projetoId = ? AND tipo = ?', whereArgs: [projeto.id!, tipoAtividadeStr])).map(Atividade.fromMap).firstOrNull;
        if (atividade == null) {
            atividade = Atividade(projetoId: projeto.id!, tipo: tipoAtividadeStr, descricao: 'Importado via CSV', dataCriacao: DateTime.now());
            final aId = await txn.insert('atividades', atividade.toMap()..['lastModified'] = now);
            atividade = atividade.copyWith(id: aId);
            result.atividadesCriadas++;
        }
        atividadesCache[tipoAtividadeStr] = atividade;
    }

    final nomeFazenda = getValue(row, ['fazenda', 'codigo_fazenda', 'fazenda_nome']);
    if (nomeFazenda == null) return null;

    final fazendaCacheKey = '${atividade.id}_$nomeFazenda';
    Fazenda? fazenda = fazendasCache[fazendaCacheKey];

    if (fazenda == null) {
        final idFazenda = nomeFazenda;
        fazenda = (await txn.query('fazendas', where: 'id = ? AND atividadeId = ?', whereArgs: [idFazenda, atividade.id!])).map(Fazenda.fromMap).firstOrNull;
        if (fazenda == null) {
            fazenda = Fazenda(id: idFazenda, atividadeId: atividade.id!, nome: nomeFazenda, municipio: getValue(row, ['municipio']) ?? 'N/I', estado: getValue(row, ['uf', 'estado']) ?? 'UF');
            await txn.insert('fazendas', fazenda.toMap()..['lastModified'] = now);
            result.fazendasCriadas++;
        }
        fazendasCache[fazendaCacheKey] = fazenda;
    }

    final nomeTalhao = getValue(row, ['talhão', 'talhao', 'id_talhao']);
    if (nomeTalhao == null) return null;
    final talhaoCacheKey = '${fazenda.id}_${fazenda.atividadeId}_$nomeTalhao';
    Talhao? talhao = talhoesCache[talhaoCacheKey];
    if (talhao == null) {
        talhao = (await txn.query('talhoes', where: 'nome = ? AND fazendaId = ? AND fazendaAtividadeId = ?', whereArgs: [nomeTalhao, fazenda.id, fazenda.atividadeId])).map(Talhao.fromMap).firstOrNull;
        if (talhao == null) {
            
            // --- NOVA LÓGICA DE IDADE INTELIGENTE ---
            final dataPlantioStr = getValue(row, ['data_plantio', 'plantio', 'dt_plantio']);
            final dataColetaStr = getValue(row, ['data_cole', 'data_coleta']);
            final idadeFixaStr = getValue(row, ['idade_anos', 'idade', 'idade_ano']);
            
            double? idadeCalculada;

            // Se tiver as duas datas, calcula a idade decimal
            if (dataPlantioStr != null && dataColetaStr != null) {
              try {
                // Tenta converter Data de Plantio (dd/mm/aaaa)
                DateFormat dmy = DateFormat('dd/MM/yyyy');
                DateTime dtPlantio = dmy.parse(dataPlantioStr);
                
                // Tenta converter Data de Coleta (Aceita dd/mm/aaaa ou aaaa-mm-dd)
                DateTime dtColeta;
                try { 
                   dtColeta = DateTime.parse(dataColetaStr); 
                } catch(_) { 
                   dtColeta = dmy.parse(dataColetaStr); 
                }

                int dias = dtColeta.difference(dtPlantio).inDays;
                if (dias > 0) {
                  idadeCalculada = dias / 365.25;
                }
              } catch (e) {
                print("Aviso: Falha ao processar datas. Usando idade fixa.");
              }
            }

            // Se não conseguiu calcular pela data, usa o número da coluna Idade_Anos
            final idadeFinal = idadeCalculada ?? double.tryParse(idadeFixaStr?.replaceAll(',', '.') ?? '');

            talhao = Talhao(
              fazendaId: fazenda.id, 
              fazendaAtividadeId: fazenda.atividadeId, 
              nome: nomeTalhao, 
              projetoId: projeto.id, 
              fazendaNome: fazenda.nome,
              bloco: getValue(row, ['bloco']), 
              up: getValue(row, ['rf', 'up']),
              areaHa: double.tryParse(getValue(row, ['area_talhao_ha', 'area_talh', 'area_ha'])?.replaceAll(',', '.') ?? ''),
              especie: getValue(row, ['espécie', 'especie']), 
              materialGenetico: getValue(row, ['material']),
              espacamento: getValue(row, ['espaçamento', 'espacamento']), 
              dataPlantio: dataPlantioStr, // Salva a data como texto para registro
              idadeAnos: idadeFinal,       // Salva o número (calculado ou fixo)
              municipio: fazenda.municipio, 
              estado: fazenda.estado,       
            );
            final tId = await txn.insert('talhoes', talhao.toMap()..['lastModified'] = now);
            talhao = talhao.copyWith(id: tId);
            result.talhoesCriados++;
        }
        talhoesCache[talhaoCacheKey] = talhao;
    }
    
    return talhao;
  }
}
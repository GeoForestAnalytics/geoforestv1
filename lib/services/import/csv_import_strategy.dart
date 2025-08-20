import 'package:sqflite/sqflite.dart';
import 'package:collection/collection.dart';

// Modelos e Repositórios necessários
import 'package:geoforestv1/models/projeto_model.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';

/// Classe para encapsular os resultados da importação de forma estruturada.
class ImportResult {
  int linhasProcessadas = 0, atividadesCriadas = 0, fazendasCriadas = 0, talhoesCriados = 0;
  int parcelasCriadas = 0, arvoresCriadas = 0, cubagensCriadas = 0, secoesCriadas = 0;
  int parcelasAtualizadas = 0, cubagensAtualizadas = 0, parcelasIgnoradas = 0;
}

/// A interface (contrato) que todas as nossas estratégias de importação devem seguir.
abstract class CsvImportStrategy {
  Future<ImportResult> processar(List<Map<String, dynamic>> dataRows);
}

/// Uma classe base que contém a lógica COMUM a todas as estratégias.
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
      final sanitizedKey = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
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

    final nomeFazenda = getValue(row, ['fazenda']);
    if (nomeFazenda == null) return null;
    final fazendaCacheKey = '${atividade.id}_$nomeFazenda';
    Fazenda? fazenda = fazendasCache[fazendaCacheKey];
    if (fazenda == null) {
        final idFazenda = nomeFazenda;
        fazenda = (await txn.query('fazendas', where: 'id = ? AND atividadeId = ?', whereArgs: [idFazenda, atividade.id!])).map(Fazenda.fromMap).firstOrNull;
        if (fazenda == null) {
            fazenda = Fazenda(id: idFazenda, atividadeId: atividade.id!, nome: nomeFazenda, municipio: 'N/I', estado: 'N/I');
            await txn.insert('fazendas', fazenda.toMap()..['lastModified'] = now);
            result.fazendasCriadas++;
        }
        fazendasCache[fazendaCacheKey] = fazenda;
    }

    final nomeTalhao = getValue(row, ['talhão', 'talhao']);
    if (nomeTalhao == null) return null;
    final talhaoCacheKey = '${fazenda.id}_${fazenda.atividadeId}_$nomeTalhao';
    Talhao? talhao = talhoesCache[talhaoCacheKey];
    if (talhao == null) {
        talhao = (await txn.query('talhoes', where: 'nome = ? AND fazendaId = ? AND fazendaAtividadeId = ?', whereArgs: [nomeTalhao, fazenda.id, fazenda.atividadeId])).map(Talhao.fromMap).firstOrNull;
        if (talhao == null) {
            talhao = Talhao(
              fazendaId: fazenda.id, fazendaAtividadeId: fazenda.atividadeId, nome: nomeTalhao, projetoId: projeto.id, fazendaNome: fazenda.nome,
              bloco: getValue(row, ['bloco']), up: getValue(row, ['rf']),
              // <<< VERSÃO FINAL E CORRETA DA ÁREA >>>
              areaHa: double.tryParse(getValue(row, ['area_talhao_ha', 'áreatalhão', 'areatalhao', 'area_talh'])?.replaceAll(',', '.') ?? ''),
              especie: getValue(row, ['espécie', 'especie']), materialGenetico: getValue(row, ['material']),
              espacamento: getValue(row, ['espaçamento', 'espacamento']), dataPlantio: getValue(row, ['plantio']),
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
// lib/services/import/excel_import_service.dart

import 'dart:io';
import 'package:excel/excel.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:sqflite/sqflite.dart';

class ExcelImportResult {
  int regrasCriadas = 0;
  int parcelasCriadas = 0;
  int cubagensCriadas = 0;
  String mensagem = "";
}

class ExcelImportService {
  final _dbHelper = DatabaseHelper.instance;

  Future<ExcelImportResult> importarProjetoXlsx({
    required String filePath,
    required int projetoId,
    required String nomeResponsavel,
  }) async {
    final result = ExcelImportResult();
    
    try {
      var bytes = File(filePath).readAsBytesSync();
      var excel = Excel.decodeBytes(bytes);
      final db = await _dbHelper.database;
      final now = DateTime.now().toIso8601String();

      await db.transaction((txn) async {
        
        // --- 1. ABA DE CONFIGURAÇÃO (REGRAS DE CÓDIGOS) ---
        var configSheet = excel.tables['Configuracao'] ?? excel.tables['Config'];
        if (configSheet != null) {
          await txn.delete('regras_codigos', where: 'projetoId = ?', whereArgs: [projetoId]);
          for (int i = 1; i < configSheet.maxRows; i++) {
            var row = configSheet.rows[i];
            if (row.length < 8 || row[7] == null) continue;
            await txn.insert('regras_codigos', {
              'id': int.tryParse(row[7]?.value.toString() ?? ''),
              'projetoId': projetoId,
              'sigla': row[8]?.value?.toString() ?? '',
              'descricao': row[9]?.value?.toString() ?? '',
              'fuste': row[10]?.value?.toString() ?? '.',
              'cap': row[11]?.value?.toString() ?? '.',
              'altura': row[12]?.value?.toString() ?? '.',
              'hipso': row[13]?.value?.toString() ?? 'N',
              'obrigaAlturaDano': row[14]?.value?.toString() ?? 'N',
              'permiteDominante': row[16]?.value?.toString() ?? 'N',
            });
            result.regrasCriadas++;
          }
        }

        // --- 2. ABA DE PLANEJAMENTO (INVENTÁRIO) ---
        var planSheet = excel.tables['Planejamento'] ?? excel.tables['Planilha1'];
        if (planSheet != null) {
          Atividade ativInv = await _getAtiv(txn, projetoId, "INVENTARIO", now);
          for (int i = 1; i < planSheet.maxRows; i++) {
            var row = planSheet.rows[i];
            if (row.isEmpty || row[2] == null) continue;

            final faz = await _getFaz(txn, ativInv.id!, row[2]?.value?.toString() ?? 'F1', now);
            final tal = await _getTal(txn, faz, row[3]?.value?.toString() ?? 'T1', projetoId, now);

            await txn.insert('parcelas', {
              'uuid': "${projetoId}_INV_${tal.id}_${row[4]?.value}",
              'talhaoId': tal.id,
              'idParcela': row[4]?.value?.toString(),
              'areaMetrosQuadrados': double.tryParse(row[7]?.value?.toString() ?? '0') ?? 0,
              'latitude': double.tryParse(row[5]?.value?.toString() ?? '0') ?? 0,
              'longitude': double.tryParse(row[6]?.value?.toString() ?? '0') ?? 0,
              'status': 'pendente',
              'dataColeta': now,
              'nomeFazenda': faz.nome,
              'nomeTalhao': tal.nome,
              'projetoId': projetoId,
              'lastModified': now,
              'nomeLider': nomeResponsavel
            });
            result.parcelasCriadas++;
          }
        }

        // --- 3. ABA DE CUBAGEM (PLANO DE CUBAGEM) ---
        var cubSheet = excel.tables['Cubagem'] ?? excel.tables['Plano_Cubagem'];
        if (cubSheet != null) {
          Atividade ativCub = await _getAtiv(txn, projetoId, "CUBAGEM RIGOROSA", now);
          for (int i = 1; i < cubSheet.maxRows; i++) {
            var row = cubSheet.rows[i];
            if (row.length < 8 || row[7] == null) continue;

            final faz = await _getFaz(txn, ativCub.id!, row[2]?.value?.toString() ?? 'F1', now);
            final tal = await _getTal(txn, faz, row[3]?.value?.toString() ?? 'T1', projetoId, now);

            await txn.insert('cubagens_arvores', {
              'talhaoId': tal.id,
              'id_fazenda': faz.id,
              'nome_fazenda': faz.nome,
              'nome_talhao': tal.nome,
              'identificador': row[7]?.value?.toString(), // ID da árvore
              'classe': row[8]?.value?.toString(),       // Classe diamétrica
              'alturaTotal': 0,
              'valorCAP': 0,
              'alturaBase': 1.30,
              'isSynced': 0,
              'exportada': 0,
              'lastModified': now,
              'nomeLider': nomeResponsavel
            });
            result.cubagensCriadas++;
          }
        }
      });

      result.mensagem = "Importado com sucesso!\nRegras: ${result.regrasCriadas}\nParcelas: ${result.parcelasCriadas}\nCubagens: ${result.cubagensCriadas}";
      return result;
    } catch (e) {
      result.mensagem = "Erro: $e";
      return result;
    }
  }

  // Auxiliares para hierarquia
  Future<Atividade> _getAtiv(Transaction txn, int pId, String t, String n) async {
    var r = await txn.query('atividades', where: 'projetoId = ? AND tipo = ?', whereArgs: [pId, t]);
    if (r.isNotEmpty) return Atividade.fromMap(r.first);
    int id = await txn.insert('atividades', {'projetoId': pId, 'tipo': t, 'descricao': 'XLSX', 'dataCriacao': n, 'lastModified': n});
    return Atividade(id: id, projetoId: pId, tipo: t, descricao: '', dataCriacao: DateTime.now());
  }

  Future<Fazenda> _getFaz(Transaction txn, int aId, String nom, String n) async {
    var r = await txn.query('fazendas', where: 'atividadeId = ? AND nome = ?', whereArgs: [aId, nom]);
    if (r.isNotEmpty) return Fazenda.fromMap(r.first);
    await txn.insert('fazendas', {'id': nom, 'atividadeId': aId, 'nome': nom, 'municipio': 'N/I', 'estado': 'UF', 'lastModified': n});
    return Fazenda(id: nom, atividadeId: aId, nome: nom, municipio: '', estado: '');
  }

  Future<Talhao> _getTal(Transaction txn, Fazenda f, String nom, int pId, String n) async {
    var r = await txn.query('talhoes', where: 'fazendaId = ? AND nome = ?', whereArgs: [f.id, nom]);
    if (r.isNotEmpty) return Talhao.fromMap(r.first);
    int id = await txn.insert('talhoes', {'fazendaId': f.id, 'fazendaAtividadeId': f.atividadeId, 'projetoId': pId, 'nome': nom, 'lastModified': n});
    return Talhao(id: id, fazendaId: f.id, fazendaAtividadeId: f.atividadeId, nome: nom);
  }
}
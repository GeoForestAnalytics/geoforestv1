// lib/services/import/excel_import_service.dart (VERSÃO À PROVA DE RANGE ERROR)

import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/models/atividade_model.dart';
import 'package:geoforestv1/models/fazenda_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/utils/constants.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:sqflite/sqflite.dart';

class ExcelImportResult {
  int regrasCriadas = 0;
  int parcelasCriadas = 0;
  String mensagem = "";
}

class ExcelImportService {
  final _dbHelper = DatabaseHelper.instance;

  // Função auxiliar para ler célula sem travar o app se a coluna não existir
  String _safeGet(List<Data?> row, int index, {String defaultValue = ''}) {
    if (index < 0 || index >= row.length) return defaultValue;
    return row[index]?.value?.toString() ?? defaultValue;
  }

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
        
        // --- 1. ABA DE CONFIGURAÇÃO (REGRAS) ---
        var configSheet = excel.tables['Configuracao'] ?? excel.tables['Config'];
        if (configSheet != null) {
          await txn.delete('regras_codigos', where: 'projetoId = ?', whereArgs: [projetoId]);
          for (int i = 1; i < configSheet.maxRows; i++) {
            var row = configSheet.rows[i];
            if (row.isEmpty || _safeGet(row, 0).isEmpty) continue;

            await txn.insert('regras_codigos', {
              'id': int.tryParse(_safeGet(row, 0)) ?? 0,          // Coluna A
              'projetoId': projetoId,
              'sigla': _safeGet(row, 1),                          // Coluna B
              'descricao': _safeGet(row, 2),                      // Coluna C
              'obrigaFuste': _safeGet(row, 3, defaultValue: '.'), // <--- CORRIGIDO (Coluna D)
              'obrigaCap': _safeGet(row, 4, defaultValue: '.'),   // <--- CORRIGIDO (Coluna E)
              'obrigaAltura': _safeGet(row, 5, defaultValue: '.'),// <--- CORRIGIDO (Coluna F)
              'obrigaHipso': _safeGet(row, 6, defaultValue: 'N'), // <--- CORRIGIDO (Coluna G)
              'obrigaAlturaDano': _safeGet(row, 7, defaultValue: 'N'), // Coluna H
              'permiteDominante': _safeGet(row, 8, defaultValue: 'N'), // Coluna I
              'listaCompativeis': '', // Pode deixar vazio por enquantO
            });
            result.regrasCriadas++;
          }
        }

        // --- 2. ABA DE PLANEJAMENTO (PONTOS) ---
        var planSheet = excel.tables['Planejamento'] ?? excel.tables['Planilha1'];
        if (planSheet != null) {
          final projWGS84 = proj4.Projection.get('EPSG:4326')!;

          for (int i = 1; i < planSheet.maxRows; i++) {
            var row = planSheet.rows[i];
            if (row.isEmpty || _safeGet(row, 0).isEmpty) continue;

            final tipoAtiv = _safeGet(row, 0, defaultValue: 'IPC'); // Col A
            final nomeFazenda = _safeGet(row, 3);                   // Col D
            final nomeTalhao = _safeGet(row, 7);                    // Col H
            final idParcela = _safeGet(row, 8);                     // Col I
            final areaParcela = double.tryParse(_safeGet(row, 17).replaceAll(',', '.')) ?? 0; // Col R
            
            final zonaUtm = _safeGet(row, 26, defaultValue: '22J'); // Col AA
            final utmX = double.tryParse(_safeGet(row, 27).replaceAll(',', '.')) ?? 0; // Col AB
            final utmY = double.tryParse(_safeGet(row, 28).replaceAll(',', '.')) ?? 0; // Col AC

            double latFinal = 0, lonFinal = 0;
            // Busca o código EPSG baseado na Zona (ex: 22J)
            final epsg = zonasUtmSirgas2000['SIRGAS 2000 / UTM Zona $zonaUtm'] ?? 31982;
            final projUTM = proj4.Projection.get('EPSG:$epsg');
            
            if (projUTM != null && utmX > 0) {
              var ponto = projUTM.transform(projWGS84, proj4.Point(x: utmX, y: utmY));
              latFinal = ponto.y;
              lonFinal = ponto.x;
            }

            final ativ = await _getAtiv(txn, projetoId, tipoAtiv, now);
            final faz = await _getFaz(txn, ativ.id!, nomeFazenda, now);
            final tal = await _getTal(txn, faz, nomeTalhao, projetoId, now);

            await txn.insert('parcelas', {
              'uuid': "${projetoId}_${ativ.id}_${tal.id}_$idParcela",
              'talhaoId': tal.id,
              'idParcela': idParcela,
              'areaMetrosQuadrados': areaParcela,
              'latitude': latFinal,
              'longitude': lonFinal,
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
      });

      result.mensagem = "Importação Concluída!\nRegras: ${result.regrasCriadas}\nParcelas: ${result.parcelasCriadas}";
      return result;
    } catch (e) {
      debugPrint("ERRO EXCEL: $e");
      return ExcelImportResult()..mensagem = "Erro técnico: $e";
    }
  }

  // Métodos auxiliares permanecem os mesmos...
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
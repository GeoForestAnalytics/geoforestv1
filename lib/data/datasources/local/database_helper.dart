import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

// (Mantenha o mapa proj4Definitions aqui em cima...)
final Map<int, String> proj4Definitions = {
  31978: '+proj=utm +zone=18 +south +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
  31979: '+proj=utm +zone=19 +south +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
  31980: '+proj=utm +zone=20 +south +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
  31981: '+proj=utm +zone=21 +south +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
  31982: '+proj=utm +zone=22 +south +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
  31983: '+proj=utm +zone=23 +south +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
  31984: '+proj=utm +zone=24 +south +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
  31985: '+proj=utm +zone=25 +south +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
};

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._privateConstructor();
  static Database? _database;

  DatabaseHelper._privateConstructor();
  factory DatabaseHelper() => _instance;
  static DatabaseHelper get instance => _instance;

  Future<Database> get database async => _database ??= await _initDatabase();

  Future<Database> _initDatabase() async {
    return await openDatabase(
      join(await getDatabasesPath(), 'geoforestv1.db'),
      version: 67,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async =>
      await db.execute('PRAGMA foreign_keys = ON');

  // --- CRIAÇÃO DO BANCO (NOVOS USUÁRIOS) ---
  Future<void> _onCreate(Database db, int version) async {
    debugPrint("Criando banco de dados versão $version do zero...");

    // 1. Cria todas as tabelas padrão
    await db.execute('''
      CREATE TABLE ${DbProjetos.tableName} (
        ${DbProjetos.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbProjetos.licenseId} TEXT,
        ${DbProjetos.nome} TEXT NOT NULL,
        ${DbProjetos.empresa} TEXT NOT NULL,
        ${DbProjetos.responsavel} TEXT NOT NULL,
        ${DbProjetos.dataCriacao} TEXT NOT NULL,
        ${DbProjetos.status} TEXT NOT NULL DEFAULT 'ativo',
        ${DbProjetos.delegadoPorLicenseId} TEXT,
        ${DbProjetos.referenciaRf} TEXT,
        ${DbProjetos.lastModified} TEXT NOT NULL 
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DbAtividades.tableName} (
        ${DbAtividades.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbAtividades.projetoId} INTEGER NOT NULL,
        ${DbAtividades.tipo} TEXT NOT NULL,
        ${DbAtividades.descricao} TEXT NOT NULL,
        ${DbAtividades.dataCriacao} TEXT NOT NULL,
        ${DbAtividades.metodoCubagem} TEXT,
        ${DbAtividades.lastModified} TEXT NOT NULL, 
        FOREIGN KEY (${DbAtividades.projetoId}) REFERENCES ${DbProjetos.tableName} (${DbProjetos.id}) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DbFazendas.tableName} (
        ${DbFazendas.id} TEXT NOT NULL,
        ${DbFazendas.atividadeId} INTEGER NOT NULL,
        ${DbFazendas.nome} TEXT NOT NULL,
        ${DbFazendas.municipio} TEXT NOT NULL,
        ${DbFazendas.estado} TEXT NOT NULL,
        ${DbFazendas.lastModified} TEXT NOT NULL,
        PRIMARY KEY (${DbFazendas.id}, ${DbFazendas.atividadeId}),
        FOREIGN KEY (${DbFazendas.atividadeId}) REFERENCES ${DbAtividades.tableName} (${DbAtividades.id}) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DbTalhoes.tableName} (
        ${DbTalhoes.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbTalhoes.fazendaId} TEXT NOT NULL,
        ${DbTalhoes.fazendaAtividadeId} INTEGER NOT NULL,
        ${DbTalhoes.projetoId} INTEGER, 
        ${DbTalhoes.nome} TEXT NOT NULL,
        ${DbTalhoes.areaHa} REAL,
        ${DbTalhoes.idadeAnos} REAL,
        ${DbTalhoes.especie} TEXT,
        ${DbTalhoes.espacamento} TEXT,
        ${DbTalhoes.bloco} TEXT,
        ${DbTalhoes.up} TEXT,
        ${DbTalhoes.materialGenetico} TEXT,
        ${DbTalhoes.dataPlantio} TEXT,
        ${DbTalhoes.lastModified} TEXT NOT NULL, 
        FOREIGN KEY (${DbTalhoes.fazendaId}, ${DbTalhoes.fazendaAtividadeId}) REFERENCES ${DbFazendas.tableName} (${DbFazendas.id}, ${DbFazendas.atividadeId}) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DbParcelas.tableName} (
        ${DbParcelas.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbParcelas.uuid} TEXT NOT NULL UNIQUE,
        ${DbParcelas.talhaoId} INTEGER,
        ${DbParcelas.atividadeTipo} TEXT,
        ${DbParcelas.nomeFazenda} TEXT,
        ${DbParcelas.nomeTalhao} TEXT,
        ${DbParcelas.idParcela} TEXT NOT NULL,
        ${DbParcelas.areaMetrosQuadrados} REAL NOT NULL,
        ${DbParcelas.observacao} TEXT,
        ${DbParcelas.latitude} REAL,
        ${DbParcelas.longitude} REAL,
        ${DbParcelas.latitudePlanejada} REAL,
        ${DbParcelas.longitudePlanejada} REAL,
        ${DbParcelas.altitude} REAL,
        ${DbParcelas.dataColeta} TEXT NOT NULL,
        ${DbParcelas.status} TEXT NOT NULL,
        ${DbParcelas.exportada} INTEGER DEFAULT 0 NOT NULL,
        ${DbParcelas.isSynced} INTEGER DEFAULT 0 NOT NULL,
        ${DbParcelas.idFazenda} TEXT,
        ${DbParcelas.photoPaths} TEXT,
        ${DbParcelas.nomeLider} TEXT,
        ${DbParcelas.projetoId} INTEGER,
        ${DbParcelas.municipio} TEXT, 
        ${DbParcelas.estado} TEXT,
        ${DbParcelas.up} TEXT,
        ${DbParcelas.referenciaRf} TEXT,
        ${DbParcelas.ciclo} TEXT,
        ${DbParcelas.rotacao} INTEGER,
        ${DbParcelas.tipoParcela} TEXT,
        ${DbParcelas.formaParcela} TEXT,
        ${DbParcelas.lado1} REAL,
        ${DbParcelas.lado2} REAL,
        ${DbParcelas.declividade} REAL,
        arvores TEXT,
        ${DbParcelas.lastModified} TEXT NOT NULL,
        ${DbParcelas.tipoMedidaCAP} TEXT,
        FOREIGN KEY (${DbParcelas.talhaoId}) REFERENCES ${DbTalhoes.tableName} (${DbTalhoes.id}) ON DELETE CASCADE
      )
    ''');

    // TABELA ARVORES (JÁ COM A COLUNA ESPECIE)
    await db.execute('''
      CREATE TABLE ${DbArvores.tableName} (
        ${DbArvores.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbArvores.parcelaId} INTEGER NOT NULL,
        ${DbArvores.cap} REAL NOT NULL,
        ${DbArvores.altura} REAL,
        ${DbArvores.alturaDano} REAL,
        ${DbArvores.linha} INTEGER NOT NULL,
        ${DbArvores.posicaoNaLinha} INTEGER NOT NULL,
        ${DbArvores.fimDeLinha} INTEGER NOT NULL,
        ${DbArvores.dominante} INTEGER NOT NULL,
        ${DbArvores.codigo} TEXT NOT NULL,
        ${DbArvores.codigo2} TEXT,
        ${DbArvores.codigo3} TEXT,
        especie TEXT, 
        ${DbArvores.tora} TEXT,
        ${DbArvores.photoPaths} TEXT,
        ${DbArvores.observacao} TEXT,
        ${DbArvores.capAuditoria} REAL,
        ${DbArvores.alturaAuditoria} REAL,
        ${DbArvores.lastModified} TEXT NOT NULL,
        ${DbArvores.tipoMedidaCAP} TEXT,
        ${DbArvores.medidaSuta1} REAL,
        ${DbArvores.medidaSuta2} REAL,
        FOREIGN KEY (${DbArvores.parcelaId}) REFERENCES ${DbParcelas.tableName} (${DbParcelas.id}) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DbCubagensArvores.tableName} (
        ${DbCubagensArvores.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbCubagensArvores.talhaoId} INTEGER,
        ${DbCubagensArvores.idFazenda} TEXT,
        ${DbCubagensArvores.nomeFazenda} TEXT,
        ${DbCubagensArvores.nomeTalhao} TEXT,
        ${DbCubagensArvores.identificador} TEXT NOT NULL,
        ${DbCubagensArvores.alturaTotal} REAL NOT NULL,
        ${DbCubagensArvores.tipoMedidaCAP} TEXT NOT NULL,
        ${DbCubagensArvores.valorCAP} REAL NOT NULL,
        ${DbCubagensArvores.alturaBase} REAL NOT NULL,
        ${DbCubagensArvores.classe} TEXT,
        ${DbCubagensArvores.observacao} TEXT,
        ${DbCubagensArvores.latitude} REAL,
        ${DbCubagensArvores.longitude} REAL,
        ${DbCubagensArvores.metodoCubagem} TEXT,
        ${DbCubagensArvores.rf} TEXT,
        ${DbCubagensArvores.dataColeta} TEXT,
        ${DbCubagensArvores.exportada} INTEGER DEFAULT 0 NOT NULL,
        ${DbCubagensArvores.isSynced} INTEGER DEFAULT 0 NOT NULL,
        ${DbCubagensArvores.nomeLider} TEXT,
        secoes TEXT,
        ${DbCubagensArvores.passoFixo} REAL DEFAULT 2.0,
        ${DbCubagensArvores.lastModified} TEXT NOT NULL,
        FOREIGN KEY (${DbCubagensArvores.talhaoId}) REFERENCES ${DbTalhoes.tableName} (${DbTalhoes.id}) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DbCubagensSecoes.tableName} (
        ${DbCubagensSecoes.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbCubagensSecoes.cubagemArvoreId} INTEGER NOT NULL,
        ${DbCubagensSecoes.alturaMedicao} REAL NOT NULL,
        ${DbCubagensSecoes.circunferencia} REAL,
        ${DbCubagensSecoes.casca1Mm} REAL,
        ${DbCubagensSecoes.casca2Mm} REAL,
        ${DbCubagensSecoes.lastModified} TEXT NOT NULL,
        FOREIGN KEY (${DbCubagensSecoes.cubagemArvoreId}) REFERENCES ${DbCubagensArvores.tableName} (${DbCubagensArvores.id}) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DbSortimentos.tableName} (
        ${DbSortimentos.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbSortimentos.nome} TEXT NOT NULL,
        ${DbSortimentos.comprimento} REAL NOT NULL,
        ${DbSortimentos.diametroMinimo} REAL NOT NULL,
        ${DbSortimentos.diametroMaximo} REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${DbDiarioDeCampo.tableName} (
        ${DbDiarioDeCampo.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbDiarioDeCampo.dataRelatorio} TEXT NOT NULL,
        ${DbDiarioDeCampo.nomeLider} TEXT NOT NULL,
        ${DbDiarioDeCampo.projetoId} INTEGER NOT NULL,
        ${DbDiarioDeCampo.talhaoId} INTEGER,
        ${DbDiarioDeCampo.kmInicial} REAL,
        ${DbDiarioDeCampo.kmFinal} REAL,
        ${DbDiarioDeCampo.localizacaoDestino} TEXT,
        ${DbDiarioDeCampo.pedagioValor} REAL,
        ${DbDiarioDeCampo.abastecimentoValor} REAL,
        ${DbDiarioDeCampo.alimentacaoMarmitasQtd} INTEGER,
        ${DbDiarioDeCampo.alimentacaoRefeicaoValor} REAL,
        ${DbDiarioDeCampo.alimentacaoDescricao} TEXT,
        ${DbDiarioDeCampo.outrasDespesasValor} REAL,
        ${DbDiarioDeCampo.outrasDespesasDescricao} TEXT,
        ${DbDiarioDeCampo.veiculoPlaca} TEXT,
        ${DbDiarioDeCampo.veiculoModelo} TEXT,
        ${DbDiarioDeCampo.equipeNoCarro} TEXT,
        ${DbDiarioDeCampo.lastModified} TEXT NOT NULL,
        UNIQUE(${DbDiarioDeCampo.dataRelatorio}, ${DbDiarioDeCampo.nomeLider})
      )
    ''');

     await db.execute('''
      CREATE TABLE checklist_veicular (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        data_registro TEXT NOT NULL,
        uid_usuario TEXT,
        nome_motorista TEXT,
        placa TEXT,
        km_atual REAL,
        modelo_veiculo TEXT,
        prefixo TEXT,           
        categoria_cnh TEXT,     
        vencimento_cnh TEXT,    
        is_motorista INTEGER NOT NULL,
        itens_json TEXT,
        observacoes TEXT,
        fotos_avarias TEXT,
        lastModified TEXT NOT NULL
      )
    ''');

    // 2. CRIA A TABELA ESPECIES
    await db.execute('''
      CREATE TABLE especies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome_cientifico TEXT NOT NULL,
        nome_comum TEXT NOT NULL,
        familia TEXT,
        fator_forma REAL,
        regiao TEXT
      )
    ''');
    
    // 3. INDEXES
    await db.execute(
        'CREATE INDEX idx_arvores_parcelaId ON ${DbArvores.tableName}(${DbArvores.parcelaId})');
    await db.execute(
        'CREATE INDEX idx_cubagens_secoes_cubagemArvoreId ON ${DbCubagensSecoes.tableName}(${DbCubagensSecoes.cubagemArvoreId})');
        
    // 4. POPULA AS ESPECIES
    await _popularTabelaEspecies(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  debugPrint("SISTEMA: Tentando migrar de $oldVersion para $newVersion");
  for (var v = oldVersion + 1; v <= newVersion; v++) {
    debugPrint("SISTEMA: Processando migração v$v...");
    switch (v) {
        case 25:
          await db.execute(
              'ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.uuid} TEXT');
          final parcelasSemUuid = await db.query(DbParcelas.tableName,
              where: '${DbParcelas.uuid} IS NULL');
          for (final p in parcelasSemUuid) {
            await db.update(
                DbParcelas.tableName, {DbParcelas.uuid: const Uuid().v4()},
                where: '${DbParcelas.id} = ?', whereArgs: [p[DbParcelas.id]]);
          }
          break;
        case 26:
          await db.execute(
              'ALTER TABLE ${DbCubagensArvores.tableName} ADD COLUMN ${DbCubagensArvores.isSynced} INTEGER DEFAULT 0 NOT NULL');
          break;
        case 27:
          await db.execute(
              "ALTER TABLE ${DbProjetos.tableName} ADD COLUMN ${DbProjetos.status} TEXT NOT NULL DEFAULT 'ativo'");
          break;
        case 28:
          await db.execute(
              "ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.nomeLider} TEXT");
          await db.execute(
              "ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.projetoId} INTEGER");
          break;
        case 29:
          await db.execute(
              "ALTER TABLE ${DbProjetos.tableName} ADD COLUMN ${DbProjetos.licenseId} TEXT");
          break;
        case 30:
          await db.execute(
              "ALTER TABLE ${DbProjetos.tableName} ADD COLUMN ${DbProjetos.delegadoPorLicenseId} TEXT");
          break;
        case 31:
          await db.execute(
              "ALTER TABLE ${DbCubagensArvores.tableName} ADD COLUMN ${DbCubagensArvores.nomeLider} TEXT");
          break;
        case 32:
          await db.execute(
              "ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.municipio} TEXT");
          await db.execute(
              "ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.estado} TEXT");
          break;
        case 33:
          await db.execute(
              "ALTER TABLE ${DbProjetos.tableName} ADD COLUMN ${DbProjetos.lastModified} TEXT");
          await db.execute(
              "ALTER TABLE ${DbAtividades.tableName} ADD COLUMN ${DbAtividades.lastModified} TEXT");
          await db.execute(
              "ALTER TABLE ${DbFazendas.tableName} ADD COLUMN ${DbFazendas.lastModified} TEXT");
          await db.execute(
              "ALTER TABLE ${DbTalhoes.tableName} ADD COLUMN ${DbTalhoes.lastModified} TEXT");
          await db.execute(
              "ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.lastModified} TEXT");
          await db.execute(
              "ALTER TABLE ${DbArvores.tableName} ADD COLUMN ${DbArvores.lastModified} TEXT");
          await db.execute(
              "ALTER TABLE ${DbCubagensArvores.tableName} ADD COLUMN ${DbCubagensArvores.lastModified} TEXT");
          await db.execute(
              "ALTER TABLE ${DbCubagensSecoes.tableName} ADD COLUMN ${DbCubagensSecoes.lastModified} TEXT");

          final now = DateTime.now().toIso8601String();
          await db.update(DbProjetos.tableName, {DbProjetos.lastModified: now},
              where: '${DbProjetos.lastModified} IS NULL');
          await db.update(
              DbAtividades.tableName, {DbAtividades.lastModified: now},
              where: '${DbAtividades.lastModified} IS NULL');
          await db.update(DbFazendas.tableName, {DbFazendas.lastModified: now},
              where: '${DbFazendas.lastModified} IS NULL');
          await db.update(DbTalhoes.tableName, {DbTalhoes.lastModified: now},
              where: '${DbTalhoes.lastModified} IS NULL');
          await db.update(DbParcelas.tableName, {DbParcelas.lastModified: now},
              where: '${DbParcelas.lastModified} IS NULL');
          await db.update(DbArvores.tableName, {DbArvores.lastModified: now},
              where: '${DbArvores.lastModified} IS NULL');
          await db.update(DbCubagensArvores.tableName,
              {DbCubagensArvores.lastModified: now},
              where: '${DbCubagensArvores.lastModified} IS NULL');
          await db.update(
              DbCubagensSecoes.tableName, {DbCubagensSecoes.lastModified: now},
              where: '${DbCubagensSecoes.lastModified} IS NULL');
          break;
        case 34:
          await db.execute(
              'ALTER TABLE ${DbTalhoes.tableName} ADD COLUMN ${DbTalhoes.projetoId} INTEGER');
          break;
        case 35:
          await db.execute(
              'ALTER TABLE ${DbProjetos.tableName} ADD COLUMN ${DbProjetos.referenciaRf} TEXT');
          break;
        case 36:
          await db.execute('''
            CREATE TABLE ${DbDiarioDeCampo.tableName} (
              ${DbDiarioDeCampo.id} INTEGER PRIMARY KEY AUTOINCREMENT,
              ${DbDiarioDeCampo.dataRelatorio} TEXT NOT NULL, ${DbDiarioDeCampo.nomeLider} TEXT NOT NULL, ${DbDiarioDeCampo.projetoId} INTEGER NOT NULL,
              ${DbDiarioDeCampo.talhaoId} INTEGER NOT NULL, ${DbDiarioDeCampo.kmInicial} REAL, ${DbDiarioDeCampo.kmFinal} REAL, ${DbDiarioDeCampo.localizacaoDestino} TEXT,
              ${DbDiarioDeCampo.pedagioValor} REAL, ${DbDiarioDeCampo.abastecimentoValor} REAL, ${DbDiarioDeCampo.alimentacaoMarmitasQtd} INTEGER,
              ${DbDiarioDeCampo.alimentacaoRefeicaoValor} REAL, ${DbDiarioDeCampo.alimentacaoDescricao} TEXT, ${DbDiarioDeCampo.veiculoPlaca} TEXT,
              ${DbDiarioDeCampo.veiculoModelo} TEXT, ${DbDiarioDeCampo.equipeNoCarro} TEXT, ${DbDiarioDeCampo.lastModified} TEXT NOT NULL,
              UNIQUE(${DbDiarioDeCampo.dataRelatorio}, ${DbDiarioDeCampo.nomeLider}, ${DbDiarioDeCampo.talhaoId})
            )
          ''');
          break;
        case 37:
          await db.execute(
              'ALTER TABLE ${DbArvores.tableName} ADD COLUMN ${DbArvores.alturaDano} REAL');
          break;
        case 38:
          await db.execute(
              'ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.up} TEXT');
          break;
        case 39:
          try {
            await db.execute(
                'ALTER TABLE ${DbParcelas.tableName} ADD COLUMN up_temp_string TEXT');
            await db.execute(
                'UPDATE ${DbParcelas.tableName} SET up_temp_string = ${DbParcelas.up}');
            await db.execute(
                'ALTER TABLE ${DbParcelas.tableName} DROP COLUMN ${DbParcelas.up}');
            await db.execute(
                'ALTER TABLE ${DbParcelas.tableName} RENAME COLUMN up_temp_string TO ${DbParcelas.up}');
          } catch (e) {
            debugPrint(
                "Aviso na migração 39 (esperado se a coluna '${DbParcelas.up}' já era TEXT): $e");
            if (!await _columnExists(db, DbParcelas.tableName, DbParcelas.up)) {
              await db.execute(
                  'ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.up} TEXT');
            }
          }
          break;
        case 40:
          debugPrint("Migração v40 pulada, lógica incorporada na v41.");
          break;
        case 41:
          await db.execute(
              'ALTER TABLE ${DbArvores.tableName} ADD COLUMN ${DbArvores.codigo3} TEXT');
          await db.execute(
              'ALTER TABLE ${DbArvores.tableName} ADD COLUMN ${DbArvores.tora} TEXT');

          await db.execute(
              'ALTER TABLE ${DbTalhoes.tableName} ADD COLUMN ${DbTalhoes.bloco} TEXT');
          await db.execute(
              'ALTER TABLE ${DbTalhoes.tableName} ADD COLUMN ${DbTalhoes.up} TEXT');
          await db.execute(
              'ALTER TABLE ${DbTalhoes.tableName} ADD COLUMN ${DbTalhoes.materialGenetico} TEXT');
          await db.execute(
              'ALTER TABLE ${DbTalhoes.tableName} ADD COLUMN ${DbTalhoes.dataPlantio} TEXT');

          await db.execute(
              'ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.altitude} REAL');
          await db.execute(
              'ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.referenciaRf} TEXT');
          await db.execute(
              'ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.ciclo} TEXT');
          await db.execute(
              'ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.rotacao} INTEGER');
          await db.execute(
              'ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.tipoParcela} TEXT');
          await db.execute(
              'ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.formaParcela} TEXT');
          await db.execute(
              'ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.lado1} REAL');
          await db.execute(
              'ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.lado2} REAL');

          if (await _columnExists(db, DbParcelas.tableName, 'raio')) {
            await db.execute(
                'UPDATE ${DbParcelas.tableName} SET ${DbParcelas.lado1} = raio WHERE raio IS NOT NULL');
          }
          if (await _columnExists(db, DbParcelas.tableName, 'largura')) {
            await db.execute(
                'UPDATE ${DbParcelas.tableName} SET ${DbParcelas.lado1} = largura WHERE largura IS NOT NULL AND ${DbParcelas.lado1} IS NULL');
          }
          if (await _columnExists(db, DbParcelas.tableName, 'comprimento')) {
            await db.execute(
                'UPDATE ${DbParcelas.tableName} SET ${DbParcelas.lado2} = comprimento WHERE comprimento IS NOT NULL');
          }

          await db.transaction((txn) async {
            await txn.execute('''
                CREATE TABLE parcelas_temp AS SELECT 
                  ${DbParcelas.id}, ${DbParcelas.uuid}, ${DbParcelas.talhaoId}, ${DbParcelas.nomeFazenda}, ${DbParcelas.nomeTalhao}, ${DbParcelas.idParcela}, ${DbParcelas.areaMetrosQuadrados}, 
                  ${DbParcelas.observacao}, ${DbParcelas.latitude}, ${DbParcelas.longitude}, ${DbParcelas.altitude}, ${DbParcelas.dataColeta}, ${DbParcelas.status}, ${DbParcelas.exportada}, ${DbParcelas.isSynced}, 
                  ${DbParcelas.idFazenda}, ${DbParcelas.photoPaths}, ${DbParcelas.nomeLider}, ${DbParcelas.projetoId}, ${DbParcelas.municipio}, ${DbParcelas.estado}, ${DbParcelas.up}, ${DbParcelas.referenciaRf}, 
                  ${DbParcelas.ciclo}, ${DbParcelas.rotacao}, ${DbParcelas.tipoParcela}, ${DbParcelas.formaParcela}, ${DbParcelas.lado1}, ${DbParcelas.lado2}, ${DbParcelas.lastModified} 
                FROM ${DbParcelas.tableName}
              ''');
            await txn.execute('DROP TABLE ${DbParcelas.tableName}');
            await txn.execute(
                'ALTER TABLE parcelas_temp RENAME TO ${DbParcelas.tableName}');
          });
          break;
        case 42:
          await db.execute(
              'ALTER TABLE ${DbCubagensArvores.tableName} ADD COLUMN ${DbCubagensArvores.observacao} TEXT');
          await db.execute(
              'ALTER TABLE ${DbCubagensArvores.tableName} ADD COLUMN ${DbCubagensArvores.latitude} REAL');
          await db.execute(
              'ALTER TABLE ${DbCubagensArvores.tableName} ADD COLUMN ${DbCubagensArvores.longitude} REAL');
          break;
        case 43:
          await db.execute(
              'ALTER TABLE ${DbCubagensArvores.tableName} ADD COLUMN ${DbCubagensArvores.metodoCubagem} TEXT');
          break;
        case 44:
          await db.execute(
              'ALTER TABLE ${DbCubagensArvores.tableName} ADD COLUMN ${DbCubagensArvores.rf} TEXT');
          break;
        case 45:
          await db.execute('''
            CREATE TABLE diario_de_campo_temp (
              ${DbDiarioDeCampo.id} INTEGER PRIMARY KEY AUTOINCREMENT,
              ${DbDiarioDeCampo.dataRelatorio} TEXT NOT NULL,
              ${DbDiarioDeCampo.nomeLider} TEXT NOT NULL,
              ${DbDiarioDeCampo.projetoId} INTEGER NOT NULL,
              ${DbDiarioDeCampo.talhaoId} INTEGER,
              ${DbDiarioDeCampo.kmInicial} REAL, ${DbDiarioDeCampo.kmFinal} REAL, ${DbDiarioDeCampo.localizacaoDestino} TEXT,
              ${DbDiarioDeCampo.pedagioValor} REAL, ${DbDiarioDeCampo.abastecimentoValor} REAL,
              ${DbDiarioDeCampo.alimentacaoMarmitasQtd} INTEGER, ${DbDiarioDeCampo.alimentacaoRefeicaoValor} REAL,
              ${DbDiarioDeCampo.alimentacaoDescricao} TEXT, ${DbDiarioDeCampo.veiculoPlaca} TEXT,
              ${DbDiarioDeCampo.veiculoModelo} TEXT, ${DbDiarioDeCampo.equipeNoCarro} TEXT, ${DbDiarioDeCampo.lastModified} TEXT NOT NULL,
              UNIQUE(${DbDiarioDeCampo.dataRelatorio}, ${DbDiarioDeCampo.nomeLider})
            )
          ''');
          await db.execute('''
            INSERT INTO diario_de_campo_temp (${DbDiarioDeCampo.id}, ${DbDiarioDeCampo.dataRelatorio}, ${DbDiarioDeCampo.nomeLider}, ${DbDiarioDeCampo.projetoId}, ${DbDiarioDeCampo.talhaoId}, ${DbDiarioDeCampo.kmInicial}, ${DbDiarioDeCampo.kmFinal}, ${DbDiarioDeCampo.localizacaoDestino}, ${DbDiarioDeCampo.pedagioValor}, ${DbDiarioDeCampo.abastecimentoValor}, ${DbDiarioDeCampo.alimentacaoMarmitasQtd}, ${DbDiarioDeCampo.alimentacaoRefeicaoValor}, ${DbDiarioDeCampo.alimentacaoDescricao}, ${DbDiarioDeCampo.veiculoPlaca}, ${DbDiarioDeCampo.veiculoModelo}, ${DbDiarioDeCampo.equipeNoCarro}, ${DbDiarioDeCampo.lastModified})
            SELECT ${DbDiarioDeCampo.id}, ${DbDiarioDeCampo.dataRelatorio}, ${DbDiarioDeCampo.nomeLider}, ${DbDiarioDeCampo.projetoId}, ${DbDiarioDeCampo.talhaoId}, ${DbDiarioDeCampo.kmInicial}, ${DbDiarioDeCampo.kmFinal}, ${DbDiarioDeCampo.localizacaoDestino}, ${DbDiarioDeCampo.pedagioValor}, ${DbDiarioDeCampo.abastecimentoValor}, ${DbDiarioDeCampo.alimentacaoMarmitasQtd}, ${DbDiarioDeCampo.alimentacaoRefeicaoValor}, ${DbDiarioDeCampo.alimentacaoDescricao}, ${DbDiarioDeCampo.veiculoPlaca}, ${DbDiarioDeCampo.veiculoModelo}, ${DbDiarioDeCampo.equipeNoCarro}, ${DbDiarioDeCampo.lastModified}
            FROM ${DbDiarioDeCampo.tableName}
            GROUP BY ${DbDiarioDeCampo.dataRelatorio}, ${DbDiarioDeCampo.nomeLider}
          ''');
          await db.execute('DROP TABLE ${DbDiarioDeCampo.tableName}');
          await db.execute(
              'ALTER TABLE diario_de_campo_temp RENAME TO ${DbDiarioDeCampo.tableName}');
          break;
        case 46:
          await db.execute(
              'ALTER TABLE ${DbCubagensArvores.tableName} ADD COLUMN ${DbCubagensArvores.dataColeta} TEXT');
          await db.execute(
              'UPDATE ${DbCubagensArvores.tableName} SET ${DbCubagensArvores.dataColeta} = ${DbCubagensArvores.lastModified} WHERE ${DbCubagensArvores.dataColeta} IS NULL');
          break;
        case 47:
          if (!await _columnExists(db, DbDiarioDeCampo.tableName,
              DbDiarioDeCampo.outrasDespesasValor)) {
            await db.execute(
                'ALTER TABLE ${DbDiarioDeCampo.tableName} ADD COLUMN ${DbDiarioDeCampo.outrasDespesasValor} REAL');
          }
          if (!await _columnExists(db, DbDiarioDeCampo.tableName,
              DbDiarioDeCampo.outrasDespesasDescricao)) {
            await db.execute(
                'ALTER TABLE ${DbDiarioDeCampo.tableName} ADD COLUMN ${DbDiarioDeCampo.outrasDespesasDescricao} TEXT');
          }
          break;
        case 48:
          if (!await _columnExists(
              db, DbParcelas.tableName, DbParcelas.declividade)) {
            await db.execute(
                'ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.declividade} REAL');
          }
          break;
        case 49:
          if (!await _columnExists(db, 'parcelas', 'arvores')) {
            await db.execute('ALTER TABLE parcelas ADD COLUMN arvores TEXT');
          }
          break;
        case 50:
          if (!await _columnExists(db, 'cubagens_arvores', 'secoes')) {
            await db
                .execute('ALTER TABLE cubagens_arvores ADD COLUMN secoes TEXT');
          }
          break;
        case 51:
          await db.execute('''
            CREATE TABLE checklist_veicular (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              data_registro TEXT NOT NULL,
              uid_usuario TEXT,
              nome_motorista TEXT,
              placa TEXT,
              km_atual REAL,
              modelo_veiculo TEXT,
              prefixo TEXT,           
              categoria_cnh TEXT,     
              vencimento_cnh TEXT,    
              is_motorista INTEGER NOT NULL,
              itens_json TEXT,
              observacoes TEXT,
              lastModified TEXT NOT NULL
            )
          ''');
          break;
           case 60:
          // AQUI É A CHAVE: Forçamos a criação mesmo se já tiver tentado antes
          debugPrint(">>> EXECUTANDO MIGRAÇÃO V60 (ESPECIES) <<<");

          // 1. Limpa se já existir (para evitar erros em testes repetidos)
          await db.execute('DROP TABLE IF EXISTS especies');

          // 2. Cria tabela
          await db.execute('''
            CREATE TABLE especies (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nome_cientifico TEXT NOT NULL,
              nome_comum TEXT NOT NULL,
              familia TEXT,
              fator_forma REAL,
              regiao TEXT
            )
          ''');

          // 3. Atualiza arvores (safe check)
          if (!await _columnExists(db, 'arvores', 'especie')) {
             try {
                await db.execute('ALTER TABLE arvores ADD COLUMN especie TEXT');
             } catch (e) {
                debugPrint("Erro ao adicionar coluna especie: $e");
             }
          }

          // 4. Popula
          await _popularTabelaEspecies(db);
          break;
        case 61:
          debugPrint(">>> EXECUTANDO MIGRAÇÃO V61 (Adicionando atividadeTipo em parcelas) <<<");
          // Verifica se a coluna já existe antes de tentar adicionar (medida de segurança)
          if (!await _columnExists(db, DbParcelas.tableName, DbParcelas.atividadeTipo)) {
            try {
              await db.execute('ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.atividadeTipo} TEXT');
              debugPrint("Coluna atividadeTipo adicionada com sucesso.");
            } catch (e) {
              debugPrint("Erro ao adicionar coluna atividadeTipo: $e");
            }
          }
          break;
        case 62:
          debugPrint(">>> EXECUTANDO MIGRAÇÃO V62 (Adicionando fotos na árvore e parcela) <<<");
          
          // Garante foto na ÁRVORE (Individual)
          if (!await _columnExists(db, DbArvores.tableName, DbArvores.photoPaths)) {
            try {
              await db.execute('ALTER TABLE ${DbArvores.tableName} ADD COLUMN ${DbArvores.photoPaths} TEXT');
              debugPrint("Coluna photoPaths adicionada em ARVORES.");
            } catch (e) { debugPrint("Erro em Arvores: $e"); }
          }

          // Garante foto na PARCELA (Geral)
          if (!await _columnExists(db, DbParcelas.tableName, DbParcelas.photoPaths)) {
            try {
              await db.execute('ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.photoPaths} TEXT');
              debugPrint("Coluna photoPaths adicionada em PARCELAS.");
            } catch (e) { debugPrint("Erro em Parcelas: $e"); }
          }
          break;
        case 63:
          debugPrint(">>> EXECUTANDO MIGRAÇÃO V63 (Fotos Checklist) <<<");
          if (!await _columnExists(db, 'checklist_veicular', 'fotos_avarias')) {
            try {
              await db.execute('ALTER TABLE checklist_veicular ADD COLUMN fotos_avarias TEXT');
              debugPrint("Coluna fotos_avarias adicionada.");
            } catch (e) {
              debugPrint("Erro ao adicionar coluna fotos_avarias: $e");
            }
          }
          break;
        case 64:
          debugPrint(">>> EXECUTANDO MIGRAÇÃO V64 (Suporte a Suta no inventário) <<<");
          for (final coluna in [DbArvores.tipoMedidaCAP, DbArvores.medidaSuta1, DbArvores.medidaSuta2]) {
            if (!await _columnExists(db, DbArvores.tableName, coluna)) {
              try {
                final tipoSql = coluna == DbArvores.tipoMedidaCAP ? 'TEXT' : 'REAL';
                await db.execute('ALTER TABLE ${DbArvores.tableName} ADD COLUMN $coluna $tipoSql');
                debugPrint("Coluna $coluna adicionada em ARVORES.");
              } catch (e) { debugPrint("Erro ao adicionar coluna $coluna: $e"); }
            }
          }
          break;
        case 65:
          debugPrint(">>> EXECUTANDO MIGRAÇÃO V65 (Tipo de medição CAP/DAP por parcela) <<<");
          if (!await _columnExists(db, DbParcelas.tableName, DbParcelas.tipoMedidaCAP)) {
            try {
              await db.execute('ALTER TABLE ${DbParcelas.tableName} ADD COLUMN ${DbParcelas.tipoMedidaCAP} TEXT');
              debugPrint("Coluna ${DbParcelas.tipoMedidaCAP} adicionada em PARCELAS.");
            } catch (e) { debugPrint("Erro ao adicionar coluna ${DbParcelas.tipoMedidaCAP}: $e"); }
          }
          break;
        case 66:
          debugPrint(">>> EXECUTANDO MIGRAÇÃO V66 (Coordenada planejada da parcela) <<<");
          for (final coluna in [DbParcelas.latitudePlanejada, DbParcelas.longitudePlanejada]) {
            if (!await _columnExists(db, DbParcelas.tableName, coluna)) {
              try {
                await db.execute('ALTER TABLE ${DbParcelas.tableName} ADD COLUMN $coluna REAL');
                debugPrint("Coluna $coluna adicionada em PARCELAS.");
              } catch (e) { debugPrint("Erro ao adicionar coluna $coluna: $e"); }
            }
          }
          break;
        case 67:
          debugPrint(">>> EXECUTANDO MIGRAÇÃO V67 (Passo fixo de cubagem) <<<");
          if (!await _columnExists(db, DbCubagensArvores.tableName, DbCubagensArvores.passoFixo)) {
            try {
              await db.execute('ALTER TABLE ${DbCubagensArvores.tableName} ADD COLUMN ${DbCubagensArvores.passoFixo} REAL DEFAULT 2.0');
              debugPrint("Coluna ${DbCubagensArvores.passoFixo} adicionada em CUBAGENS_ARVORES.");
            } catch (e) { debugPrint("Erro ao adicionar coluna ${DbCubagensArvores.passoFixo}: $e"); }
          }
          break;
      }
    }
  }

  Future<bool> _columnExists(Database db, String table, String column) async {
    final result = await db.rawQuery('PRAGMA table_info($table)');
    return result.any((row) => row['name'] == column);
  }

  Future<void> _popularTabelaEspecies(Database db) async {
    try {
      final String csvData = await rootBundle.loadString('assets/data/especies.csv');
      final List<String> linhas = const LineSplitter().convert(csvData);
      final batch = db.batch();
      int count = 0;

      // Pula cabeçalho se existir
      int startIndex = 0;
      if (linhas.isNotEmpty && linhas[0].contains('NomeCientifico')) {
        startIndex = 1;
      }

      for (int i = startIndex; i < linhas.length; i++) {
        String linha = linhas[i];
        if (linha.trim().isEmpty) continue;
        
        var colunas = linha.split(';');
        if (colunas.length >= 3) {
          batch.insert('especies', {
            'nome_cientifico': colunas[0].trim(),
            'nome_comum': colunas[1].trim(),
            'familia': colunas[2].trim(),
            'fator_forma': colunas.length > 3 ? (double.tryParse(colunas[3].replaceAll(',', '.')) ?? 0.5) : 0.5,
            'regiao': colunas.length > 4 ? colunas[4].trim() : 'Cerrado'
          });
          count++;
        }
      }
      await batch.commit(noResult: true);
      debugPrint("Importação concluída: $count espécies adicionadas.");
    } catch (e) {
      debugPrint("ERRO ao importar espécies: $e");
    }
  }

  Future<void> deleteDatabaseFile() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
    try {
      final path = join(await getDatabasesPath(), 'geoforestv1.db');
      await deleteDatabase(path);
      debugPrint("Banco de dados apagado.");
    } catch (e) {
      debugPrint("Erro ao apagar banco: $e");
      rethrow;
    }
  }
}

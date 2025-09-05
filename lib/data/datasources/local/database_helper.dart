// lib/data/datasources/local/database_helper.dart (VERSÃO COM AS SUAS MELHORIAS)

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

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
      // Versão do banco permanece 48
      version: 48,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async => await db.execute('PRAGMA foreign_keys = ON');

  Future<void> _onCreate(Database db, int version) async {
    // ... (CREATEs de projetos, atividades, fazendas, talhoes)
    await db.execute('''
      CREATE TABLE projetos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        licenseId TEXT,
        nome TEXT NOT NULL,
        empresa TEXT NOT NULL,
        responsavel TEXT NOT NULL,
        dataCriacao TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'ativo',
        delegado_por_license_id TEXT,
        referencia_rf TEXT,
        lastModified TEXT NOT NULL 
      )
    ''');
    await db.execute('''
      CREATE TABLE atividades (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        projetoId INTEGER NOT NULL,
        tipo TEXT NOT NULL,
        descricao TEXT NOT NULL,
        dataCriacao TEXT NOT NULL,
        metodoCubagem TEXT,
        lastModified TEXT NOT NULL, 
        FOREIGN KEY (projetoId) REFERENCES projetos (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE fazendas (
        id TEXT NOT NULL,
        atividadeId INTEGER NOT NULL,
        nome TEXT NOT NULL,
        municipio TEXT NOT NULL,
        estado TEXT NOT NULL,
        lastModified TEXT NOT NULL,
        PRIMARY KEY (id, atividadeId),
        FOREIGN KEY (atividadeId) REFERENCES atividades (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE talhoes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fazendaId TEXT NOT NULL,
        fazendaAtividadeId INTEGER NOT NULL,
        projetoId INTEGER, 
        nome TEXT NOT NULL,
        areaHa REAL,
        idadeAnos REAL,
        especie TEXT,
        espacamento TEXT,
        bloco TEXT,
        up TEXT,
        material_genetico TEXT,
        data_plantio TEXT,
        lastModified TEXT NOT NULL, 
        FOREIGN KEY (fazendaId, fazendaAtividadeId) REFERENCES fazendas (id, atividadeId) ON DELETE CASCADE
      )
    ''');
    
    // <<< MELHORIA 1 APLICADA: Coluna 'declividade' adicionada ao CREATE TABLE >>>
    await db.execute('''
      CREATE TABLE parcelas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        talhaoId INTEGER,
        nomeFazenda TEXT,
        nomeTalhao TEXT,
        idParcela TEXT NOT NULL,
        areaMetrosQuadrados REAL NOT NULL,
        observacao TEXT,
        latitude REAL,
        longitude REAL,
        altitude REAL,
        dataColeta TEXT NOT NULL,
        status TEXT NOT NULL,
        exportada INTEGER DEFAULT 0 NOT NULL,
        isSynced INTEGER DEFAULT 0 NOT NULL,
        idFazenda TEXT,
        photoPaths TEXT,
        nomeLider TEXT,
        projetoId INTEGER,
        municipio TEXT, 
        estado TEXT,
        up TEXT,
        referencia_rf TEXT,
        ciclo TEXT,
        rotacao INTEGER,
        tipo_parcela TEXT,
        forma_parcela TEXT,
        lado1 REAL,
        lado2 REAL,
        declividade REAL, -- <<< COLUNA ADICIONADA AQUI
        lastModified TEXT NOT NULL,
        FOREIGN KEY (talhaoId) REFERENCES talhoes (id) ON DELETE CASCADE
      )
    ''');
    
    // ... (CREATEs de arvores, cubagens_arvores, etc. permanecem os mesmos)
    await db.execute('''
      CREATE TABLE arvores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parcelaId INTEGER NOT NULL,
        cap REAL NOT NULL,
        altura REAL,
        alturaDano REAL,
        linha INTEGER NOT NULL,
        posicaoNaLinha INTEGER NOT NULL,
        fimDeLinha INTEGER NOT NULL,
        dominante INTEGER NOT NULL,
        codigo TEXT NOT NULL,
        codigo2 TEXT,
        codigo3 TEXT,
        tora TEXT,
        observacao TEXT,
        capAuditoria REAL,
        alturaAuditoria REAL,
        lastModified TEXT NOT NULL,
        FOREIGN KEY (parcelaId) REFERENCES parcelas (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE cubagens_arvores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        talhaoId INTEGER,
        id_fazenda TEXT,
        nome_fazenda TEXT,
        nome_talhao TEXT,
        identificador TEXT NOT NULL,
        alturaTotal REAL NOT NULL,
        tipoMedidaCAP TEXT NOT NULL,
        valorCAP REAL NOT NULL,
        alturaBase REAL NOT NULL,
        classe TEXT,
        observacao TEXT,
        latitude REAL,
        longitude REAL,
        metodoCubagem TEXT,
        rf TEXT,
        dataColeta TEXT,
        exportada INTEGER DEFAULT 0 NOT NULL,
        isSynced INTEGER DEFAULT 0 NOT NULL,
        nomeLider TEXT,
        lastModified TEXT NOT NULL,
        FOREIGN KEY (talhaoId) REFERENCES talhoes (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE cubagens_secoes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cubagemArvoreId INTEGER NOT NULL,
        alturaMedicao REAL NOT NULL,
        circunferencia REAL,
        casca1_mm REAL,
        casca2_mm REAL,
        lastModified TEXT NOT NULL,
        FOREIGN KEY (cubagemArvoreId) REFERENCES cubagens_arvores (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE sortimentos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        comprimento REAL NOT NULL,
        diametroMinimo REAL NOT NULL,
        diametroMaximo REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE diario_de_campo (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        data_relatorio TEXT NOT NULL,
        nome_lider TEXT NOT NULL,
        projeto_id INTEGER NOT NULL,
        talhao_id INTEGER,
        km_inicial REAL,
        km_final REAL,
        localizacao_destino TEXT,
        pedagio_valor REAL,
        abastecimento_valor REAL,
        alimentacao_marmitas_qtd INTEGER,
        alimentacao_refeicao_valor REAL,
        alimentacao_descricao TEXT,
        outras_despesas_valor REAL,
        outras_despesas_descricao TEXT,
        veiculo_placa TEXT,
        veiculo_modelo TEXT,
        equipe_no_carro TEXT,
        lastModified TEXT NOT NULL,
        UNIQUE(data_relatorio, nome_lider)
      )
    ''');
    
    await db.execute('CREATE INDEX idx_arvores_parcelaId ON arvores(parcelaId)');
    await db.execute('CREATE INDEX idx_cubagens_secoes_cubagemArvoreId ON cubagens_secoes(cubagemArvoreId)');
  }


  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (var v = oldVersion + 1; v <= newVersion; v++) {
      debugPrint("Executando migração de banco de dados para a versão $v...");
      switch (v) {
        // ... (casos de 25 a 46 permanecem os mesmos)
        case 25:
          await db.execute('ALTER TABLE parcelas ADD COLUMN uuid TEXT');
          final parcelasSemUuid = await db.query('parcelas', where: 'uuid IS NULL');
          for (final p in parcelasSemUuid) {
            await db.update('parcelas', {'uuid': const Uuid().v4()}, where: 'id = ?', whereArgs: [p['id']]);
          }
          break;
        case 26:
          await db.execute('ALTER TABLE cubagens_arvores ADD COLUMN isSynced INTEGER DEFAULT 0 NOT NULL');
          break;
        case 27:
          await db.execute("ALTER TABLE projetos ADD COLUMN status TEXT NOT NULL DEFAULT 'ativo'");
          break;
        case 28:
          await db.execute("ALTER TABLE parcelas ADD COLUMN nomeLider TEXT");
          await db.execute("ALTER TABLE parcelas ADD COLUMN projetoId INTEGER");
          break;
        case 29:
          await db.execute("ALTER TABLE projetos ADD COLUMN licenseId TEXT");
          break;
        case 30:
          await db.execute("ALTER TABLE projetos ADD COLUMN delegado_por_license_id TEXT");
          break;
        case 31:
          await db.execute("ALTER TABLE cubagens_arvores ADD COLUMN nomeLider TEXT");
          break;
        case 32:
          await db.execute("ALTER TABLE parcelas ADD COLUMN municipio TEXT");
          await db.execute("ALTER TABLE parcelas ADD COLUMN estado TEXT");
          break;
        case 33:
          await db.execute("ALTER TABLE projetos ADD COLUMN lastModified TEXT");
          await db.execute("ALTER TABLE atividades ADD COLUMN lastModified TEXT");
          await db.execute("ALTER TABLE fazendas ADD COLUMN lastModified TEXT");
          await db.execute("ALTER TABLE talhoes ADD COLUMN lastModified TEXT");
          await db.execute("ALTER TABLE parcelas ADD COLUMN lastModified TEXT");
          await db.execute("ALTER TABLE arvores ADD COLUMN lastModified TEXT");
          await db.execute("ALTER TABLE cubagens_arvores ADD COLUMN lastModified TEXT");
          await db.execute("ALTER TABLE cubagens_secoes ADD COLUMN lastModified TEXT");
    
          final now = DateTime.now().toIso8601String();
          await db.update('projetos', {'lastModified': now}, where: 'lastModified IS NULL');
          await db.update('atividades', {'lastModified': now}, where: 'lastModified IS NULL');
          await db.update('fazendas', {'lastModified': now}, where: 'lastModified IS NULL');
          await db.update('talhoes', {'lastModified': now}, where: 'lastModified IS NULL');
          await db.update('parcelas', {'lastModified': now}, where: 'lastModified IS NULL');
          await db.update('arvores', {'lastModified': now}, where: 'lastModified IS NULL');
          await db.update('cubagens_arvores', {'lastModified': now}, where: 'lastModified IS NULL');
          await db.update('cubagens_secoes', {'lastModified': now}, where: 'lastModified IS NULL');
          break;
        case 34:
          await db.execute('ALTER TABLE talhoes ADD COLUMN projetoId INTEGER');
          break;
        case 35:
          await db.execute('ALTER TABLE projetos ADD COLUMN referencia_rf TEXT');
          break;
        case 36:
          await db.execute('''
            CREATE TABLE diario_de_campo (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              data_relatorio TEXT NOT NULL, nome_lider TEXT NOT NULL, projeto_id INTEGER NOT NULL,
              talhao_id INTEGER NOT NULL, km_inicial REAL, km_final REAL, localizacao_destino TEXT,
              pedagio_valor REAL, abastecimento_valor REAL, alimentacao_marmitas_qtd INTEGER,
              alimentacao_refeicao_valor REAL, alimentacao_descricao TEXT, veiculo_placa TEXT,
              veiculo_modelo TEXT, equipe_no_carro TEXT, lastModified TEXT NOT NULL,
              UNIQUE(data_relatorio, nome_lider, talhao_id)
            )
          ''');
          break;
        case 37:
           await db.execute('ALTER TABLE arvores ADD COLUMN alturaDano REAL');
          break;
        case 38:
          await db.execute('ALTER TABLE parcelas ADD COLUMN up TEXT');
          break;
        case 39:
          try {
            await db.execute('ALTER TABLE parcelas ADD COLUMN up_temp_string TEXT');
            await db.execute('UPDATE parcelas SET up_temp_string = up');
            await db.execute('ALTER TABLE parcelas DROP COLUMN up');
            await db.execute('ALTER TABLE parcelas RENAME COLUMN up_temp_string TO up');
          } catch (e) {
            debugPrint("Aviso na migração 39 (esperado se a coluna 'up' já era TEXT): $e");
            if (!await _columnExists(db, 'parcelas', 'up')) {
              await db.execute('ALTER TABLE parcelas ADD COLUMN up TEXT');
            }
          }
          break;
        
        case 40:
          debugPrint("Migração v40 pulada, lógica incorporada na v41.");
          break;

        case 41:
          await db.execute('ALTER TABLE arvores ADD COLUMN codigo3 TEXT');
          await db.execute('ALTER TABLE arvores ADD COLUMN tora TEXT');
          
          await db.execute('ALTER TABLE talhoes ADD COLUMN bloco TEXT');
          await db.execute('ALTER TABLE talhoes ADD COLUMN up TEXT');
          await db.execute('ALTER TABLE talhoes ADD COLUMN material_genetico TEXT');
          await db.execute('ALTER TABLE talhoes ADD COLUMN data_plantio TEXT');
          
          await db.execute('ALTER TABLE parcelas ADD COLUMN altitude REAL');
          await db.execute('ALTER TABLE parcelas ADD COLUMN referencia_rf TEXT');
          await db.execute('ALTER TABLE parcelas ADD COLUMN ciclo TEXT');
          await db.execute('ALTER TABLE parcelas ADD COLUMN rotacao INTEGER');
          await db.execute('ALTER TABLE parcelas ADD COLUMN tipo_parcela TEXT');
          await db.execute('ALTER TABLE parcelas ADD COLUMN forma_parcela TEXT');
          await db.execute('ALTER TABLE parcelas ADD COLUMN lado1 REAL');
          await db.execute('ALTER TABLE parcelas ADD COLUMN lado2 REAL');
          
          if(await _columnExists(db, 'parcelas', 'raio')) {
            await db.execute('UPDATE parcelas SET lado1 = raio WHERE raio IS NOT NULL');
          }
          if(await _columnExists(db, 'parcelas', 'largura')) {
            await db.execute('UPDATE parcelas SET lado1 = largura WHERE largura IS NOT NULL AND lado1 IS NULL');
          }
           if(await _columnExists(db, 'parcelas', 'comprimento')) {
            await db.execute('UPDATE parcelas SET lado2 = comprimento WHERE comprimento IS NOT NULL');
          }

          await db.transaction((txn) async {
              await txn.execute('''
                CREATE TABLE parcelas_temp AS SELECT 
                  id, uuid, talhaoId, nomeFazenda, nomeTalhao, idParcela, areaMetrosQuadrados, 
                  observacao, latitude, longitude, altitude, dataColeta, status, exportada, isSynced, 
                  idFazenda, photoPaths, nomeLider, projetoId, municipio, estado, up, referencia_rf, 
                  ciclo, rotacao, tipo_parcela, forma_parcela, lado1, lado2, lastModified 
                FROM parcelas
              ''');
              await txn.execute('DROP TABLE parcelas');
              await txn.execute('ALTER TABLE parcelas_temp RENAME TO parcelas');
          });
          break;
        
        case 42:
          await db.execute('ALTER TABLE cubagens_arvores ADD COLUMN observacao TEXT');
          await db.execute('ALTER TABLE cubagens_arvores ADD COLUMN latitude REAL');
          await db.execute('ALTER TABLE cubagens_arvores ADD COLUMN longitude REAL');
          break;

        case 43:
          await db.execute('ALTER TABLE cubagens_arvores ADD COLUMN metodoCubagem TEXT');
          break;
        case 44:
          await db.execute('ALTER TABLE cubagens_arvores ADD COLUMN rf TEXT');
          break;
          
        case 45:
          await db.execute('''
            CREATE TABLE diario_de_campo_temp (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              data_relatorio TEXT NOT NULL,
              nome_lider TEXT NOT NULL,
              projeto_id INTEGER NOT NULL,
              talhao_id INTEGER,
              km_inicial REAL, km_final REAL, localizacao_destino TEXT,
              pedagio_valor REAL, abastecimento_valor REAL,
              alimentacao_marmitas_qtd INTEGER, alimentacao_refeicao_valor REAL,
              alimentacao_descricao TEXT, veiculo_placa TEXT,
              veiculo_modelo TEXT, equipe_no_carro TEXT, lastModified TEXT NOT NULL,
              UNIQUE(data_relatorio, nome_lider)
            )
          ''');
          await db.execute('''
            INSERT INTO diario_de_campo_temp (id, data_relatorio, nome_lider, projeto_id, talhao_id, km_inicial, km_final, localizacao_destino, pedagio_valor, abastecimento_valor, alimentacao_marmitas_qtd, alimentacao_refeicao_valor, alimentacao_descricao, veiculo_placa, veiculo_modelo, equipe_no_carro, lastModified)
            SELECT id, data_relatorio, nome_lider, projeto_id, talhao_id, km_inicial, km_final, localizacao_destino, pedagio_valor, abastecimento_valor, alimentacao_marmitas_qtd, alimentacao_refeicao_valor, alimentacao_descricao, veiculo_placa, veiculo_modelo, equipe_no_carro, lastModified
            FROM diario_de_campo
            GROUP BY data_relatorio, nome_lider
          ''');
          await db.execute('DROP TABLE diario_de_campo');
          await db.execute('ALTER TABLE diario_de_campo_temp RENAME TO diario_de_campo');
          break;
          
        case 46:
          await db.execute('ALTER TABLE cubagens_arvores ADD COLUMN dataColeta TEXT');
          await db.execute('UPDATE cubagens_arvores SET dataColeta = lastModified WHERE dataColeta IS NULL');
          break;

        case 47:
          if (!await _columnExists(db, 'diario_de_campo', 'outras_despesas_valor')) {
            await db.execute('ALTER TABLE diario_de_campo ADD COLUMN outras_despesas_valor REAL');
          }
          if (!await _columnExists(db, 'diario_de_campo', 'outras_despesas_descricao')) {
            await db.execute('ALTER TABLE diario_de_campo ADD COLUMN outras_despesas_descricao TEXT');
          }
          break;

        // <<< MELHORIA 2 APLICADA: Verificação de existência da coluna antes de adicioná-la >>>
        case 48:
          if (!await _columnExists(db, 'parcelas', 'declividade')) {
            await db.execute('ALTER TABLE parcelas ADD COLUMN declividade REAL');
          }
          break;
      }
    }
  }
  
  /// Função auxiliar para verificar se uma coluna existe antes de tentar modificá-la
  Future<bool> _columnExists(Database db, String table, String column) async {
    final result = await db.rawQuery('PRAGMA table_info($table)');
    return result.any((row) => row['name'] == column);
  }

  Future<void> deleteDatabaseFile() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
    try {
      final path = join(await getDatabasesPath(), 'geoforestv1.db');
      await deleteDatabase(path);
      debugPrint("Banco de dados local completamente apagado com sucesso.");
    } catch (e) {
      debugPrint("!!!!!! ERRO AO APAGAR O BANCO DE DADOS: $e !!!!!");
      rethrow;
    }
  }
}
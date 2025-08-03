// lib/data/datasources/local/database_helper.dart (VERSÃO REALMENTE COMPLETA E CORRIGIDA)

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

// <<< DEFINIÇÕES COMPLETAS RESTAURADAS >>>
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

void _initializeProj4InIsolate(Map<int, String> definitions) {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  proj4.Projection.add('EPSG:4326', '+proj=longlat +datum=WGS84 +no_defs');
  definitions.forEach((epsg, def) {
    proj4.Projection.add('EPSG:$epsg', def);
  });
}

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._privateConstructor();
  static Database? _database;

  DatabaseHelper._privateConstructor();
  factory DatabaseHelper() => _instance;
  static DatabaseHelper get instance => _instance;

  Future<Database> get database async => _database ??= await _initDatabase();

  Future<Database> _initDatabase() async {
    await compute(_initializeProj4InIsolate, proj4Definitions);
    
    return await openDatabase(
      join(await getDatabasesPath(), 'geoforestv1.db'),
      version: 31, 
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async => await db.execute('PRAGMA foreign_keys = ON');

  Future<void> _onCreate(Database db, int version) async {
     await db.execute('''
      CREATE TABLE projetos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        licenseId TEXT,
        nome TEXT NOT NULL,
        empresa TEXT NOT NULL,
        responsavel TEXT NOT NULL,
        dataCriacao TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'ativo',
        delegado_por_license_id TEXT
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
        PRIMARY KEY (id, atividadeId),
        FOREIGN KEY (atividadeId) REFERENCES atividades (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE talhoes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fazendaId TEXT NOT NULL,
        fazendaAtividadeId INTEGER NOT NULL,
        nome TEXT NOT NULL,
        areaHa REAL,
        idadeAnos REAL,
        especie TEXT,
        espacamento TEXT, 
        FOREIGN KEY (fazendaId, fazendaAtividadeId) REFERENCES fazendas (id, atividadeId) ON DELETE CASCADE
      )
    ''');
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
        dataColeta TEXT NOT NULL,
        status TEXT NOT NULL,
        exportada INTEGER DEFAULT 0 NOT NULL,
        isSynced INTEGER DEFAULT 0 NOT NULL,
        idFazenda TEXT,
        largura REAL,
        comprimento REAL,
        raio REAL,
        photoPaths TEXT,
        nomeLider TEXT,
        projetoId INTEGER,
        FOREIGN KEY (talhaoId) REFERENCES talhoes (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE arvores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parcelaId INTEGER NOT NULL,
        cap REAL NOT NULL,
        altura REAL,
        linha INTEGER NOT NULL,
        posicaoNaLinha INTEGER NOT NULL,
        fimDeLinha INTEGER NOT NULL,
        dominante INTEGER NOT NULL,
        codigo TEXT NOT NULL,
        codigo2 TEXT,
        observacao TEXT,
        capAuditoria REAL,
        alturaAuditoria REAL,
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
        exportada INTEGER DEFAULT 0 NOT NULL,
        isSynced INTEGER DEFAULT 0 NOT NULL,
        nomeLider TEXT,
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
    await db.execute('CREATE INDEX idx_arvores_parcelaId ON arvores(parcelaId)');
    await db.execute('CREATE INDEX idx_cubagens_secoes_cubagemArvoreId ON cubagens_secoes(cubagemArvoreId)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (var v = oldVersion + 1; v <= newVersion; v++) {
      debugPrint("Executando migração de banco de dados para a versão $v...");
       switch (v) {
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
      }
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
      debugPrint("Banco de dados local completamente apagado com sucesso.");
    } catch (e) {
      debugPrint("!!!!!! ERRO AO APAGAR O BANCO DE DADOS: $e !!!!!");
      rethrow;
    }
  }
}
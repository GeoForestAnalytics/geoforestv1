import 'package:geoforestv1/data/datasources/local/database_constants.dart';

class EstoqueSaida {
  final int? id;
  final int? talhaoId;
  final int? centroideId;
  final String? fazendaId;
  final String nomeFazenda;
  final String nomeTalhao;
  final String sortimento;
  final int numeroCaminhoes;
  final double volumeM3;
  final String? nomeLider;
  final String dataRegistro;
  final String? observacoes;
  final bool exportada;
  final bool isSynced;
  final String lastModified;

  const EstoqueSaida({
    this.id,
    this.talhaoId,
    this.centroideId,
    this.fazendaId,
    required this.nomeFazenda,
    required this.nomeTalhao,
    required this.sortimento,
    this.numeroCaminhoes = 0,
    required this.volumeM3,
    this.nomeLider,
    required this.dataRegistro,
    this.observacoes,
    this.exportada = false,
    this.isSynced = false,
    required this.lastModified,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) DbEstoqueSaida.id: id,
        DbEstoqueSaida.talhaoId: talhaoId,
        DbEstoqueSaida.centroideId: centroideId,
        DbEstoqueSaida.fazendaId: fazendaId,
        DbEstoqueSaida.nomeFazenda: nomeFazenda,
        DbEstoqueSaida.nomeTalhao: nomeTalhao,
        DbEstoqueSaida.sortimento: sortimento,
        DbEstoqueSaida.numeroCaminhoes: numeroCaminhoes,
        DbEstoqueSaida.volumeM3: volumeM3,
        DbEstoqueSaida.nomeLider: nomeLider,
        DbEstoqueSaida.dataRegistro: dataRegistro,
        DbEstoqueSaida.observacoes: observacoes,
        DbEstoqueSaida.exportada: exportada ? 1 : 0,
        DbEstoqueSaida.isSynced: isSynced ? 1 : 0,
        DbEstoqueSaida.lastModified: lastModified,
      };

  factory EstoqueSaida.fromMap(Map<String, dynamic> m) => EstoqueSaida(
        id: m[DbEstoqueSaida.id] as int?,
        talhaoId: m[DbEstoqueSaida.talhaoId] as int?,
        centroideId: m[DbEstoqueSaida.centroideId] as int?,
        fazendaId: m[DbEstoqueSaida.fazendaId] as String?,
        nomeFazenda: m[DbEstoqueSaida.nomeFazenda] as String? ?? '',
        nomeTalhao: m[DbEstoqueSaida.nomeTalhao] as String? ?? '',
        sortimento: m[DbEstoqueSaida.sortimento] as String? ?? '',
        numeroCaminhoes: (m[DbEstoqueSaida.numeroCaminhoes] as num?)?.toInt() ?? 0,
        volumeM3: (m[DbEstoqueSaida.volumeM3] as num?)?.toDouble() ?? 0,
        nomeLider: m[DbEstoqueSaida.nomeLider] as String?,
        dataRegistro: m[DbEstoqueSaida.dataRegistro] as String? ?? '',
        observacoes: m[DbEstoqueSaida.observacoes] as String?,
        exportada: (m[DbEstoqueSaida.exportada] as int?) == 1,
        isSynced: (m[DbEstoqueSaida.isSynced] as int?) == 1,
        lastModified: m[DbEstoqueSaida.lastModified] as String? ?? '',
      );

  EstoqueSaida copyWith({int? id, bool? exportada, bool? isSynced}) => EstoqueSaida(
        id: id ?? this.id,
        talhaoId: talhaoId,
        centroideId: centroideId,
        fazendaId: fazendaId,
        nomeFazenda: nomeFazenda,
        nomeTalhao: nomeTalhao,
        sortimento: sortimento,
        numeroCaminhoes: numeroCaminhoes,
        volumeM3: volumeM3,
        nomeLider: nomeLider,
        dataRegistro: dataRegistro,
        observacoes: observacoes,
        exportada: exportada ?? this.exportada,
        isSynced: isSynced ?? this.isSynced,
        lastModified: lastModified,
      );
}

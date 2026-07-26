import 'dart:convert';
import 'package:geoforestv1/data/datasources/local/database_constants.dart';

class SortimentoConfig {
  final String nome;
  final double? dapMin;
  final double? dapMax;
  final double comprimentoTora;
  final double? volumeEsperadoM3;
  final double fatorEmpilhamento;

  const SortimentoConfig({
    required this.nome,
    this.dapMin,
    this.dapMax,
    required this.comprimentoTora,
    this.volumeEsperadoM3,
    this.fatorEmpilhamento = 0.65,
  });

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'dapMin': dapMin,
        'dapMax': dapMax,
        'comprimentoTora': comprimentoTora,
        'volumeEsperadoM3': volumeEsperadoM3,
        'fatorEmpilhamento': fatorEmpilhamento,
      };

  factory SortimentoConfig.fromMap(Map<String, dynamic> m) => SortimentoConfig(
        nome: m['nome'] as String? ?? '',
        dapMin: (m['dapMin'] as num?)?.toDouble(),
        dapMax: (m['dapMax'] as num?)?.toDouble(),
        comprimentoTora: (m['comprimentoTora'] as num?)?.toDouble() ?? 2.4,
        volumeEsperadoM3: (m['volumeEsperadoM3'] as num?)?.toDouble(),
        fatorEmpilhamento: (m['fatorEmpilhamento'] as num?)?.toDouble() ?? 0.65,
      );

  String get descricaoClasse {
    if (dapMin != null && dapMax != null) return '${dapMin!.toStringAsFixed(0)}–${dapMax!.toStringAsFixed(0)} cm DAP';
    if (dapMin != null) return '≥ ${dapMin!.toStringAsFixed(0)} cm DAP';
    if (dapMax != null) return '< ${dapMax!.toStringAsFixed(0)} cm DAP';
    return '';
  }
}

class SecaoPilha {
  final int posicao;
  final double distanciaMetros;
  double altura;

  SecaoPilha({required this.posicao, required this.distanciaMetros, this.altura = 0.0});

  Map<String, dynamic> toMap() => {
        'posicao': posicao,
        'distanciaMetros': distanciaMetros,
        'altura': altura,
      };

  factory SecaoPilha.fromMap(Map<String, dynamic> m) => SecaoPilha(
        posicao: (m['posicao'] as num?)?.toInt() ?? 0,
        distanciaMetros: (m['distanciaMetros'] as num?)?.toDouble() ?? 0.0,
        altura: (m['altura'] as num?)?.toDouble() ?? 0.0,
      );
}

class CentroidePilha {
  final int? id;
  final int? talhaoId;
  final String? fazendaId;
  final String nomeFazenda;
  final String nomeTalhao;
  final double latitude;
  final double longitude;
  final List<SortimentoConfig> sortimentos;

  const CentroidePilha({
    this.id,
    this.talhaoId,
    this.fazendaId,
    required this.nomeFazenda,
    required this.nomeTalhao,
    required this.latitude,
    required this.longitude,
    this.sortimentos = const [],
  });

  Map<String, dynamic> toMap() => {
        DbCentroidesPilha.id: id,
        DbCentroidesPilha.talhaoId: talhaoId,
        DbCentroidesPilha.fazendaId: fazendaId,
        DbCentroidesPilha.nomeFazenda: nomeFazenda,
        DbCentroidesPilha.nomeTalhao: nomeTalhao,
        DbCentroidesPilha.latitude: latitude,
        DbCentroidesPilha.longitude: longitude,
        DbCentroidesPilha.sortimentos: jsonEncode(sortimentos.map((s) => s.toMap()).toList()),
        DbCentroidesPilha.lastModified: DateTime.now().toIso8601String(),
      };

  factory CentroidePilha.fromMap(Map<String, dynamic> m) {
    List<SortimentoConfig> sortimentos = [];
    final raw = m[DbCentroidesPilha.sortimentos];
    if (raw != null) {
      try {
        final decoded = raw is String ? jsonDecode(raw) : raw;
        if (decoded is List) {
          sortimentos = decoded.map((s) => SortimentoConfig.fromMap(Map<String, dynamic>.from(s))).toList();
        }
      } catch (_) {}
    }
    return CentroidePilha(
      id: m[DbCentroidesPilha.id],
      talhaoId: m[DbCentroidesPilha.talhaoId],
      fazendaId: m[DbCentroidesPilha.fazendaId],
      nomeFazenda: m[DbCentroidesPilha.nomeFazenda] ?? '',
      nomeTalhao: m[DbCentroidesPilha.nomeTalhao] ?? '',
      latitude: (m[DbCentroidesPilha.latitude] as num?)?.toDouble() ?? 0.0,
      longitude: (m[DbCentroidesPilha.longitude] as num?)?.toDouble() ?? 0.0,
      sortimentos: sortimentos,
    );
  }
}

class PilhaMadeira {
  int? id;
  final int? talhaoId;
  final int? centroideId;
  final int numeroPilha;
  final String sortimento;
  final double? dapMin;
  final double? dapMax;
  final double comprimentoTora;
  final double? comprimentoToraReal;
  final double comprimentoPilha;
  List<SecaoPilha> secoes;
  double? alturaMedia;
  double? volumeBruto;
  final double? latitude;
  final double? longitude;
  final String? nomeFazenda;
  final String? nomeTalhao;
  final String? nomeLider;
  final DateTime? dataColeta;
  final String? observacoes;
  final List<String> fotos;
  final double fatorEmpilhamento;
  final bool exportada;
  final bool isSynced;
  final DateTime? lastModified;

  PilhaMadeira({
    this.id,
    this.talhaoId,
    this.centroideId,
    required this.numeroPilha,
    required this.sortimento,
    this.dapMin,
    this.dapMax,
    required this.comprimentoTora,
    this.comprimentoToraReal,
    required this.comprimentoPilha,
    this.secoes = const [],
    this.alturaMedia,
    this.volumeBruto,
    this.latitude,
    this.longitude,
    this.nomeFazenda,
    this.nomeTalhao,
    this.nomeLider,
    this.dataColeta,
    this.observacoes,
    this.fotos = const [],
    this.fatorEmpilhamento = 0.65,
    this.exportada = false,
    this.isSynced = false,
    this.lastModified,
  });

  // Regras de seção:
  // ≤5m → passo 1m | 5-10m → 2m | 10-30m → 3m | >30m → 5m
  // Início: 0,5m fixo; segundo ponto: 1,0m fixo; fim: comprimento-0,5m fixo.
  static List<SecaoPilha> gerarSecoes(double comprimento) {
    final double step;
    if (comprimento <= 5.0) {
      step = 1.0;
    } else if (comprimento <= 10.0) {
      step = 2.0;
    } else if (comprimento <= 30.0) {
      step = 3.0;
    } else {
      step = 5.0;
    }

    final double fimBorda = double.parse((comprimento - 0.5).toStringAsFixed(2));
    final List<double> posicoes = [0.5];

    if (comprimento > 1.5) {
      posicoes.add(1.0);
      double current = double.parse((1.0 + step).toStringAsFixed(2));
      while (current < fimBorda) {
        posicoes.add(current);
        current = double.parse((current + step).toStringAsFixed(2));
      }
    }

    if (posicoes.last < fimBorda) posicoes.add(fimBorda);

    return posicoes
        .asMap()
        .entries
        .map((e) => SecaoPilha(posicao: e.key + 1, distanciaMetros: e.value))
        .toList();
  }

  double calcularAlturaMedia() {
    if (secoes.isEmpty) return 0;
    return secoes.map((s) => s.altura).reduce((a, b) => a + b) / secoes.length;
  }

  // Volume total = cunha inicial (0→0,5m) + trapézios centrais + cunha final (comp-0,5m→comp)
  // Usa comprimentoToraReal se informado no campo; caso contrário, usa o da OS.
  double calcularVolumeBruto() {
    if (secoes.isEmpty) return 0;
    final tora = comprimentoToraReal ?? comprimentoTora;
    double volume = 0;

    if (secoes.first.distanciaMetros > 0) {
      volume += (secoes.first.altura / 2) * secoes.first.distanciaMetros * tora;
    }
    for (int i = 0; i < secoes.length - 1; i++) {
      final L = secoes[i + 1].distanciaMetros - secoes[i].distanciaMetros;
      volume += ((secoes[i].altura + secoes[i + 1].altura) / 2) * L * tora;
    }
    if (secoes.last.distanciaMetros < comprimentoPilha) {
      volume += (secoes.last.altura / 2) * (comprimentoPilha - secoes.last.distanciaMetros) * tora;
    }

    return volume;
  }

  // V_sólido = V_estéreo × fator de empilhamento
  double calcularVolumesolido() => calcularVolumeBruto() * fatorEmpilhamento;

  String get numeroPilhaFormatado => numeroPilha.toString().padLeft(3, '0');

  Map<String, dynamic> toMap() {
    final media = calcularAlturaMedia();
    final vol = calcularVolumeBruto();
    return {
      DbPilhasMadeira.id: id,
      DbPilhasMadeira.talhaoId: talhaoId,
      DbPilhasMadeira.centroideId: centroideId,
      DbPilhasMadeira.numeroPilha: numeroPilha,
      DbPilhasMadeira.sortimento: sortimento,
      DbPilhasMadeira.dapMin: dapMin,
      DbPilhasMadeira.dapMax: dapMax,
      DbPilhasMadeira.comprimentoTora: comprimentoTora,
      DbPilhasMadeira.comprimentoToraReal: comprimentoToraReal,
      DbPilhasMadeira.comprimentoPilha: comprimentoPilha,
      DbPilhasMadeira.secoes: jsonEncode(secoes.map((s) => s.toMap()).toList()),
      DbPilhasMadeira.alturaMedia: media,
      DbPilhasMadeira.volumeBruto: vol,
      DbPilhasMadeira.fatorEmpilhamento: fatorEmpilhamento,
      DbPilhasMadeira.latitude: latitude,
      DbPilhasMadeira.longitude: longitude,
      DbPilhasMadeira.nomeFazenda: nomeFazenda,
      DbPilhasMadeira.nomeTalhao: nomeTalhao,
      DbPilhasMadeira.nomeLider: nomeLider,
      DbPilhasMadeira.dataColeta: dataColeta?.toIso8601String() ?? DateTime.now().toIso8601String(),
      DbPilhasMadeira.observacoes: observacoes,
      DbPilhasMadeira.fotos: fotos.isEmpty ? null : jsonEncode(fotos),
      DbPilhasMadeira.exportada: exportada ? 1 : 0,
      DbPilhasMadeira.isSynced: isSynced ? 1 : 0,
      DbPilhasMadeira.lastModified: lastModified?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  factory PilhaMadeira.fromMap(Map<String, dynamic> m) {
    List<SecaoPilha> secoes = [];
    final rawSecoes = m[DbPilhasMadeira.secoes];
    if (rawSecoes != null) {
      try {
        final decoded = rawSecoes is String ? jsonDecode(rawSecoes) : rawSecoes;
        if (decoded is List) {
          secoes = decoded.map((s) => SecaoPilha.fromMap(Map<String, dynamic>.from(s))).toList();
        }
      } catch (_) {}
    }

    List<String> fotos = [];
    final rawFotos = m[DbPilhasMadeira.fotos];
    if (rawFotos != null) {
      try {
        final decoded = rawFotos is String ? jsonDecode(rawFotos) : rawFotos;
        if (decoded is List) fotos = decoded.cast<String>();
      } catch (_) {}
    }

    return PilhaMadeira(
      id: m[DbPilhasMadeira.id],
      talhaoId: m[DbPilhasMadeira.talhaoId],
      centroideId: m[DbPilhasMadeira.centroideId],
      numeroPilha: (m[DbPilhasMadeira.numeroPilha] as num?)?.toInt() ?? 0,
      sortimento: m[DbPilhasMadeira.sortimento] ?? '',
      dapMin: (m[DbPilhasMadeira.dapMin] as num?)?.toDouble(),
      dapMax: (m[DbPilhasMadeira.dapMax] as num?)?.toDouble(),
      comprimentoTora: (m[DbPilhasMadeira.comprimentoTora] as num?)?.toDouble() ?? 2.4,
      comprimentoToraReal: (m[DbPilhasMadeira.comprimentoToraReal] as num?)?.toDouble(),
      comprimentoPilha: (m[DbPilhasMadeira.comprimentoPilha] as num?)?.toDouble() ?? 0.0,
      secoes: secoes,
      alturaMedia: (m[DbPilhasMadeira.alturaMedia] as num?)?.toDouble(),
      volumeBruto: (m[DbPilhasMadeira.volumeBruto] as num?)?.toDouble(),
      latitude: (m[DbPilhasMadeira.latitude] as num?)?.toDouble(),
      longitude: (m[DbPilhasMadeira.longitude] as num?)?.toDouble(),
      nomeFazenda: m[DbPilhasMadeira.nomeFazenda],
      nomeTalhao: m[DbPilhasMadeira.nomeTalhao],
      nomeLider: m[DbPilhasMadeira.nomeLider],
      dataColeta: m[DbPilhasMadeira.dataColeta] != null ? DateTime.tryParse(m[DbPilhasMadeira.dataColeta]) : null,
      observacoes: m[DbPilhasMadeira.observacoes],
      fotos: fotos,
      fatorEmpilhamento: (m[DbPilhasMadeira.fatorEmpilhamento] as num?)?.toDouble() ?? 0.65,
      exportada: m[DbPilhasMadeira.exportada] == 1,
      isSynced: m[DbPilhasMadeira.isSynced] == 1,
      lastModified: m[DbPilhasMadeira.lastModified] != null ? DateTime.tryParse(m[DbPilhasMadeira.lastModified]) : null,
    );
  }
}

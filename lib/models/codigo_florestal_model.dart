// ================================================================================
// Arquivo: lib\models\codigo_florestal_model.dart
// ================================================================================

class CodigoFlorestal {
  final String sigla;
  final String descricao;
  
  // Strings puras do CSV
  final String _fuste;        // Coluna C da sua imagem
  final String _cap;
  final String _altura;
  final String _hipsometria; 
  final String _extraDan;
  final String _dominante; 

  CodigoFlorestal({
    required this.sigla,
    required this.descricao,
    required String fuste,
    required String cap,
    required String altura,
    required String hipsometria,
    required String extraDan,
    required String dominante,
  })  : _fuste = fuste.toUpperCase().trim(),
        _cap = cap.toUpperCase().trim(),
        _altura = altura.toUpperCase().trim(),
        _hipsometria = hipsometria.toUpperCase().trim(),
        _extraDan = extraDan.toUpperCase().trim(),
        _dominante = dominante.toUpperCase().trim();

  factory CodigoFlorestal.fromCsv(List<dynamic> row) {
    // Helper para evitar erro de índice
    String getCol(int index) => (row.length > index) ? row[index].toString() : '.';

    return CodigoFlorestal(
      sigla: getCol(0),
      descricao: getCol(1),
      fuste: getCol(2), // LÊ A COLUNA C AQUI
      cap: getCol(3),
      altura: getCol(4),
      hipsometria: getCol(5),
      extraDan: getCol(6),
      dominante: getCol(7),
    );
  }

  // --- REGRAS DE NEGÓCIO ---

  // CAP
  bool get capObrigatorio => _cap == 'S';
  bool get capBloqueado => _cap == 'N';

  // Altura Total
  bool get alturaObrigatoria => _altura == 'S';
  bool get alturaBloqueada => _altura == 'N';

  // Altura do Dano (Extra Dano)
  bool get requerAlturaDano => _extraDan == 'S';

  // Fuste (AQUI ESTÁ A LÓGICA DA SUA PLANILHA)
  // 'N' = Bloqueia botão adicionar fuste (ex: Falha, Caída)
  // 'S' = Exige múltiplos fustes (ex: Bifurcada Abaixo)
  // '.' = Permite fuste, mas não exige (ex: Normal, caso tenha erro de campo)
  
  bool get permiteMultifuste => _fuste != 'N'; 
  
  // NOVA REGRA: Se na planilha estiver 'S', o app vai travar o botão salvar no 1º fuste
  bool get exigeMultiplosFustes => _fuste == 'S'; 

  // Hipsometria
  bool get entraNaCurva => _hipsometria == 'S';
  
  // Dominante
  bool get podeSerDominante => _dominante != 'N';

  @override
  String toString() => "$sigla - $descricao";
}
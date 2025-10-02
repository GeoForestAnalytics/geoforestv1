// lib/pages/amostra/coleta_dados_page.dart (VERSÃO FINAL COMPLETA)

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/pages/amostra/inventario_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoforestv1/services/permission_service.dart';
import 'package:image/image.dart' as img;
import 'package:gal/gal.dart';
import 'package:geoforestv1/data/datasources/local/database_helper.dart';
import 'package:geoforestv1/utils/constants.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
import 'package:geoforestv1/data/repositories/projeto_repository.dart';

enum FormaParcela { retangular, circular }
enum DeclividadeUnidade { graus, porcentagem }

class ColetaDadosPage extends StatefulWidget {
  final Parcela? parcelaParaEditar;
  final Talhao? talhao;

  const ColetaDadosPage({super.key, this.parcelaParaEditar, this.talhao})
      : assert(parcelaParaEditar != null || talhao != null, 'É necessário fornecer uma parcela para editar ou um talhão para criar uma nova parcela.');

  @override
  State<ColetaDadosPage> createState() => _ColetaDadosPageState();
}

class _ColetaDadosPageState extends State<ColetaDadosPage> {
  final _formKey = GlobalKey<FormState>();
  
  final _parcelaRepository = ParcelaRepository();
  final _projetoRepository = ProjetoRepository();
  
  late Parcela _parcelaAtual;

  final _nomeFazendaController = TextEditingController();
  final _idFazendaController = TextEditingController();
  final _talhaoParcelaController = TextEditingController();
  final _idParcelaController = TextEditingController();
  final _observacaoController = TextEditingController();
  final _lado1Controller = TextEditingController();
  final _lado2Controller = TextEditingController();
  final _referenciaRfController = TextEditingController();
  final _declividadeController = TextEditingController();
  
  double _areaAlvoDaParcela = 0.0; 

  DeclividadeUnidade _declividadeUnidade = DeclividadeUnidade.graus;
  String _tipoParcelaSelecionado = 'Instalação';

  Position? _posicaoAtualExibicao;
  bool _buscandoLocalizacao = false;
  String? _erroLocalizacao;
  bool _salvando = false;
  FormaParcela _formaDaParcela = FormaParcela.retangular;
  bool _isModoEdicao = false;
  final ImagePicker _picker = ImagePicker();
  final PermissionService _permissionService = PermissionService();
  bool _isReadOnly = false;

  @override
  void initState() {
    super.initState();
    _lado1Controller.addListener(_atualizarCalculosAutomaticos);
    _declividadeController.addListener(_atualizarCalculosAutomaticos);
    _lado2Controller.addListener(() => setState(() {}));
    _setupInitialData();
  }
  
  @override
  void dispose() {
    _lado1Controller.removeListener(_atualizarCalculosAutomaticos);
    _declividadeController.removeListener(_atualizarCalculosAutomaticos);
    _lado2Controller.removeListener(() => setState(() {}));
    _declividadeController.dispose();
    _nomeFazendaController.dispose();
    _idFazendaController.dispose();
    _talhaoParcelaController.dispose();
    _idParcelaController.dispose();
    _observacaoController.dispose();
    _lado1Controller.dispose();
    _lado2Controller.dispose();
    _referenciaRfController.dispose();
    super.dispose();
  }

  void _atualizarCalculosAutomaticos() {
    if (_formaDaParcela == FormaParcela.circular) {
      setState(() {}); // Apenas redesenha para atualizar a área calculada do raio
      return;
    }

    if (_formaDaParcela == FormaParcela.retangular && _areaAlvoDaParcela > 0 && !_isReadOnly) {
      final lado1 = double.tryParse(_lado1Controller.text.replaceAll(',', '.')) ?? 0;
      if (lado1 <= 0) {
        if (_lado2Controller.text.isNotEmpty) _lado2Controller.clear();
        return;
      }
      
      final declividadeValor = double.tryParse(_declividadeController.text.replaceAll(',', '.')) ?? 0;
      final areaHorizontalDesejada = _areaAlvoDaParcela;
      double fatorCorrecao = 1.0;

      if(declividadeValor > 0) {
        if (_declividadeUnidade == DeclividadeUnidade.graus) {
            final radianos = declividadeValor * (math.pi / 180.0);
            fatorCorrecao = 1 / math.cos(radianos);
        } else {
            final declividadeDecimal = declividadeValor / 100;
            fatorCorrecao = math.sqrt(1 + math.pow(declividadeDecimal, 2));
        }
      }
      
      final areaInclinadaNecessaria = areaHorizontalDesejada * fatorCorrecao;
      final lado2Calculado = areaInclinadaNecessaria / lado1;

      if (_lado2Controller.text != lado2Calculado.toStringAsFixed(2).replaceAll('.', ',')) {
          _lado2Controller.text = lado2Calculado.toStringAsFixed(2).replaceAll('.', ',');
      }
    }
    setState(() {});
  }

  Future<void> _setupInitialData() async {
    setState(() { _salvando = true; });
    try {
      if (widget.parcelaParaEditar != null) {
        _isModoEdicao = true;
        final parcelaDoBanco = await _parcelaRepository.getParcelaById(widget.parcelaParaEditar!.dbId!);
        _parcelaAtual = parcelaDoBanco ?? widget.parcelaParaEditar!;
        if(parcelaDoBanco != null) {
          _parcelaAtual.arvores = await _parcelaRepository.getArvoresDaParcela(_parcelaAtual.dbId!);
        }
        
        if (_parcelaAtual.status == StatusParcela.concluida || _parcelaAtual.status == StatusParcela.exportada) {
          _isReadOnly = true;
        }
      } else {
        _isModoEdicao = false;
        _isReadOnly = false;
        _parcelaAtual = Parcela(
          talhaoId: widget.talhao!.id,
          idParcela: '',
          areaMetrosQuadrados: 0,
          dataColeta: DateTime.now(),
          nomeFazenda: widget.talhao!.fazendaNome,
          nomeTalhao: widget.talhao!.nome,
          idFazenda: widget.talhao!.fazendaId,
          projetoId: widget.talhao!.projetoId,
          municipio: widget.talhao!.municipio, 
          estado: widget.talhao!.estado,       
        );
      }
      _preencherControllersComDadosAtuais();
    } catch (e) {
      debugPrint("Erro em _setupInitialData: $e");
      rethrow;
    } finally {
      if (mounted) {
        setState(() { _salvando = false; });
      }
    }
  }

  void _preencherControllersComDadosAtuais() {
    final p = _parcelaAtual;
    _areaAlvoDaParcela = p.areaMetrosQuadrados;

    _nomeFazendaController.text = p.nomeFazenda ?? '';
    _talhaoParcelaController.text = p.nomeTalhao ?? '';
    _idFazendaController.text = p.idFazenda ?? '';
    _idParcelaController.text = p.idParcela;
    _observacaoController.text = p.observacao ?? '';
    _referenciaRfController.text = p.referenciaRf ?? '';
    _declividadeController.text = p.declividade?.toString().replaceAll('.', ',') ?? '';
    
    if (p.tipoParcela != null) {
      if (p.tipoParcela!.toUpperCase() == 'I') {
        _tipoParcelaSelecionado = 'Instalação';
      } else if (p.tipoParcela!.toUpperCase() == 'R') {
        _tipoParcelaSelecionado = 'Remedição';
      } else {
        final opcoesValidas = ['Instalação', 'Remedição'];
        _tipoParcelaSelecionado = opcoesValidas.contains(p.tipoParcela) ? p.tipoParcela! : 'Instalação';
      }
    } else {
      _tipoParcelaSelecionado = 'Instalação';
    }
    
    _lado1Controller.clear();
    _lado2Controller.clear();
    
    _formaDaParcela = (p.formaParcela?.toLowerCase() == 'circular') 
        ? FormaParcela.circular 
        : FormaParcela.retangular;

    if (_formaDaParcela == FormaParcela.circular) {
      if ((p.lado1 == null || p.lado1! <= 0) && p.areaMetrosQuadrados > 0) {
          final raioCalculado = math.sqrt(p.areaMetrosQuadrados / math.pi);
          _lado1Controller.text = raioCalculado.toStringAsFixed(2).replaceAll('.', ',');
      } else if (p.lado1 != null) {
          _lado1Controller.text = p.lado1.toString().replaceAll('.', ',');
      }
    } else { 
      if (p.lado1 != null) _lado1Controller.text = p.lado1.toString().replaceAll('.', ',');
      if (p.lado2 != null) _lado2Controller.text = p.lado2.toString().replaceAll('.', ',');
    }
    
    if (p.latitude != null && p.longitude != null) {
      _posicaoAtualExibicao = Position(latitude: p.latitude!, longitude: p.longitude!, timestamp: DateTime.now(), accuracy: 0.0, altitude: 0.0, altitudeAccuracy: 0.0, heading: 0.0, headingAccuracy: 0.0, speed: 0.0, speedAccuracy: 0.0);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if(mounted) {
        setState(() {
          _atualizarCalculosAutomaticos();
        });
      }
    });
  }

  Parcela _construirObjetoParcelaParaSalvar() {
    double? lado1, lado2;
    double areaInclinada = 0.0;
    
    if (_formaDaParcela == FormaParcela.retangular) {
        lado1 = double.tryParse(_lado1Controller.text.replaceAll(',', '.'));
        lado2 = double.tryParse(_lado2Controller.text.replaceAll(',', '.'));
        areaInclinada = (lado1 ?? 0) * (lado2 ?? 0);
    } else {
        lado1 = double.tryParse(_lado1Controller.text.replaceAll(',', '.'));
        lado2 = null;
        areaInclinada = math.pi * math.pow(lado1 ?? 0, 2);
    }
    
    final valorDeclividadeInput = double.tryParse(_declividadeController.text.replaceAll(',', '.')) ?? 0;
    double declividadeParaSalvarEmGraus = 0.0;
    double areaFinalParaSalvar = areaInclinada;

    if (valorDeclividadeInput > 0) {
      if (_declividadeUnidade == DeclividadeUnidade.graus) {
        declividadeParaSalvarEmGraus = valorDeclividadeInput;
        final radianos = declividadeParaSalvarEmGraus * (math.pi / 180);
        areaFinalParaSalvar = areaInclinada * math.cos(radianos);
      } else { 
        declividadeParaSalvarEmGraus = math.atan(valorDeclividadeInput / 100) * (180 / math.pi);
        areaFinalParaSalvar = areaInclinada / math.sqrt(1 + math.pow(valorDeclividadeInput / 100, 2));
      }
    }

    return _parcelaAtual.copyWith(
      idParcela: _idParcelaController.text.trim(),
      nomeFazenda: _nomeFazendaController.text.trim(),
      idFazenda: _idFazendaController.text.trim().isNotEmpty ? _idFazendaController.text.trim() : null,
      nomeTalhao: _talhaoParcelaController.text.trim(),
      observacao: _observacaoController.text.trim(),
      areaMetrosQuadrados: areaFinalParaSalvar > 0 ? areaFinalParaSalvar : _areaAlvoDaParcela,
      referenciaRf: _referenciaRfController.text.trim(),
      tipoParcela: _tipoParcelaSelecionado,
      formaParcela: _formaDaParcela.name,
      lado1: lado1,
      lado2: lado2,
      declividade: declividadeParaSalvarEmGraus > 0 ? declividadeParaSalvarEmGraus : null,
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 1280);
    if (pickedFile == null || !mounted) return;

    final bool hasPermission = await _permissionService.requestStoragePermission();
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permissão de armazenamento negada.'), backgroundColor: Colors.red));
      return;
    }

    try {
      proj4.Projection.add('EPSG:4326', '+proj=longlat +datum=WGS84 +no_defs');
      proj4Definitions.forEach((epsg, def) {
        proj4.Projection.add('EPSG:$epsg', def);
      });

      if (_parcelaAtual.dbId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, salve os dados da parcela antes de adicionar fotos.'), backgroundColor: Colors.orange));
        return;
      }
      
      final projeto = await _projetoRepository.getProjetoPelaParcela(_parcelaAtual);
      final projetoNome = projeto?.nome.replaceAll(RegExp(r'[^\w\s-]'), '') ?? 'PROJETO';
      final fazendaNome = _parcelaAtual.nomeFazenda?.replaceAll(RegExp(r'[^\w\s-]'), '') ?? 'FAZENDA';
      final talhaoNome = _parcelaAtual.nomeTalhao?.replaceAll(RegExp(r'[^\w\s-]'), '') ?? 'TALHAO';
      final idParcela = _idParcelaController.text.trim().replaceAll(RegExp(r'[^\w\s-]'), '');
      
      final prefs = await SharedPreferences.getInstance();
      String utmString = "UTM N/A";
      
      if (_parcelaAtual.latitude != null && _parcelaAtual.longitude != null) {
        final nomeZona = prefs.getString('zona_utm_selecionada') ?? 'SIRGAS 2000 / UTM Zona 22S';
        final codigoEpsg = zonasUtmSirgas2000[nomeZona] ?? 31982;
        
        final projWGS84 = proj4.Projection.get('EPSG:4326');
        final projUTM = proj4.Projection.get('EPSG:$codigoEpsg');
        
        if (projWGS84 == null || projUTM == null) {
            throw Exception('Falha ao obter sistema de projeção (Proj4). Tente novamente.');
        }

        var pUtm = projWGS84.transform(projUTM, proj4.Point(x: _parcelaAtual.longitude!, y: _parcelaAtual.latitude!));
        utmString = "E: ${pUtm.x.toInt()} N: ${pUtm.y.toInt()} | ${nomeZona.split('/')[1].trim()}";
      }
      
      final String nomeLider = prefs.getString('nome_lider') ?? 'Equipe N/A';
      
      final timestamp = DateTime.now();
      final dataHoraFormatada = DateFormat('dd/MM/yyyy HH:mm:ss').format(timestamp);
      final nomeArquivoTimestamp = DateFormat('yyyyMMdd_HHmmss').format(timestamp);
      final String nomeArquivoFinal = "${projetoNome}_${fazendaNome}_${talhaoNome}_${idParcela}_$nomeArquivoTimestamp.jpg";
      
      final bytesImagemOriginal = await File(pickedFile.path).readAsBytes();
      img.Image? imagemEditavel = img.decodeImage(bytesImagemOriginal);
      if (imagemEditavel == null) throw Exception("Não foi possível decodificar a imagem.");

      final List<String> linhas = [
        "Projeto: $projetoNome",
        "Fazenda: $fazendaNome | Talhão: $talhaoNome | Parcela: $idParcela",
        utmString,
        "Líder: $nomeLider | $dataHoraFormatada"
      ];

      final int alturaLinha = 28;
      final int alturaTotalTexto = linhas.length * alturaLinha;
      final int alturaFaixa = alturaTotalTexto + 15;

      img.fillRect(imagemEditavel, x1: 0, y1: imagemEditavel.height - alturaFaixa, x2: imagemEditavel.width, y2: imagemEditavel.height, color: img.ColorRgba8(0, 0, 0, 128));

      for (int i = 0; i < linhas.length; i++) {
        int yPos = (imagemEditavel.height - alturaFaixa) + (i * alturaLinha) + 10;
        img.drawString(imagemEditavel, linhas[i], font: img.arial24, x: 10, y: yPos, color: img.ColorRgb8(255, 255, 255));
      }

      final Uint8List bytesFinais = Uint8List.fromList(img.encodeJpg(imagemEditavel, quality: 85));

      await Gal.putImageBytes(bytesFinais, name: nomeArquivoFinal);

      setState(() {
          _parcelaAtual.photoPaths.add(pickedFile.path);
      });
      
      await _salvarAlteracoes(showSnackbar: false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto salva na galeria e vinculada à parcela!'), backgroundColor: Colors.green)
        );
      }

    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar foto: ${e.toString()}'), backgroundColor: Colors.red));
    }
  }

  Future<void> _reabrirParaEdicao() async {
    setState(() => _salvando = true);
    try {
      await _parcelaRepository.updateParcelaStatus(_parcelaAtual.dbId!, StatusParcela.emAndamento);
      
      if(mounted) {
        setState(() {
          _parcelaAtual = _parcelaAtual.copyWith(status: StatusParcela.emAndamento);
          _isReadOnly = false;
          _salvando = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parcela reaberta. Agora você pode editar os dados.'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao reabrir parcela: $e'), backgroundColor: Colors.red));
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _salvarEIniciarColeta() async {
    if (!_formKey.currentState!.validate()) return;
    
    final parcelaParaSalvar = _construirObjetoParcelaParaSalvar();

    if (parcelaParaSalvar.areaMetrosQuadrados <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A área da parcela deve ser maior que zero'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _salvando = true);

    if (!_isModoEdicao) {
        final parcelaExistente = await _parcelaRepository.getParcelaPorIdParcela(widget.talhao!.id!, _idParcelaController.text.trim());
        if(parcelaExistente != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este ID de Parcela já existe neste talhão.'), backgroundColor: Colors.red));
            setState(() => _salvando = false);
            return;
        }
    }

    try {
      final parcelaAtualizada = parcelaParaSalvar.copyWith(status: StatusParcela.emAndamento);
      final parcelaSalva = await _parcelaRepository.saveFullColeta(parcelaAtualizada, _parcelaAtual.arvores);

      if (mounted) {
        await Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => InventarioPage(parcela: parcelaSalva)));
        
        Navigator.pop(context, true); 
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _finalizarParcelaVazia() async {
    if (!_formKey.currentState!.validate()) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Parcela?'),
        content: const Text('Você vai marcar a parcela como concluída sem árvores. Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Finalizar')),
        ],
      ),
    );

    if (confirmar != true) return;
    setState(() => _salvando = true);

    try {
      final parcelaFinalizada = _construirObjetoParcelaParaSalvar().copyWith(status: StatusParcela.concluida);
      await _parcelaRepository.saveFullColeta(parcelaFinalizada, []);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parcela finalizada com sucesso!'), backgroundColor: Colors.green));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao finalizar: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }
  
  Future<void> _salvarAlteracoes({bool showSnackbar = true}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);
    try {
      final parcelaEditada = _construirObjetoParcelaParaSalvar();
      final parcelaSalva = await _parcelaRepository.saveFullColeta(parcelaEditada, _parcelaAtual.arvores);
      
      if (mounted) {
        setState(() {
          _parcelaAtual = parcelaSalva;
          _areaAlvoDaParcela = parcelaSalva.areaMetrosQuadrados; // Atualiza a área alvo
        });
        if(showSnackbar) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alterações salvas com sucesso!'), backgroundColor: Colors.green));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _navegarParaInventario() async {
    if (_salvando) return;
    
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    final parcelaParaNavegar = _construirObjetoParcelaParaSalvar();
    
    if (parcelaParaNavegar.areaMetrosQuadrados <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A área da parcela deve ser maior que zero.'), backgroundColor: Colors.orange));
      return;
    }
    
    setState(() => _salvando = true);
    final parcelaSalva = await _parcelaRepository.saveFullColeta(parcelaParaNavegar, _parcelaAtual.arvores);
    setState(() {
      _parcelaAtual = parcelaSalva;
      _areaAlvoDaParcela = parcelaSalva.areaMetrosQuadrados; // Atualiza a área alvo
      _salvando = false;
    });
    
    if (mounted) {
      final foiAtualizado = await Navigator.push(
        context, 
        MaterialPageRoute(builder: (context) => InventarioPage(parcela: _parcelaAtual))
      );
      
      if (foiAtualizado == true && mounted) {
        _recarregarTela();
      }
    }
  }
  
  Future<void> _recarregarTela() async {
    if (_parcelaAtual.dbId == null) return;
    final parcelaRecarregada = await _parcelaRepository.getParcelaById(_parcelaAtual.dbId!);
    if(parcelaRecarregada != null && mounted) {
      final arvoresRecarregadas = await _parcelaRepository.getArvoresDaParcela(parcelaRecarregada.dbId!);
      parcelaRecarregada.arvores = arvoresRecarregadas;
      setState(() {
        _parcelaAtual = parcelaRecarregada;
        _isReadOnly = (_parcelaAtual.status == StatusParcela.concluida || _parcelaAtual.status == StatusParcela.exportada);
        _preencherControllersComDadosAtuais();
      });
    }
  }

  Future<void> _obterLocalizacaoAtual() async {
    if (_isReadOnly) return;
    setState(() { _buscandoLocalizacao = true; _erroLocalizacao = null; });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'Serviço de GPS desabilitado.';
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw 'Permissão negada.';
      }
      if (permission == LocationPermission.deniedForever) throw 'Permissão negada permanentemente.';
      
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 20));
      
      setState(() {
        _posicaoAtualExibicao = position;
        _parcelaAtual = _parcelaAtual.copyWith(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      });

    } catch (e) {
      setState(() => _erroLocalizacao = e.toString());
    } finally {
      if (mounted) setState(() => _buscandoLocalizacao = false);
    }
  }
  
   @override
  Widget build(BuildContext context) {
    double areaInclinadaCalculada = 0.0;
    if (_formaDaParcela == FormaParcela.retangular) {
      final lado1 = double.tryParse(_lado1Controller.text.replaceAll(',', '.')) ?? 0;
      final lado2 = double.tryParse(_lado2Controller.text.replaceAll(',', '.')) ?? 0;
      areaInclinadaCalculada = lado1 * lado2;
    } else {
      final raio = double.tryParse(_lado1Controller.text.replaceAll(',', '.')) ?? 0;
      areaInclinadaCalculada = math.pi * math.pow(raio, 2);
    }

    final valorDeclividadeInput = double.tryParse(_declividadeController.text.replaceAll(',', '.')) ?? 0;
    double areaHorizontalFinal = areaInclinadaCalculada;

    if (valorDeclividadeInput > 0) {
      if (_declividadeUnidade == DeclividadeUnidade.graus) {
        final radianos = valorDeclividadeInput * (math.pi / 180.0);
        areaHorizontalFinal = areaInclinadaCalculada * math.cos(radianos);
      } else {
        areaHorizontalFinal = areaInclinadaCalculada / math.sqrt(1 + math.pow(valorDeclividadeInput / 100, 2));
      }
    }

    // <<< CORREÇÃO AQUI: Passamos a variável calculada para o widget de construção >>>
    return Scaffold(
      appBar: AppBar(
        title: Text(_isModoEdicao ? 'Dados da Parcela' : 'Nova Parcela'),
        backgroundColor: const Color.fromARGB(255, 13, 58, 89),
        foregroundColor: Colors.white,
      ),
      body: _salvando && !_buscandoLocalizacao
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isReadOnly)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline, size: 18, color: Colors.amber.shade800),
                          const SizedBox(width: 8),
                          Expanded(child: Text("Parcela concluída (modo de visualização).", style: TextStyle(color: Colors.amber.shade900))),
                        ],
                      ),
                    ),
                  
                  Row(
                    children: [
                      Expanded(child: TextFormField(controller: _referenciaRfController, enabled: !_isReadOnly, decoration: const InputDecoration(labelText: 'RF', border: OutlineInputBorder()))),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _tipoParcelaSelecionado,
                          items: const [
                            DropdownMenuItem(value: 'Instalação', child: Text('Instalação')),
                            DropdownMenuItem(value: 'Remedição', child: Text('Remedição')),
                          ],
                          onChanged: _isReadOnly ? null : (value) {
                            if (value != null) {
                              setState(() => _tipoParcelaSelecionado = value);
                            }
                          },
                          decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(controller: _nomeFazendaController, enabled: false, decoration: const InputDecoration(labelText: 'Nome da Fazenda', border: OutlineInputBorder(), prefixIcon: Icon(Icons.business))),
                  const SizedBox(height: 16),
                  TextFormField(controller: _idFazendaController, enabled: false, decoration: const InputDecoration(labelText: 'Código da Fazenda', border: OutlineInputBorder(), prefixIcon: Icon(Icons.pin_outlined))),
                  const SizedBox(height: 16),
                  TextFormField(controller: _talhaoParcelaController, enabled: false, decoration: const InputDecoration(labelText: 'Talhão', border: OutlineInputBorder(), prefixIcon: Icon(Icons.grid_on))),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _idParcelaController,
                    enabled: !_isModoEdicao,
                    decoration: InputDecoration(
                      labelText: 'ID da parcela (Ex: P01, A05)',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.tag),
                      filled: _isModoEdicao,
                      fillColor: _isModoEdicao ? Colors.black12 : null,
                    ), 
                    validator: (v) => v == null || v.trim().isEmpty ? 'Campo obrigatório' : null
                  ),

                  const SizedBox(height: 16),
                  _buildCalculadoraArea(areaInclinadaCalculada, areaHorizontalFinal),
                  const SizedBox(height: 16),
                  _buildColetorCoordenadas(),
                  const SizedBox(height: 24),
                  _buildPhotoSection(),
                  const SizedBox(height: 16),
                  TextFormField(controller: _observacaoController, enabled: !_isReadOnly, decoration: const InputDecoration(labelText: 'Observações da Parcela', border: OutlineInputBorder(), prefixIcon: Icon(Icons.comment), helperText: 'Opcional'), maxLines: 3),
                  const SizedBox(height: 24),
                  _buildActionButtons(),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildActionButtons() {
    if (_isReadOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 50, child: ElevatedButton.icon(onPressed: _salvando ? null : _reabrirParaEdicao, icon: _salvando ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white)) : const Icon(Icons.edit_outlined), label: const Text('Reabrir para Edição', style: TextStyle(fontSize: 18)), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white))),
          const SizedBox(height: 12),
          SizedBox(height: 50, child: OutlinedButton.icon(onPressed: _navegarParaInventario, icon: const Icon(Icons.park_outlined), label: const Text('Ver Inventário', style: TextStyle(fontSize: 18)))),
        ],
      );
    }
    
    if (_isModoEdicao) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 50, child: ElevatedButton.icon(onPressed: _salvando ? null : () => _salvarAlteracoes(), icon: _salvando ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white)) : const Icon(Icons.save_outlined), label: const Text('Salvar Dados da Parcela', style: TextStyle(fontSize: 18)), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white))),
          const SizedBox(height: 12),
          SizedBox(height: 50, child: ElevatedButton.icon(onPressed: _salvando ? null : _navegarParaInventario, icon: const Icon(Icons.park_outlined), label: const Text('Ver/Editar Inventário', style: TextStyle(fontSize: 18)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1D4433), foregroundColor: Colors.white))),
        ],
      );
    } else { 
  return Wrap( // ✅ Substitua Row por Wrap
    spacing: 16.0, // Espaço horizontal entre os botões
    runSpacing: 12.0, // Espaço vertical se quebrar a linha
    alignment: WrapAlignment.center, // Centraliza os botões
    children: [
      SizedBox(
        width: 150, // Dê uma largura mínima razoável
        height: 50, 
        child: OutlinedButton(
          onPressed: _salvando ? null : _finalizarParcelaVazia, 
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF1D4433)), foregroundColor: const Color(0xFF1D4433)), 
          child: const Text('Finalizar Vazia')
        )
      ),
      SizedBox(
        width: 150, // Dê uma largura mínima razoável
        height: 50, 
        child: ElevatedButton(
          onPressed: _salvando ? null : _salvarEIniciarColeta, 
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1D4433), foregroundColor: Colors.white), 
          child: _salvando ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white)) : const Text('Iniciar Coleta', style: TextStyle(fontSize: 18))
        )
      ),
    ],
  );
}
  }


   Widget _buildCalculadoraArea(double areaInclinada, double areaHorizontal) {
    final double areaParaExibir = (areaInclinada <= 0 && _areaAlvoDaParcela > 0)
        ? _areaAlvoDaParcela
        : areaInclinada;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Dimensões e Área da Parcela', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<FormaParcela>(
          segments: const [
            ButtonSegment(value: FormaParcela.retangular, label: Text('Retangular'), icon: Icon(Icons.crop_square)),
            ButtonSegment(value: FormaParcela.circular, label: Text('Circular'), icon: Icon(Icons.circle_outlined)),
          ],
          selected: {_formaDaParcela},
          onSelectionChanged: _isReadOnly ? null : (newSelection) {
            setState(() { 
              _formaDaParcela = newSelection.first; 
              _lado1Controller.clear();
              _lado2Controller.clear();
              if (_formaDaParcela == FormaParcela.circular && _areaAlvoDaParcela > 0) {
                final raioCalculado = math.sqrt(_areaAlvoDaParcela / math.pi);
                _lado1Controller.text = raioCalculado.toStringAsFixed(2).replaceAll('.', ',');
              }
            });
          },
        ),
        const SizedBox(height: 16),
        if (_formaDaParcela == FormaParcela.retangular)
          Row(children: [
            Expanded(child: TextFormField(controller: _lado1Controller, enabled: !_isReadOnly, decoration: const InputDecoration(labelText: 'Lado 1 (m)', border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null)),
            const SizedBox(width: 8), const Text('x', style: TextStyle(fontSize: 20)), const SizedBox(width: 8),
            Expanded(child: TextFormField(controller: _lado2Controller, enabled: !_isReadOnly, decoration: const InputDecoration(labelText: 'Lado 2 (m)', border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null)),
          ])
        else
          TextFormField(controller: _lado1Controller, enabled: !_isReadOnly, decoration: const InputDecoration(labelText: 'Raio (m)', border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null),
        const SizedBox(height: 16),
        
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _declividadeController,
                enabled: !_isReadOnly,
                decoration: InputDecoration(
                  labelText: 'Declividade (${_declividadeUnidade == DeclividadeUnidade.graus ? "°" : "%"})', 
                  border: const OutlineInputBorder(), 
                  helperText: 'Opcional, para correção'
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: SegmentedButton<DeclividadeUnidade>(
                segments: const [
                  ButtonSegment(value: DeclividadeUnidade.graus, label: Text('°')),
                  ButtonSegment(value: DeclividadeUnidade.porcentagem, label: Text('%')),
                ],
                selected: {_declividadeUnidade},
                onSelectionChanged: _isReadOnly ? null : (newSelection) {
                  setState(() {
                    _declividadeUnidade = newSelection.first;
                    _atualizarCalculosAutomaticos();
                  });
                },
              ),
            )
          ],
        ),

        const SizedBox(height: 16),

        Container(
          width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: areaParaExibir > 0 ? Colors.green[50] : Colors.grey[200], borderRadius: BorderRadius.circular(4), border: Border.all(color: areaParaExibir > 0 ? Colors.green : Colors.grey)),
          child: Column(children: [ 
            const Text('Área Inclinada (Medida):'), 
            Text('${areaParaExibir.toStringAsFixed(2)} m²', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: areaParaExibir > 0 ? Colors.green[800] : Colors.black)),
            if (areaHorizontal != areaInclinada && areaInclinada > 0) ...[
              const SizedBox(height: 8),
              const Text('Área Horizontal (Corrigida):'),
              Text('${areaHorizontal.toStringAsFixed(2)} m²', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue[800])),
            ]
          ]),
        ),
      ],
    );
  }


  Widget _buildColetorCoordenadas() {
    final latExibicao = _posicaoAtualExibicao?.latitude ?? _parcelaAtual.latitude;
    final lonExibicao = _posicaoAtualExibicao?.longitude ?? _parcelaAtual.longitude;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Coordenadas da Parcela', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
          child: Row(children: [
            Expanded(
              child: _buscandoLocalizacao
                ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(width: 16), Text('Buscando...')])
                : _erroLocalizacao != null
                  ? Text('Erro: $_erroLocalizacao', style: const TextStyle(color: Colors.red))
                  : (latExibicao == null)
                    ? const Text('Nenhuma localização obtida.')
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Lat: ${latExibicao.toStringAsFixed(6)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Lon: ${lonExibicao!.toStringAsFixed(6)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (_posicaoAtualExibicao != null && _posicaoAtualExibicao!.accuracy > 0)
                          Text('Precisão: ±${_posicaoAtualExibicao!.accuracy.toStringAsFixed(1)}m', style: TextStyle(color: Colors.grey[700])),
                      ]),
            ),
            IconButton(icon: const Icon(Icons.my_location, color: Color(0xFF1D4433)), onPressed: _buscandoLocalizacao || _isReadOnly ? null : _obterLocalizacaoAtual, tooltip: 'Obter localização'),
          ]),
        ),
      ],
    );
  }
  
  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fotos da Parcela', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: [
              _parcelaAtual.photoPaths.isEmpty
                  ? const Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 24.0), child: Text('Nenhuma foto adicionada.')))
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                      itemCount: _parcelaAtual.photoPaths.length,
                      itemBuilder: (context, index) {
                        final photoPath = _parcelaAtual.photoPaths[index];
                        final file = File(photoPath);

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: file.existsSync()
                                ? Image.file(file, fit: BoxFit.cover)
                                : Container(
                                    color: Colors.grey.shade300,
                                    child: const Icon(Icons.broken_image_outlined, color: Colors.grey, size: 40),
                                  ),
                            ),
                            if (!_isReadOnly)
                              Positioned(
                                top: -8, right: -8,
                                child: IconButton(
                                  icon: const CircleAvatar(backgroundColor: Colors.white, radius: 12, child: Icon(Icons.close, color: Colors.red, size: 16)),
                                  onPressed: () => setState(() => _parcelaAtual.photoPaths.removeAt(index)),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
              if (!_isReadOnly) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(child: OutlinedButton.icon(onPressed: () => _pickImage(ImageSource.camera), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Câmera'))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton.icon(onPressed: () => _pickImage(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Galeria'))),
                  ],
                ),
              ]
            ],
          ),
        ),
      ],
    );
  }
}
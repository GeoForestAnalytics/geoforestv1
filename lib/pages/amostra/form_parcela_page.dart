// lib/pages/amostra/form_parcela_page.dart (VERSÃO ATUALIZADA PARA EXPORTAÇÃO)

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/pages/amostra/inventario_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geoforestv1/data/repositories/parcela_repository.dart';

enum FormaParcela { retangular, circular }

class FormParcelaPage extends StatefulWidget {
  final Talhao talhao;

  const FormParcelaPage({super.key, required this.talhao});

  @override
  State<FormParcelaPage> createState() => _FormParcelaPageState();
}

class _FormParcelaPageState extends State<FormParcelaPage> {
  final _formKey = GlobalKey<FormState>();
  final _parcelaRepository = ParcelaRepository();

  // --- CONTROLADORES ATUALIZADOS ---
  final _idParcelaController = TextEditingController();
  final _observacaoController = TextEditingController();
  final _lado1Controller = TextEditingController();
  final _lado2Controller = TextEditingController();
  final _referenciaRfController = TextEditingController();
  final _tipoParcelaController = TextEditingController(text: 'Instalação');

  bool _isSaving = false;
  bool _isGettingLocation = false;
  FormaParcela _formaDaParcela = FormaParcela.retangular;
  double _areaCalculada = 0.0;
  
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _lado1Controller.addListener(_calcularArea);
    _lado2Controller.addListener(_calcularArea);
  }

  @override
  void dispose() {
    _idParcelaController.dispose();
    _observacaoController.dispose();
    _lado1Controller.dispose();
    _lado2Controller.dispose();
    _referenciaRfController.dispose();
    _tipoParcelaController.dispose();
    super.dispose();
  }

  void _calcularArea() {
    double area = 0.0;
    if (_formaDaParcela == FormaParcela.retangular) {
      final lado1 = double.tryParse(_lado1Controller.text.replaceAll(',', '.')) ?? 0;
      final lado2 = double.tryParse(_lado2Controller.text.replaceAll(',', '.')) ?? 0;
      area = lado1 * lado2;
    } else {
      final raio = double.tryParse(_lado1Controller.text.replaceAll(',', '.')) ?? 0;
      area = math.pi * math.pow(raio, 2);
    }
    setState(() => _areaCalculada = area);
  }

  Future<void> _obterCoordenadasGPS() async {
    setState(() => _isGettingLocation = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Serviços de localização estão desativados.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Permissão de localização negada.';
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw 'Permissão de localização negada permanentemente.';
      }

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao obter GPS: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if(mounted) setState(() => _isGettingLocation = false);
    }
  }

  // <<< FUNÇÃO DE SALVAR ATUALIZADA >>>
  Future<void> _salvarEIniciarColeta() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_areaCalculada <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A área da parcela deve ser maior que zero.'), backgroundColor: Colors.orange));
      return;
    }
    
    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('É obrigatório obter as coordenadas GPS da parcela.'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isSaving = true);

    final parcelaExistente = await _parcelaRepository.getParcelaPorIdParcela(widget.talhao.id!, _idParcelaController.text.trim());
    if (parcelaExistente != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este ID de Parcela já existe neste talhão.'), backgroundColor: Colors.red));
        setState(() => _isSaving = false);
        return;
    }

    final novaParcela = Parcela(
      talhaoId: widget.talhao.id,
      idParcela: _idParcelaController.text.trim(),
      areaMetrosQuadrados: _areaCalculada,
      observacao: _observacaoController.text.trim(),
      dataColeta: DateTime.now(),
      status: StatusParcela.emAndamento,
      formaParcela: _formaDaParcela.name,
      lado1: double.tryParse(_lado1Controller.text.replaceAll(',', '.')),
      lado2: _formaDaParcela == FormaParcela.retangular ? double.tryParse(_lado2Controller.text.replaceAll(',', '.')) : null,
      referenciaRf: _referenciaRfController.text.trim(),
      tipoParcela: _tipoParcelaController.text.trim(),
      nomeFazenda: widget.talhao.fazendaNome, 
      nomeTalhao: widget.talhao.nome,
      latitude: _latitude,
      longitude: _longitude,
      projetoId: widget.talhao.projetoId,
    );

    try {
      final parcelaSalva = await _parcelaRepository.saveFullColeta(novaParcela, []);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => InventarioPage(parcela: parcelaSalva)),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Nova Parcela: ${widget.talhao.nome}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _idParcelaController,
                decoration: const InputDecoration(labelText: 'ID da Parcela (Ex: P01, A05)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.tag)),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _referenciaRfController,
                decoration: const InputDecoration(labelText: 'Referência (RF)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.flag_outlined)),
              ),
              const SizedBox(height: 16),
              _buildCalculadoraArea(),
              const SizedBox(height: 16),
              _buildLocalizacaoGps(),
              const SizedBox(height: 16),
              TextFormField(
                controller: _observacaoController,
                decoration: const InputDecoration(labelText: 'Observações (Opcional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.comment)),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _salvarEIniciarColeta,
                icon: _isSaving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) : const Icon(Icons.arrow_forward),
                label: const Text('Salvar e Iniciar Inventário'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocalizacaoGps() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Localização GPS da Parcela', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            if (_latitude != null && _longitude != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Latitude: ${_latitude!.toStringAsFixed(6)}"),
                    Text("Longitude: ${_longitude!.toStringAsFixed(6)}"),
                  ],
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(bottom: 16.0),
                child: Text("Nenhuma coordenada obtida ainda.", style: TextStyle(color: Colors.grey)),
              ),
            OutlinedButton.icon(
              onPressed: _isGettingLocation ? null : _obterCoordenadasGPS,
              icon: _isGettingLocation
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.gps_fixed),
              label: Text(_isGettingLocation ? 'Obtendo...' : 'Obter Coordenadas GPS'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // <<< WIDGET ATUALIZADO PARA LADO1/LADO2 >>>
  Widget _buildCalculadoraArea() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Formato e Área da Parcela', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            SegmentedButton<FormaParcela>(
              segments: const [
                ButtonSegment(value: FormaParcela.retangular, label: Text('Retangular'), icon: Icon(Icons.crop_square)),
                ButtonSegment(value: FormaParcela.circular, label: Text('Circular'), icon: Icon(Icons.circle_outlined)),
              ],
              selected: {_formaDaParcela},
              onSelectionChanged: (newSelection) {
                setState(() => _formaDaParcela = newSelection.first);
                _calcularArea();
              },
            ),
            const SizedBox(height: 16),
            if (_formaDaParcela == FormaParcela.retangular)
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _lado1Controller,
                      decoration: const InputDecoration(labelText: 'Lado 1 (m)', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _lado2Controller,
                      decoration: const InputDecoration(labelText: 'Lado 2 (m)', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                    ),
                  ),
                ],
              )
            else
              TextFormField(
                controller: _lado1Controller,
                decoration: const InputDecoration(labelText: 'Raio (m)', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
              ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  'Área Calculada: ${_areaCalculada.toStringAsFixed(2)} m²',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
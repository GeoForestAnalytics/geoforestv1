// lib/pages/amostra/form_parcela_page.dart (VERSÃO REFATORADA COM REPOSITÓRIOS)

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/models/talhao_model.dart';
import 'package:geoforestv1/pages/amostra/inventario_page.dart';
import 'package:geolocator/geolocator.dart';

// --- NOVO IMPORT DO REPOSITÓRIO ---
import 'package:geoforestv1/data/repositories/parcela_repository.dart';
// ------------------------------------

// O import do database_helper foi removido.
// import 'package:geoforestv1/data/datasources/local/database_helper.dart';

enum FormaParcela { retangular, circular }

class FormParcelaPage extends StatefulWidget {
  final Talhao talhao;

  const FormParcelaPage({super.key, required this.talhao});

  @override
  State<FormParcelaPage> createState() => _FormParcelaPageState();
}

class _FormParcelaPageState extends State<FormParcelaPage> {
  final _formKey = GlobalKey<FormState>();
  
  // --- INSTÂNCIA DO NOVO REPOSITÓRIO ---
  final _parcelaRepository = ParcelaRepository();
  // ---------------------------------------

  final _idParcelaController = TextEditingController();
  final _observacaoController = TextEditingController();
  final _larguraController = TextEditingController();
  final _comprimentoController = TextEditingController();
  final _raioController = TextEditingController();

  bool _isSaving = false;
  bool _isGettingLocation = false;
  FormaParcela _formaDaParcela = FormaParcela.retangular;
  double _areaCalculada = 0.0;
  
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _larguraController.addListener(_calcularArea);
    _comprimentoController.addListener(_calcularArea);
    _raioController.addListener(_calcularArea);
  }

  @override
  void dispose() {
    _idParcelaController.dispose();
    _observacaoController.dispose();
    _larguraController.dispose();
    _comprimentoController.dispose();
    _raioController.dispose();
    super.dispose();
  }

  void _calcularArea() {
    double area = 0.0;
    if (_formaDaParcela == FormaParcela.retangular) {
      final largura = double.tryParse(_larguraController.text.replaceAll(',', '.')) ?? 0;
      final comprimento = double.tryParse(_comprimentoController.text.replaceAll(',', '.')) ?? 0;
      area = largura * comprimento;
    } else {
      final raio = double.tryParse(_raioController.text.replaceAll(',', '.')) ?? 0;
      area = math.pi * raio * raio;
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

  // --- MÉTODO ATUALIZADO ---
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

    // Usa o ParcelaRepository para verificar a existência
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
      largura: _formaDaParcela == FormaParcela.retangular ? double.tryParse(_larguraController.text.replaceAll(',', '.')) : null,
      comprimento: _formaDaParcela == FormaParcela.retangular ? double.tryParse(_comprimentoController.text.replaceAll(',', '.')) : null,
      raio: _formaDaParcela == FormaParcela.circular ? double.tryParse(_raioController.text.replaceAll(',', '.')) : null,
      nomeFazenda: widget.talhao.fazendaNome, 
      nomeTalhao: widget.talhao.nome,
      latitude: _latitude,
      longitude: _longitude,
      projetoId: widget.talhao.projetoId, // Passa o ID do projeto para a nova parcela
    );

    try {
      // Usa o ParcelaRepository para salvar
      final parcelaSalva = await _parcelaRepository.saveParcela(novaParcela);
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

  // O método build e seus widgets auxiliares não precisam de nenhuma alteração.
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
                      controller: _larguraController,
                      decoration: const InputDecoration(labelText: 'Largura (m)', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _comprimentoController,
                      decoration: const InputDecoration(labelText: 'Comprimento (m)', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                    ),
                  ),
                ],
              )
            else
              TextFormField(
                controller: _raioController,
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
// lib/pages/menu/vehicle_checklist_page.dart

import 'package:flutter/material.dart';
import 'package:geoforestv1/data/repositories/vehicle_checklist_repository.dart';
import 'package:geoforestv1/models/vehicle_checklist_model.dart';
import 'package:geoforestv1/services/pdf_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
// REMOVIDO: import 'package:image_picker/image_picker.dart';
// REMOVIDO: import 'dart:io';

class VehicleChecklistPage extends StatefulWidget {
  final VehicleChecklist? checklistParaEditar;

  const VehicleChecklistPage({super.key, this.checklistParaEditar});

  @override
  State<VehicleChecklistPage> createState() => _VehicleChecklistPageState();
}

class _VehicleChecklistPageState extends State<VehicleChecklistPage> {
  final _formKey = GlobalKey<FormState>();
  
  final _placaController = TextEditingController();
  final _kmController = TextEditingController();
  final _modeloController = TextEditingController();
  final _prefixoController = TextEditingController(); 
  final _categoriaCnhController = TextEditingController(); 
  final _vencimentoCnhController = TextEditingController(); 
  final _obsController = TextEditingController();
  
  final Map<String, String> _respostas = {};

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    
    if (widget.checklistParaEditar != null) {
      final c = widget.checklistParaEditar!;
      _placaController.text = c.placa ?? '';
      _kmController.text = c.kmAtual?.toString() ?? '';
      _modeloController.text = c.modeloVeiculo ?? '';
      _prefixoController.text = c.prefixo ?? '';
      _categoriaCnhController.text = c.categoriaCnh ?? '';
      _vencimentoCnhController.text = c.vencimentoCnh != null ? DateFormat('dd/MM/yyyy').format(c.vencimentoCnh!) : '';
      _obsController.text = c.observacoes ?? '';
      
      // Carrega as respostas salvas
      if (c.itens.isNotEmpty) {
        _respostas.addAll(c.itens);
      } else {
        _inicializarRespostasPadrao();
      }
    } else {
      _inicializarRespostasPadrao();
    }
  }

  void _inicializarRespostasPadrao() {
    for (int i = 1; i <= checklistItensDescricao.length; i++) {
      _respostas[i.toString()] = 'C';
    }
  }

  @override
  void dispose() {
    _placaController.dispose();
    _kmController.dispose();
    _modeloController.dispose();
    _prefixoController.dispose();
    _categoriaCnhController.dispose();
    _vencimentoCnhController.dispose();
    _obsController.dispose();
    super.dispose();
  }

  Future<void> _selecionarVencimento(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _vencimentoCnhController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  Future<void> _salvarEGerarPdf() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha os campos obrigatórios.')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final nomeLider = widget.checklistParaEditar?.nomeMotorista ?? (prefs.getString('nome_lider') ?? 'Motorista');

      final checklist = VehicleChecklist(
        id: widget.checklistParaEditar?.id,
        dataRegistro: widget.checklistParaEditar?.dataRegistro ?? DateTime.now(),
        nomeMotorista: nomeLider,
        isMotorista: true,
        placa: _placaController.text.toUpperCase(),
        kmAtual: double.tryParse(_kmController.text.replaceAll(',', '.')),
        modeloVeiculo: _modeloController.text,
        prefixo: _prefixoController.text, 
        categoriaCnh: _categoriaCnhController.text, 
        vencimentoCnh: _vencimentoCnhController.text.isNotEmpty 
            ? DateFormat('dd/MM/yyyy').parse(_vencimentoCnhController.text) 
            : null, 
        observacoes: _obsController.text,
        itens: _respostas,
        // REMOVIDO: fotosAvarias: _fotos, 
        lastModified: DateTime.now(),
      );

      final repo = VehicleChecklistRepository();
      await repo.insertChecklist(checklist); 

      if (mounted) {
        await PdfService().gerarChecklistVeicularPdf(context, checklist);
        Navigator.pop(context, true);
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.checklistParaEditar != null ? "Editar Checklist" : "Checklist Diário")),
      body: _isSaving 
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text("Identificação", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _categoriaCnhController,
                        decoration: const InputDecoration(labelText: "Categoria CNH", border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _vencimentoCnhController,
                        readOnly: true,
                        onTap: () => _selecionarVencimento(context),
                        decoration: const InputDecoration(
                          labelText: "Vencimento CNH", 
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today)
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),

                const Text("Dados do Veículo", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _prefixoController,
                        decoration: const InputDecoration(labelText: "Prefixo", border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _modeloController,
                        decoration: const InputDecoration(labelText: "Modelo do Veículo", border: OutlineInputBorder()),
                        validator: (v) => v!.isEmpty ? "Obrigatório" : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _placaController,
                        decoration: const InputDecoration(labelText: "Placa", border: OutlineInputBorder()),
                        validator: (v) => v!.isEmpty ? "Obrigatório" : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _kmController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "KM Atual", border: OutlineInputBorder()),
                        validator: (v) => v!.isEmpty ? "Obrigatório" : null,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 30, thickness: 2),
                const Text("Itens de Verificação", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text("C ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                    Text("| NC ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    Text("| NA", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    SizedBox(width: 10),
                  ],
                ),
                
                ...checklistItensDescricao.asMap().entries.map((entry) {
                  final index = entry.key + 1;
                  final desc = entry.value;
                  
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(desc, style: const TextStyle(fontWeight: FontWeight.w500)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _buildRadio(index.toString(), 'C', Colors.green),
                              _buildRadio(index.toString(), 'NC', Colors.red),
                              _buildRadio(index.toString(), 'NA', Colors.grey),
                            ],
                          )
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 20),
                
                // REMOVIDO: _buildFotosSection(), 

                TextFormField(
                  controller: _obsController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: "Observações Gerais", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text("Salvar e Gerar Relatório"),
                  onPressed: _salvarEGerarPdf,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF023853),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16)
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
    );
  }

  Widget _buildRadio(String itemIndex, String value, Color color) {
    return Row(
      children: [
        Radio<String>(
          value: value,
          groupValue: _respostas[itemIndex],
          activeColor: color,
          onChanged: (val) {
            setState(() {
              _respostas[itemIndex] = val!;
            });
          },
          visualDensity: VisualDensity.compact,
        ),
        Text(value, style: TextStyle(fontSize: 12, color: _respostas[itemIndex] == value ? color : Colors.black54)),
        const SizedBox(width: 8),
      ],
    );
  }
}
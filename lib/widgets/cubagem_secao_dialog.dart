// lib/widgets/cubagem_secao_dialog.dart (VERSÃO CORRIGIDA COM SALVAR E PRÓXIMA)

import 'package:flutter/material.dart';
import '../models/cubagem_secao_model.dart';

// NOVA CLASSE DE RESULTADO para o diálogo de seção
class SecaoDialogResult {
  final CubagemSecao secao;
  final bool irParaProximaSecao;

  SecaoDialogResult({
    required this.secao,
    this.irParaProximaSecao = false,
  });
}

class CubagemSecaoDialog extends StatefulWidget {
  final CubagemSecao secaoParaEditar;

  const CubagemSecaoDialog({
    super.key,
    required this.secaoParaEditar,
  });

  @override
  State<CubagemSecaoDialog> createState() => _CubagemSecaoDialogState();
}

class _CubagemSecaoDialogState extends State<CubagemSecaoDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _circunferenciaController;
  late TextEditingController _casca1Controller;
  late TextEditingController _casca2Controller;

  @override
  void initState() {
    super.initState();
    _circunferenciaController = TextEditingController(text: widget.secaoParaEditar.circunferencia > 0 ? widget.secaoParaEditar.circunferencia.toString() : '');
    _casca1Controller = TextEditingController(text: widget.secaoParaEditar.casca1_mm > 0 ? widget.secaoParaEditar.casca1_mm.toString() : '');
    _casca2Controller = TextEditingController(text: widget.secaoParaEditar.casca2_mm > 0 ? widget.secaoParaEditar.casca2_mm.toString() : '');
  }

  @override
  void dispose() {
    _circunferenciaController.dispose();
    _casca1Controller.dispose();
    _casca2Controller.dispose();
    super.dispose();
  }

  // Modificar _salvar para aceitar um parâmetro 'irParaProximaSecao'
  void _salvar({required bool irParaProximaSecao}) {
    if (_formKey.currentState!.validate()) {
      final secaoAtualizada = CubagemSecao(
        id: widget.secaoParaEditar.id,
        cubagemArvoreId: widget.secaoParaEditar.cubagemArvoreId,
        alturaMedicao: widget.secaoParaEditar.alturaMedicao,
        circunferencia: double.tryParse(_circunferenciaController.text.replaceAll(',', '.')) ?? 0,
        casca1_mm: double.tryParse(_casca1Controller.text.replaceAll(',', '.')) ?? 0,
        casca2_mm: double.tryParse(_casca2Controller.text.replaceAll(',', '.')) ?? 0,
      );
      // Retorna o novo SecaoDialogResult
      Navigator.of(context).pop(SecaoDialogResult(secao: secaoAtualizada, irParaProximaSecao: irParaProximaSecao));
    }
  }
  
  String? _validadorObrigatorio(String? v) {
    if (v == null || v.trim().isEmpty) {
      return 'Obrigatório';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Medição em ${widget.secaoParaEditar.alturaMedicao.toStringAsFixed(2)}m'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _circunferenciaController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Circunferência (cm)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: _validadorObrigatorio, // Circunferência continua obrigatória
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _casca1Controller,
                decoration: const InputDecoration(labelText: 'Espessura Casca 1 (mm)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                // <<< REMOVA O VALIDADOR DAQUI >>>
                // validator: _validadorObrigatorio, 
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _casca2Controller,
                decoration: const InputDecoration(labelText: 'Espessura Casca 2 (mm)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                // <<< E REMOVA O VALIDADOR DAQUI >>>
                // validator: _validadorObrigatorio,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        // Botão "Confirmar" (apenas salva e fecha)
        FilledButton(onPressed: () => _salvar(irParaProximaSecao: false), child: const Text('Confirmar')),
        // NOVO Botão "Salvar e Próxima"
        FilledButton(
          onPressed: () => _salvar(irParaProximaSecao: true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey), // Cor diferente para destacar
          child: const Text('Salvar e Próxima'),
        ),
      ],
    );
  }
}

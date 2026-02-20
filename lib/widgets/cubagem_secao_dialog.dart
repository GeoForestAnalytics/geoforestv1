import 'package:flutter/material.dart';
import '../models/cubagem_secao_model.dart';

// Enum para controlar a direção da navegação
enum SecaoNavigation { salvarEFechar, proxima, anterior }

class SecaoDialogResult {
  final CubagemSecao secao;
  final SecaoNavigation navigation;

  SecaoDialogResult({
    required this.secao,
    required this.navigation,
  });
}

class CubagemSecaoDialog extends StatefulWidget {
  final CubagemSecao secaoParaEditar;
  final bool isPrimeira; // Para desabilitar o botão "Anterior" se for a primeira
  final bool isUltima;   // Para mudar o texto do "Próxima" se for a última

  const CubagemSecaoDialog({
    super.key,
    required this.secaoParaEditar,
    this.isPrimeira = false,
    this.isUltima = false,
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

  void _salvar(SecaoNavigation navigation) {
    if (_formKey.currentState!.validate()) {
      final secaoAtualizada = CubagemSecao(
        id: widget.secaoParaEditar.id,
        cubagemArvoreId: widget.secaoParaEditar.cubagemArvoreId,
        alturaMedicao: widget.secaoParaEditar.alturaMedicao,
        circunferencia: double.tryParse(_circunferenciaController.text.replaceAll(',', '.')) ?? 0,
        casca1_mm: double.tryParse(_casca1Controller.text.replaceAll(',', '.')) ?? 0,
        casca2_mm: double.tryParse(_casca2Controller.text.replaceAll(',', '.')) ?? 0,
      );
      
      Navigator.of(context).pop(SecaoDialogResult(
        secao: secaoAtualizada, 
        navigation: navigation
      ));
    }
  }
  
  String? _validadorObrigatorio(String? v) {
    if (v == null || v.trim().isEmpty) return 'Obrigatório';
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
                validator: _validadorObrigatorio,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _casca1Controller,
                      decoration: const InputDecoration(labelText: 'Casca 1 (mm)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _casca2Controller,
                      decoration: const InputDecoration(labelText: 'Casca 2 (mm)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        // Linha 1: Navegação (Anterior / Próxima)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: widget.isPrimeira ? null : () => _salvar(SecaoNavigation.anterior),
              icon: const Icon(Icons.arrow_back_ios, size: 16),
              label: const Text('Anterior'),
            ),
            Directionality(
              textDirection: TextDirection.rtl,
              child: TextButton.icon(
                onPressed: () => _salvar(SecaoNavigation.proxima),
                icon: const Icon(Icons.arrow_back_ios, size: 16), // Seta para direita por causa do RTL
                label: Text(widget.isUltima ? 'Salvar' : 'Próxima'),
              ),
            ),
          ],
        ),
        const Divider(),
        // Linha 2: Ações Principais
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(), 
              child: const Text('Cancelar', style: TextStyle(color: Colors.red))
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _salvar(SecaoNavigation.salvarEFechar), 
              child: const Text('Confirmar e Fechar')
            ),
          ],
        ),
      ],
    );
  }
}
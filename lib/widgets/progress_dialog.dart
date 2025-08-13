// lib/widgets/progress_dialog.dart (NOVO ARQUIVO)

import 'package:flutter/material.dart';

class ProgressDialog extends StatelessWidget {
  final String message;

  const ProgressDialog({super.key, required this.message});

  static void show(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false, // Impede que o usuário feche o diálogo
      builder: (BuildContext context) {
        return PopScope( // Impede o botão "Voltar" do Android de fechar
          canPop: false,
          child: ProgressDialog(message: message),
        );
      },
    );
  }

  static void hide(BuildContext context) {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text(message),
          ],
        ),
      ),
    );
  }
}
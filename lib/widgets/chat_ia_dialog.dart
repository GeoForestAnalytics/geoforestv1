import 'package:flutter/material.dart';
import 'package:geoforestv1/models/arvore_model.dart';
import 'package:geoforestv1/models/parcela_model.dart';
import 'package:geoforestv1/services/ai_validation_service.dart';

class ChatIaDialog extends StatefulWidget {
  final Parcela parcela;
  final List<Arvore> arvores;

  const ChatIaDialog({super.key, required this.parcela, required this.arvores});

  @override
  State<ChatIaDialog> createState() => _ChatIaDialogState();
}

class _ChatIaDialogState extends State<ChatIaDialog> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _aiService = AiValidationService();
  
  // Lista para manter o histórico da conversa no diálogo
  final List<Map<String, String>> _mensagens = [
    {
      "role": "ai",
      "text": "Olá! Analisei os dados desta parcela. Posso verificar erros de digitação, calcular médias ou tirar dúvidas técnicas. Como posso ajudar?"
    }
  ];
  
  bool _isLoading = false;

  void _enviarPergunta({String? perguntaPredefinida}) async {
    final texto = perguntaPredefinida ?? _controller.text;
    if (texto.isEmpty) return;
    
    setState(() {
      _mensagens.add({"role": "user", "text": texto});
      _isLoading = true;
      _controller.clear();
    });

    _scrollToBottom();

    final respostaIa = await _aiService.perguntarSobreDados(
      texto, 
      widget.parcela, 
      widget.arvores
    );

    if (mounted) {
      setState(() {
        _mensagens.add({"role": "ai", "text": respostaIa});
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.blue.shade100, shape: BoxShape.circle),
            child: const Icon(Icons.auto_awesome, color: Colors.blue, size: 20),
          ),
          const SizedBox(width: 12),
          const Text("GeoForest AI", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Listagem de Mensagens (Histórico)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                constraints: const BoxConstraints(maxHeight: 350),
                child: ListView.builder(
                  controller: _scrollController,
                  shrinkWrap: true,
                  itemCount: _mensagens.length,
                  itemBuilder: (context, index) {
                    final msg = _mensagens[index];
                    final isAi = msg["role"] == "ai";
                    return _buildBubble(msg["text"]!, isAi);
                  },
                ),
              ),
            ),
            
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: LinearProgressIndicator(backgroundColor: Colors.transparent),
              ),

            const SizedBox(height: 12),

            // Sugestões de Ação Rápida
            if (!_isLoading)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildQuickAction("🔍 Analisar Erros"),
                    _buildQuickAction("📊 Resumo Estatístico"),
                    _buildQuickAction("🌲 Dominantes"),
                  ],
                ),
              ),
              
            const SizedBox(height: 12),

            // Input de texto
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: "Dúvida sobre a coleta...",
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: _isLoading ? null : () => _enviarPergunta(),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (_) => _enviarPergunta(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fechar"))
      ],
    );
  }

  Widget _buildBubble(String texto, bool isAi) {
    return Align(
      alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isAi ? Colors.grey.shade100 : Colors.blue.shade500,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isAi ? 0 : 12),
            bottomRight: Radius.circular(isAi ? 12 : 0),
          ),
          border: isAi ? Border.all(color: Colors.grey.shade300) : null,
        ),
        child: Text(
          texto,
          style: TextStyle(color: isAi ? Colors.black87 : Colors.white, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildQuickAction(String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: _isLoading ? null : () => _enviarPergunta(perguntaPredefinida: label),
        backgroundColor: Colors.blue.shade50,
        side: BorderSide(color: Colors.blue.shade100),
      ),
    );
  }
}
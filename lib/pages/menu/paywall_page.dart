// lib/pages/menu/paywall_page.dart (VERSÃO FINAL - CONTRASTE CORRIGIDO)

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

// Modelo para representar um plano.
class PlanoAssinatura {
  final String nome;
  final String descricao;
  final String valorAnual;
  final String valorMensal;
  final IconData icone;
  final Color cor;
  final List<String> features;

  PlanoAssinatura({
    required this.nome,
    required this.descricao,
    required this.valorAnual,
    required this.valorMensal,
    required this.icone,
    required this.cor,
    required this.features,
  });
}

class PaywallPage extends StatefulWidget {
  const PaywallPage({super.key});

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  // Lista de planos para exibir no catálogo.
  final List<PlanoAssinatura> planos = [
    PlanoAssinatura(
      nome: "Básico",
      descricao: "Para equipes pequenas e projetos iniciais.",
      valorAnual: "", //"R\$ 5.000",
      valorMensal: "", //"R\$ 600",
      icone: Icons.person_outline,
      cor: Colors.blue,
      features: ["3 Smartphones", "Exportação de dados", "Suporte por e-mail"],
    ),
    PlanoAssinatura(
      nome: "Profissional",
      descricao: "Ideal para empresas em crescimento.",
      valorAnual: "", //"R\$ 9.000",
      valorMensal: "", //"R\$ 850",
      icone: Icons.business_center_outlined,
      cor: Colors.green,
      features: ["7 Smartphones", "Módulo de Análise e Relatórios", "Suporte prioritário"],
    ),
    PlanoAssinatura(
      nome: "Premium",
      descricao: "A solução completa para grandes operações.",
      valorAnual: "", //"R\$ 15.000",
      valorMensal: "", //"R\$ 1.700",
      icone: Icons.star_border_outlined,
      cor: Colors.purple,
      features: ["Dispositivos ilimitados", "Todos os Módulos", "Delegação de Projetos", "Gerente de conta dedicado"],
    ),
  ];

  /// Esta função gera a mensagem e abre o WhatsApp.
  Future<void> iniciarContatoWhatsApp(PlanoAssinatura plano, String tipoCobranca) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erro: Usuário não encontrado. Por favor, faça login novamente."))
        );
      }
      return;
    }

    // !! IMPORTANTE !! TROQUE ESTE NÚMERO PELO SEU NÚMERO COMERCIAL !!
    final String seuNumeroWhatsApp = "5515981409153"; 
    
    final String nomePlano = plano.nome;
    final String emailUsuario = user.email ?? "Email não disponível";

    final String mensagem = "Olá! Tenho interesse em contratar o plano *$nomePlano ($tipoCobranca)* para o GeoForest Analytics. Meu email de cadastro é: $emailUsuario";
    
    final String urlWhatsApp = "https://wa.me/$seuNumeroWhatsApp?text=${Uri.encodeComponent(mensagem )}";
    final Uri uri = Uri.parse(urlWhatsApp);

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Não foi possível abrir o WhatsApp. Certifique-se de que ele está instalado."))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Detecta o tema para ajustar as cores do texto de fundo
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color subtitleColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      appBar: AppBar(title: const Text("Escolha seu Plano"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            "Aproveite o Futuro em Análises e Coletas Florestais",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF66BB6A)), // Verde mais claro para contrastar
          ),
          const SizedBox(height: 8),
          Text(
            "Escolha um plano para destravar todos os recursos e continuar crescendo.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: subtitleColor), // Cor dinâmica
          ),
          const SizedBox(height: 24),
          // Mapeia os planos para o widget PlanoCard
          ...planos.map((plano) => PlanoCard(
                plano: plano,
                onSelecionar: (planoSelecionado, tipoCobranca) => 
                    iniciarContatoWhatsApp(planoSelecionado, tipoCobranca),
              )).toList(),
        ],
      ),
    );
  }
}

// Widget do Card
class PlanoCard extends StatelessWidget {
  final PlanoAssinatura plano;
  final Function(PlanoAssinatura plano, String tipoCobranca) onSelecionar;

  const PlanoCard({
    super.key,
    required this.plano,
    required this.onSelecionar,
  });

  @override
  Widget build(BuildContext context) {
    // Detecta o tema dentro do Card
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Cores adaptativas para o conteúdo do card
    final Color descriptionColor = isDark ? Colors.white60 : Colors.black54;
    final Color featureTextColor = isDark ? Colors.white70 : Colors.black87;
    final Color cardBgColor = isDark ? const Color(0xFF1E293B) : Colors.white; // Azul escuro ou Branco

    return Card(
      elevation: 4,
      color: cardBgColor, // Fundo do card explícito
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: plano.cor, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(plano.icone, size: 40, color: plano.cor),
            const SizedBox(height: 12),
            Text(
              plano.nome,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: plano.cor),
            ),
            const SizedBox(height: 8),
            Text(
              plano.descricao,
              style: TextStyle(fontSize: 15, color: descriptionColor), // Cor corrigida
            ),
            const Divider(height: 32),
            ...plano.features.map((feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: 20, color: Colors.green.shade400),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          feature, 
                          style: TextStyle(fontSize: 16, color: featureTextColor), // Cor corrigida
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onSelecionar(plano, "Mensal"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: plano.cor),
                      // Garante que o texto tenha a cor do plano ou branco, para não ficar escuro
                      foregroundColor: isDark ? Colors.white : plano.cor,
                    ),
                    child: Text("${plano.valorMensal}Mensal"),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => onSelecionar(plano, "Anual"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: plano.cor,
                      foregroundColor: Colors.white, // Texto sempre branco no botão cheio
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text("${plano.valorAnual}Anual"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
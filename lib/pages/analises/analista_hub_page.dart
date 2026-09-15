import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:geoforestv1/pages/analises/analise_selecao_page.dart';
import 'package:geoforestv1/pages/analises/ai_analista_page.dart';

class AnalistaHubPage extends StatelessWidget {
  const AnalistaHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final license = context.watch<LicenseProvider>().licenseData;
    final temInventario = true; // análise sempre disponível se chegou até aqui
    final temColheita = license?.isModuloColheita ?? false;
    final temSilvicultura = license?.isModuloSilvicultura ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GeoForest Analista'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Text(
            'Selecione o módulo para análise',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          _ModuloTile(
            icon: Icons.forest_outlined,
            cor: Colors.green.shade700,
            titulo: 'Inventário Florestal',
            descricao: 'Estrato, volumes, cubagem, planos e auditoria IA',
            itens: const [
              'Dashboard de estrato',
              'Tabela comparativa',
              'Equação de volume (Schumacher-Hall)',
              'Planos de cubagem em lote',
              'Auditoria IA',
            ],
            disponivel: temInventario,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AnaliseSelecaoPage()),
            ),
          ),
          const SizedBox(height: 16),
          _ModuloTile(
            icon: Icons.local_shipping_outlined,
            cor: Colors.orange.shade700,
            titulo: 'Colheita',
            descricao: 'Volume por sortimento, produtividade e rastreio de pilhas',
            itens: const [
              'Volume colhido por fazenda/talhão',
              'Ranking de produtividade',
              'Análise por sortimento',
              'Histórico de saídas de estoque',
            ],
            disponivel: temColheita,
            onTap: () => _mostrarEmBreve(context, 'Colheita'),
            mensagemBloqueio:
                'Sua conta não tem liberação para o módulo Colheita.\nVocê pode utilizar apenas a análise de Inventário Florestal.',
          ),
          const SizedBox(height: 16),
          _ModuloTile(
            icon: Icons.eco_outlined,
            cor: Colors.teal.shade700,
            titulo: 'Silvicultura',
            descricao: 'Área aplicada, progresso por operação e cobertura por fazenda',
            itens: const [
              'Área aplicada por tipo de operação',
              'Progresso vs planejado',
              'Ranking de cobertura por fazenda',
              'Histórico de operações',
            ],
            disponivel: temSilvicultura,
            onTap: () => _mostrarEmBreve(context, 'Silvicultura'),
            mensagemBloqueio:
                'Sua conta não tem liberação para o módulo Silvicultura.\nVocê pode utilizar apenas a análise de Inventário Florestal.',
          ),
          const SizedBox(height: 16),
          _ModuloTile(
            icon: Icons.auto_awesome_outlined,
            cor: Colors.deepPurple.shade600,
            titulo: 'IA Analista',
            descricao: 'Chat inteligente com dados consolidados de todos os módulos',
            itens: const [
              'Resumo executivo automático',
              'Perguntas em linguagem natural',
              'Análise de produtividade por líder',
              'Comparativo entre módulos',
              'Identificação de gargalos e atrasos',
            ],
            disponivel: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiAnalistaPage()),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _mostrarEmBreve(BuildContext context, String modulo) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(Icons.construction_outlined, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Text('$modulo — Em breve'),
        ]),
        content: const Text(
          'Este módulo de análise está sendo desenvolvido e estará disponível em breve.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _ModuloTile extends StatelessWidget {
  final IconData icon;
  final Color cor;
  final String titulo;
  final String descricao;
  final List<String> itens;
  final bool disponivel;
  final VoidCallback onTap;
  final String? mensagemBloqueio;

  const _ModuloTile({
    required this.icon,
    required this.cor,
    required this.titulo,
    required this.descricao,
    required this.itens,
    required this.disponivel,
    required this.onTap,
    this.mensagemBloqueio,
  });

  @override
  Widget build(BuildContext context) {
    final bloqueado = !disponivel && mensagemBloqueio != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: bloqueado ? 1 : 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: bloqueado ? () => _mostrarBloqueio(context) : onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header colorido
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              color: bloqueado
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : cor,
              child: Row(
                children: [
                  Icon(icon,
                      color: bloqueado
                          ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)
                          : Colors.white,
                      size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: bloqueado
                                ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)
                                : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          descricao,
                          style: TextStyle(
                            fontSize: 12,
                            color: bloqueado
                                ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (bloqueado)
                    Icon(Icons.lock_outline,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
                        size: 24)
                  else
                    const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
                ],
              ),
            ),
            // Lista de recursos
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: itens
                    .map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                bloqueado ? Icons.remove : Icons.check_circle_outline,
                                size: 16,
                                color: bloqueado
                                    ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)
                                    : cor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: bloqueado
                                        ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35)
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarBloqueio(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(Icons.lock_outline, color: Colors.orange.shade700, size: 36),
        title: Text('Módulo $titulo'),
        content: Text(mensagemBloqueio!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
}

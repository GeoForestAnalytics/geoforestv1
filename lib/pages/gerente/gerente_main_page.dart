import 'package:flutter/material.dart';
import 'package:geoforestv1/pages/gerente/pilhas_dashboard_page.dart';
import 'package:geoforestv1/pages/gerente/projetos_dashboard_page.dart';
import 'package:geoforestv1/pages/gerente/operacoes_dashboard_page.dart';
import 'package:geoforestv1/pages/menu/home_page.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:provider/provider.dart';

class GerenteMainPage extends StatefulWidget {
  const GerenteMainPage({super.key});

  @override
  State<GerenteMainPage> createState() => _GerenteMainPageState();
}

class _GerenteMainPageState extends State<GerenteMainPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final modulo = context.watch<LicenseProvider>().licenseData?.modulo ?? 'inventario';
    final tabs = _buildTabs(modulo);

    // Garante que o índice não ultrapasse o número de tabs disponíveis
    final safeIndex = _selectedIndex.clamp(0, tabs.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: Text(tabs[safeIndex].title),
        automaticallyImplyLeading: false,
      ),
      body: IndexedStack(
        index: safeIndex,
        children: tabs.map((t) => t.page).toList(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: safeIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        items: tabs.map((t) => BottomNavigationBarItem(icon: Icon(t.icon), label: t.label)).toList(),
      ),
    );
  }

  List<_TabItem> _buildTabs(String modulo) {
    final tabs = <_TabItem>[
      _TabItem(
        title: 'Modo Coleta de Campo',
        label: 'Coleta',
        icon: Icons.park_outlined,
        page: const HomePage(title: 'Modo Coleta de Campo', showAppBar: false),
      ),
    ];

    if (modulo == 'inventario' || modulo == 'todos') {
      tabs.add(_TabItem(
        title: 'Inventário / Cubagem',
        label: 'Inventário',
        icon: Icons.bar_chart_outlined,
        page: const ProjetosDashboardPage(),
      ));
    }

    if (modulo == 'colheita' || modulo == 'todos') {
      tabs.add(_TabItem(
        title: 'Colheita',
        label: 'Colheita',
        icon: Icons.forest_outlined,
        page: const PilhasDashboardPage(),
      ));
    }

    tabs.add(_TabItem(
      title: 'Dashboard de Operações',
      label: 'Operações',
      icon: Icons.insights_outlined,
      page: const OperacoesDashboardPage(),
    ));

    return tabs;
  }
}

class _TabItem {
  final String title;
  final String label;
  final IconData icon;
  final Widget page;

  const _TabItem({
    required this.title,
    required this.label,
    required this.icon,
    required this.page,
  });
}

// lib/pages/gerente/gerente_main_page.dart (VERSÃO CORRETA E FINAL)

import 'package:flutter/material.dart';
import 'package:geoforestv1/pages/gerente/projetos_dashboard_page.dart'; 
import 'package:geoforestv1/pages/gerente/operacoes_dashboard_page.dart';
import 'package:geoforestv1/pages/menu/home_page.dart';

class GerenteMainPage extends StatefulWidget {
  const GerenteMainPage({super.key});

  @override
  State<GerenteMainPage> createState() => _GerenteMainPageState();
}

class _GerenteMainPageState extends State<GerenteMainPage> {
  int _selectedIndex = 0;

  // A lista de páginas para a navegação
  static final List<Widget> _pages = <Widget>[
    const HomePage(title: 'Modo Coleta de Campo', showAppBar: false),
    const ProjetosDashboardPage(),
    const OperacoesDashboardPage(),
  ];

  // Os títulos correspondentes para a AppBar
  static const List<String> _pageTitles = <String>[
    'Modo Coleta de Campo',
    'Dashboard de Projetos',
    'Dashboard de Operações',
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitles.elementAt(_selectedIndex)),
        automaticallyImplyLeading: false, 
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.park_outlined),
            label: 'Coleta',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            label: 'Projetos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.insights_outlined),
            label: 'Operações',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
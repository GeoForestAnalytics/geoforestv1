// lib/widgets/weather_header.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geoforestv1/utils/app_config.dart';
import 'package:geoforestv1/data/repositories/vehicle_checklist_repository.dart';
import 'package:geoforestv1/models/vehicle_checklist_model.dart';
import 'package:geoforestv1/pages/menu/vehicle_checklist_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WeatherHeader extends StatefulWidget {
  const WeatherHeader({super.key});

  @override
  State<WeatherHeader> createState() => _WeatherHeaderState();
}

class _WeatherHeaderState extends State<WeatherHeader> {
  // Variáveis de Estado do Clima
  String _cidade = "Localizando...";
  String _temperatura = "--";
  String _descricao = "Aguarde...";
  IconData _iconeClima = Icons.cloud_sync;
  bool _isLoading = true;
  String _nomeUsuario = "Florestal";

  // Variável para controlar o estado do checklist
  bool _checklistFeitoHoje = false;

  @override
  void initState() {
    super.initState();
    _carregarUsuario();
    _checkStatusChecklist(); // Verifica status ao iniciar
    
    Future.delayed(Duration.zero, () {
      _carregarClima();
    });
  }

  void _carregarUsuario() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.displayName != null && user.displayName!.isNotEmpty) {
      final nomeCompleto = user.displayName!;
      final primeiroNome = nomeCompleto.split(' ')[0];
      final nomeFormatado = "${primeiroNome[0].toUpperCase()}${primeiroNome.substring(1)}";
      if (mounted) setState(() => _nomeUsuario = nomeFormatado);
    }
  }

  // Verifica no banco se já existe checklist hoje
  Future<void> _checkStatusChecklist() async {
    final repo = VehicleChecklistRepository();
    final feito = await repo.hasChecklistForToday();
    if (mounted) setState(() => _checklistFeitoHoje = feito);
  }

  // Ação ao clicar no botão de checklist
  Future<void> _handleChecklistClick() async {
    final repo = VehicleChecklistRepository();
    
    // 1. Tenta buscar um checklist já existente hoje
    final checklistExistente = await repo.getChecklistForToday();

    if (checklistExistente != null) {
      // 2. Se existe, pergunta se quer editar/visualizar
      final bool? querEditar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Checklist Realizado"),
          content: Text(
            checklistExistente.isMotorista 
              ? "Você já preencheu o checklist do veículo ${checklistExistente.modeloVeiculo} hoje."
              : "Você registrou que não é motorista hoje."
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Fechar")),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true), 
              icon: const Icon(Icons.edit),
              label: const Text("Editar / Gerar PDF")
            ),
          ],
        ),
      );

      if (querEditar == true) {
        // Se for "Não Motorista" e quiser editar, abre o form vazio (convertendo para motorista)
        // Se for "Motorista", abre o form preenchido
        
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VehicleChecklistPage(
              // Se ele era "Não Motorista", não passamos dados para preencher, ele começa do zero
              checklistParaEditar: checklistExistente.isMotorista ? checklistExistente : checklistExistente
            )
          ),
        );
        if (result == true) _checkStatusChecklist();
      }
      return;
    }

    // 3. Se NÃO existe, segue o fluxo normal de criação
    final bool? isMotorista = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Checklist Diário"),
        content: const Text("Você será o motorista da equipe hoje?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Não")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Sim")),
        ],
      ),
    );

    if (isMotorista == null) return;

    if (isMotorista) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const VehicleChecklistPage()),
      );
      if (result == true) _checkStatusChecklist();
    } else {
      final prefs = await SharedPreferences.getInstance();
      final nome = prefs.getString('nome_lider') ?? _nomeUsuario;
      
      final checklistSimples = VehicleChecklist(
        dataRegistro: DateTime.now(),
        nomeMotorista: nome,
        isMotorista: false, 
        lastModified: DateTime.now(),
      );
      
      await VehicleChecklistRepository().insertChecklist(checklistSimples);
      await _checkStatusChecklist();
      
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Registro salvo."), backgroundColor: Colors.green));
      }
    }
  }

  // --- LÓGICA DO CLIMA (Mantida) ---
  Future<void> _carregarClima() async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      if (connectivityResults.isEmpty || connectivityResults.contains(ConnectivityResult.none)) {
        if (mounted) {
          setState(() {
            _cidade = "Sem conexão"; _temperatura = "--"; _descricao = "Offline"; _iconeClima = Icons.signal_wifi_off; _isLoading = false;
          });
        }
        return;
      }
      Position posicao = await _determinarPosicao();
      final url = Uri.parse('https://api.openweathermap.org/data/2.5/weather?lat=${posicao.latitude}&lon=${posicao.longitude}&appid=${AppConfig.openWeatherApiKey}&units=metric&lang=pt_br');
      final response = await http.get(url).timeout(AppConfig.shortNetworkTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _cidade = data['name'] ?? 'Desconhecido';
            _temperatura = "${data['main']['temp'].toStringAsFixed(0)}°C";
            String desc = data['weather'][0]['description'] ?? '';
            _descricao = desc.isNotEmpty ? desc[0].toUpperCase() + desc.substring(1) : '';
            _iconeClima = _getIconForCondition(data['weather'][0]['id'] ?? 800);
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() { _cidade = "Erro"; _temperatura = "--"; _descricao = "Erro"; _iconeClima = Icons.error_outline; _isLoading = false; });
    }
  }

  Future<Position> _determinarPosicao() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('GPS off');
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return Future.error('Permissão negada');
    
    Position? last = await Geolocator.getLastKnownPosition();
    if (last != null) return last;
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium, timeLimit: const Duration(seconds: 10));
  }

  IconData _getIconForCondition(int condition) {
    if (condition < 300) return Icons.thunderstorm;
    if (condition < 600) return Icons.umbrella;
    if (condition < 800) return Icons.ac_unit;
    if (condition == 800) return Icons.wb_sunny;
    return Icons.cloud;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateStr = DateFormat('EEEE, d MMM', 'pt_BR').format(now);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 50, 16, 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark 
              ? [const Color(0xFF1E3C72), const Color(0xFF2A5298)]
              : [const Color(0xFF4B79A1), const Color(0xFF283E51)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ESQUERDA (Data, Nome e Local)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateStr.toUpperCase(), style: const TextStyle(color: Color(0xFFEBE4AB), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                const SizedBox(height: 4),
                Text("Olá, $_nomeUsuario!", style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Color(0xFFEBE4AB), size: 14),
                    const SizedBox(width: 4),
                    Flexible(child: Text(_cidade, style: const TextStyle(color: Colors.white70, fontSize: 13), overflow: TextOverflow.ellipsis)),
                  ],
                )
              ],
            ),
          ),
          
          const SizedBox(width: 8),

          // CENTRO: CHECKLIST (Onde você pediu)
          GestureDetector(
            onTap: _handleChecklistClick,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _checklistFeitoHoje ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                border: Border.all(color: _checklistFeitoHoje ? Colors.green : Colors.red, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _checklistFeitoHoje ? Icons.check_circle : Icons.warning_amber_rounded,
                    color: _checklistFeitoHoje ? Colors.greenAccent : Colors.redAccent,
                    size: 22
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "CHECKLIST",
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: _checklistFeitoHoje ? Colors.greenAccent : Colors.redAccent,
                      letterSpacing: 0.5
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // DIREITA: CLIMA
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF023853).withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFFEBE4AB), strokeWidth: 2))
                : Column(
                    children: [
                      Icon(_iconeClima, color: const Color(0xFFEBE4AB), size: 26),
                      const SizedBox(height: 2),
                      Text(_temperatura, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(_descricao, style: const TextStyle(color: Colors.white70, fontSize: 8), overflow: TextOverflow.ellipsis, maxLines: 1)
                    ],
                  ),
          )
        ],
      ),
    );
  }
}
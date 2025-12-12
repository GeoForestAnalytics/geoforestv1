// lib/widgets/weather_header.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class WeatherHeader extends StatefulWidget {
  const WeatherHeader({super.key});

  @override
  State<WeatherHeader> createState() => _WeatherHeaderState();
}

class _WeatherHeaderState extends State<WeatherHeader> {
  // Variáveis de Estado
  String _cidade = "Localizando...";
  String _temperatura = "--";
  String _descricao = "Aguarde...";
  IconData _iconeClima = Icons.cloud_sync;
  bool _isLoading = true;

  // --- SUA CHAVE NOVA JÁ CONFIGURADA ---
  final String _apiKey = "44c419e21659fd02589ddc5f3be43f89";

  @override
  void initState() {
    super.initState();
    // Pequeno delay para garantir que a interface carregou antes de chamar o GPS
    Future.delayed(Duration.zero, () {
      _carregarClima();
    });
  }

  Future<void> _carregarClima() async {
    try {
      // 1. Pega a posição (agora mais robusto)
      Position posicao = await _determinarPosicao();

      // 2. Chama a API
      final url = Uri.parse(
          'https://api.openweathermap.org/data/2.5/weather?lat=${posicao.latitude}&lon=${posicao.longitude}&appid=$_apiKey&units=metric&lang=pt_br');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (mounted) {
          setState(() {
            _cidade = data['name'];
            _temperatura = "${data['main']['temp'].toStringAsFixed(0)}°C";
            
            // Arruma a descrição (Primeira letra maiúscula)
            String desc = data['weather'][0]['description'];
            _descricao = desc[0].toUpperCase() + desc.substring(1);
            
            // Ícone
            int conditionId = data['weather'][0]['id'];
            _iconeClima = _getIconForCondition(conditionId);
            
            _isLoading = false;
          });
        }
      } else {
        // Se der erro, mostra no terminal o motivo real
        print("ERRO API CLIMA: Código ${response.statusCode} - Corpo: ${response.body}");
        throw Exception('Erro na API: ${response.statusCode}');
      }
    } catch (e) {
      print("Erro geral no clima: $e");
      if (mounted) {
        setState(() {
          _cidade = "Sem sinal GPS";
          _temperatura = "--";
          _descricao = "Verifique conexão";
          _iconeClima = Icons.signal_wifi_off;
          _isLoading = false;
        });
      }
    }
  }

  // Função de GPS melhorada para Emuladores e Celulares
  Future<Position> _determinarPosicao() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. Verifica se GPS está ligado
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('GPS desligado.');
    }

    // 2. Verifica Permissões
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Permissão negada.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return Future.error('Permissão negada permanentemente.');
    }

    // 3. Tenta pegar a ÚLTIMA posição conhecida (É instantâneo e funciona melhor no emulador)
    Position? lastPosition = await Geolocator.getLastKnownPosition();
    if (lastPosition != null) {
      return lastPosition;
    }

    // 4. Se não tiver última, tenta pegar a atual (com timeout para não travar)
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium, 
      timeLimit: const Duration(seconds: 10),
    );
  }

  IconData _getIconForCondition(int condition) {
    if (condition < 300) return Icons.thunderstorm;
    if (condition < 400) return Icons.water_drop;
    if (condition < 600) return Icons.umbrella;
    if (condition < 700) return Icons.ac_unit;
    if (condition < 800) return Icons.foggy;
    if (condition == 800) return Icons.wb_sunny;
    if (condition <= 804) return Icons.cloud;
    return Icons.wb_cloudy;
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
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ESQUERDA
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateStr.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFFEBE4AB),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Olá, Florestal!",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, color: Color(0xFFEBE4AB), size: 14),
                  const SizedBox(width: 4),
                  Text(
                    _cidade,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              )
            ],
          ),
          
          // DIREITA (CLIMA)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF023853).withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24, 
                    height: 24, 
                    child: CircularProgressIndicator(color: Color(0xFFEBE4AB), strokeWidth: 2)
                  )
                : Column(
                    children: [
                      Icon(_iconeClima, color: const Color(0xFFEBE4AB), size: 30),
                      const SizedBox(height: 4),
                      Text(
                        _temperatura,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _descricao,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 9,
                        ),
                      )
                    ],
                  ),
          )
        ],
      ),
    );
  }
}
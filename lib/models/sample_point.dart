// lib/models/sample_point.dart

import 'package:latlong2/latlong.dart';

// Usar um enum é mais seguro e legível do que usar strings ("aberto", "fechado").
enum SampleStatus {
  untouched, // Intocado
  open,      // Em coleta
  completed, // Coleta finalizada
  exported,  // Já exportado
}

class SamplePoint {
  final int id;
  final LatLng position;
  Map<String, dynamic> data;
  SampleStatus status; 

  SamplePoint({
    required this.id,
    required this.position,
    Map<String, dynamic>? data,
    // O status padrão de um novo ponto é 'untouched'
    this.status = SampleStatus.untouched, 
  }) : this.data = data ?? {};

  // =========================================================================
  // ====================== MÉTODO FALTANTE ADICIONADO =======================
  // =========================================================================
  /// Cria uma cópia deste SamplePoint, permitindo a modificação de campos específicos.
  SamplePoint copyWith({
    int? id,
    LatLng? position,
    Map<String, dynamic>? data,
    SampleStatus? status,
  }) {
    return SamplePoint(
      // Se um novo valor for fornecido, use-o. Senão, use o valor do objeto atual (this).
      id: id ?? this.id,
      position: position ?? this.position,
      data: data ?? this.data,
      status: status ?? this.status,
    );
  }
  // =========================================================================
  // =========================================================================

  /// Converte um objeto SamplePoint para um Map (formato JSON)
  Map<String, dynamic> toJson() => {
    'id': id,
    'latitude': position.latitude,
    'longitude': position.longitude,
    'data': data,
    'status': status.name, // Salva o nome do enum como string, ex: "completed"
  };

  /// Cria um objeto SamplePoint a partir de um Map (formato JSON)
  factory SamplePoint.fromJson(Map<String, dynamic> json) => SamplePoint(
    id: json['id'],
    position: LatLng(json['latitude'], json['longitude']),
    data: Map<String, dynamic>.from(json['data'] ?? {}),
    // Converte a string de volta para o enum, com um valor padrão caso não encontre
    status: SampleStatus.values.firstWhere(
      (e) => e.name == json['status'], 
      orElse: () => SampleStatus.untouched
    ),
  );
}
// lib/models/atividade_model.dart (VERSÃO FINAL E CORRIGIDA)
import 'package:cloud_firestore/cloud_firestore.dart';
enum TipoAtividade {
ipc("Inventário Pré-Corte"),
ifc("Inventário Florestal Contínuo"),
cub("Cubagem Rigorosa"),
aud("Auditoria"),
ifq6("IFQ - 6 Meses"),
ifq12("IFQ - 12 Meses"),
ifs("Inventário de Sobrevivência e Qualidade"),
bio("Inventario Biomassa");
const TipoAtividade(this.descricao);
final String descricao;
}
class Atividade {
final int? id;
final int projetoId;
final String tipo;
final String descricao;
final DateTime dataCriacao;
final String? metodoCubagem;
final DateTime? lastModified;
Atividade({
this.id,
required this.projetoId,
required this.tipo,
required this.descricao,
required this.dataCriacao,
this.metodoCubagem,
this.lastModified,
});
Atividade copyWith({
int? id,
int? projetoId,
String? tipo,
String? descricao,
DateTime? dataCriacao,
String? metodoCubagem,
DateTime? lastModified,
}) {
return Atividade(
id: id ?? this.id,
projetoId: projetoId ?? this.projetoId,
tipo: tipo ?? this.tipo,
descricao: descricao ?? this.descricao,
dataCriacao: dataCriacao ?? this.dataCriacao,
metodoCubagem: metodoCubagem ?? this.metodoCubagem,
lastModified: lastModified ?? this.lastModified,
);
}
Map<String, dynamic> toMap() {
return {
'id': id,
'projetoId': projetoId,
'tipo': tipo,
'descricao': descricao,
'dataCriacao': dataCriacao.toIso8601String(),
'metodoCubagem': metodoCubagem,
'lastModified': lastModified?.toIso8601String(),
};
}
factory Atividade.fromMap(Map<String, dynamic> map) {
// <<< INÍCIO DA CORREÇÃO >>>
DateTime? parseDate(dynamic value) {
if (value is Timestamp) return value.toDate();
if (value is String) return DateTime.tryParse(value);
return null;
}
// <<< FIM DA CORREÇÃO >>>
final dataCriacao = parseDate(map['dataCriacao']);
if (dataCriacao == null) {
  throw FormatException("Formato de data inválido para 'dataCriacao' na Atividade ${map['id']}");
}

return Atividade(
  id: map['id'],
  projetoId: map['projetoId'],
  tipo: map['tipo'],
  descricao: map['descricao'],
  dataCriacao: dataCriacao,
  metodoCubagem: map['metodoCubagem'],
  lastModified: parseDate(map['lastModified']),
);
}
}
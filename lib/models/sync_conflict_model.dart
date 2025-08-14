// lib/models/sync_conflict_model.dart (NOVO ARQUIVO)

enum ConflictType { parcela, cubagem }

class SyncConflict {
  final ConflictType type;
  final dynamic localData;   // A versão que está no celular do usuário
  final dynamic serverData;  // A versão mais nova que está na nuvem
  final String identifier;    // Um ID para sabermos do que se trata (ex: Parcela P01)

  SyncConflict({
    required this.type,
    required this.localData,
    required this.serverData,
    required this.identifier,
  });
}
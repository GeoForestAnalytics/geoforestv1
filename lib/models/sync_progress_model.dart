// lib/models/sync_progress_model.dart (NOVO ARQUIVO)

class SyncProgress {
  final int totalAProcessar;
  final int processados;
  final String mensagem;
  final bool concluido;
  final String? erro;

  SyncProgress({
    this.totalAProcessar = 0,
    this.processados = 0,
    this.mensagem = 'Iniciando...',
    this.concluido = false,
    this.erro,
  });
}
class SyncProgress {
  final int totalAProcessar;   // itens para enviar (upload)
  final int processados;       // enviados até agora
  final String mensagem;
  final bool concluido;
  final String? erro;
  final bool isDownloading;    // fase de download ativa
  final int totalDownload;     // total a baixar (parcelas + cubagens)
  final int downloadados;      // baixados até agora

  SyncProgress({
    this.totalAProcessar = 0,
    this.processados = 0,
    this.mensagem = 'Iniciando...',
    this.concluido = false,
    this.erro,
    this.isDownloading = false,
    this.totalDownload = 0,
    this.downloadados = 0,
  });

  double get uploadPercent =>
      totalAProcessar > 0 ? (processados / totalAProcessar).clamp(0.0, 1.0) : 0.0;

  double get downloadPercent =>
      totalDownload > 0 ? (downloadados / totalDownload).clamp(0.0, 1.0) : 0.0;

  double get progressoGeral {
    if (!isDownloading) return uploadPercent;
    return downloadPercent;
  }
}

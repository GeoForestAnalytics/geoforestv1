import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:native_exif/native_exif.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p; // Você vai precisar do pacote 'path' no pubspec

class ImageUtils {
  /// Grava a hierarquia nos metadados e salva na galeria
  static Future<String> carimbarMetadadosESalvar({
    required String pathOriginal,
    required String informacoesHierarquia,
    required String nomeArquivoFinal,
  }) async {
    try {
      // 1. Grava no EXIF (Metadado oculto) - RAM ZERO
      final exif = await Exif.fromPath(pathOriginal);
      await exif.writeAttributes({
        'UserComment': informacoesHierarquia,
        'ImageDescription': 'Coleta realizada via Geo Forest Analytics',
      });

      // 2. Renomeia o arquivo temporário para o nome da hierarquia
      // Isso ajuda o sistema operacional a identificar o nome correto ao salvar
      final file = File(pathOriginal);
      final String extensao = p.extension(pathOriginal);
      final String novoCaminho = p.join(
        p.dirname(pathOriginal), 
        "$nomeArquivoFinal${extensao.isEmpty ? '.jpg' : extensao}"
      );
      
      final File arquivoRenomeado = await file.rename(novoCaminho);

      // 3. Salva na Galeria
      // Removido o 'name: nomeArquivoFinal' que não existe no Gal.putImage
      await Gal.putImage(arquivoRenomeado.path);

      debugPrint("Foto processada via EXIF e salva: ${arquivoRenomeado.path}");
      return arquivoRenomeado.path;
    } catch (e) {
      debugPrint("Erro no processamento de imagem: $e");
      // Se falhar a renomeação ou EXIF, tenta salvar o original para não perder o dado de campo
      try {
        await Gal.putImage(pathOriginal);
      } catch (_) {}
      return pathOriginal;
    }
  }
}
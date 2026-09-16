import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:native_exif/native_exif.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p; // Você vai precisar do pacote 'path' no pubspec

class ImageUtils {
  static const Map<String, String> _mapaAcentos = {
    'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
    'Á': 'A', 'À': 'A', 'Ã': 'A', 'Â': 'A', 'Ä': 'A',
    'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
    'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I',
    'Ó': 'O', 'Ò': 'O', 'Õ': 'O', 'Ô': 'O', 'Ö': 'O',
    'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
    'Ç': 'C', 'Ñ': 'N',
  };

  /// O plugin `native_exif` não grava corretamente caracteres acentuados no
  /// UserComment (viram "?"/lixo) — tira os acentos antes de gravar, pra garantir
  /// que o texto sobreviva legível.
  static String _semAcentos(String texto) {
    var resultado = texto;
    _mapaAcentos.forEach((acentuado, simples) => resultado = resultado.replaceAll(acentuado, simples));
    return resultado;
  }

  /// Grava a hierarquia nos metadados e (opcionalmente) salva na galeria.
  ///
  /// [salvarNaGaleria] por padrão é true (comportamento antigo). Passe false quando
  /// dados como a espécie só ficam conhecidos DEPOIS da captura (ex.: árvore em modo
  /// BIO) — nesse caso a galeria é uma cópia independente do arquivo do app, então
  /// mandar pra galeria antes de renomear/atualizar o EXIF deixaria uma cópia
  /// desatualizada lá pra sempre. Chame [salvarNaGaleria] manualmente depois que o
  /// nome/EXIF final estiverem prontos.
  static Future<String> carimbarMetadadosESalvar({
    required String pathOriginal,
    required String informacoesHierarquia,
    required String nomeArquivoFinal,
    bool salvarNaGaleria = true,
  }) async {
    try {
      // 1. Grava no EXIF (Metadado oculto) - RAM ZERO
      final exif = await Exif.fromPath(pathOriginal);
      await exif.writeAttributes({
        'UserComment': _semAcentos(informacoesHierarquia),
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

      // 3. Salva na Galeria (cópia independente — ver aviso acima)
      if (salvarNaGaleria) {
        await Gal.putImage(arquivoRenomeado.path);
      }

      debugPrint("Foto processada via EXIF e salva: ${arquivoRenomeado.path}");
      return arquivoRenomeado.path;
    } catch (e) {
      debugPrint("Erro no processamento de imagem: $e");
      // Se falhar a renomeação ou EXIF, tenta salvar o original para não perder o dado de campo
      if (salvarNaGaleria) {
        try {
          await Gal.putImage(pathOriginal);
        } catch (_) {}
      }
      return pathOriginal;
    }
  }

  /// Copia a foto (já com nome/EXIF definitivos) pra galeria pública do celular.
  /// Best-effort: falha silenciosamente se o arquivo não existir mais.
  static Future<void> salvarNaGaleria(String path) async {
    try {
      await Gal.putImage(path);
    } catch (e) {
      debugPrint("Erro ao salvar $path na galeria: $e");
    }
  }

  /// Atualiza a descrição EXIF de uma foto já salva (sem renomear), incluindo
  /// dados conhecidos só depois da captura (ex.: espécie identificada).
  /// Best-effort: falha silenciosamente se o arquivo não existir mais ou o EXIF não puder ser gravado.
  static Future<void> atualizarDescricaoExif({
    required String path,
    required String descricao,
  }) async {
    try {
      final exif = await Exif.fromPath(path);
      await exif.writeAttributes({'UserComment': _semAcentos(descricao)});
    } catch (e) {
      debugPrint("Erro ao atualizar EXIF de $path: $e");
    }
  }
}
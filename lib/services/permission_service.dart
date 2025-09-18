// lib/services/permission_service.dart (VERSÃO CORRIGIDA E COMPLETA)

import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';

class PermissionService {
  
  /// Solicita a permissão de armazenamento/fotos de forma robusta para Android e outras plataformas.
  Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      final deviceInfo = await DeviceInfoPlugin().androidInfo;
      
      // Para Android 13 (SDK 33) e superior, precisamos de permissões de mídia granulares.
      if (deviceInfo.version.sdkInt >= 33) {
        var photoStatus = await Permission.photos.status;
        if (!photoStatus.isGranted) {
          photoStatus = await Permission.photos.request();
        }
        return photoStatus.isGranted;
      } 
      // Para Android 11 e 12 (SDK 30-32), a permissão de gerenciar todos os arquivos é a mais garantida.
      else if (deviceInfo.version.sdkInt >= 30) {
        var storageStatus = await Permission.manageExternalStorage.status;
        if (!storageStatus.isGranted) {
          storageStatus = await Permission.manageExternalStorage.request();
        }
        return storageStatus.isGranted;
      } 
      // Para versões mais antigas do Android, a permissão de storage simples é suficiente.
      else {
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
        return status.isGranted;
      }
    } else {
      // Para iOS, a permissão de 'photos' é a correta.
      var status = await Permission.photos.request();
      return status.isGranted;
    }
  }
}
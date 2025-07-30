// lib/services/permission_service.dart (VERSÃO CORRIGIDA E COMPLETA)

import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';

class PermissionService {
  
  /// Solicita a permissão de armazenamento de forma robusta para Android e outras plataformas.
  Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      // Para Android moderno, precisamos da permissão para gerenciar todos os arquivos.
      final deviceInfo = await DeviceInfoPlugin().androidInfo;
      
      // A partir do Android 11 (SDK 30), a permissão MANAGE_EXTERNAL_STORAGE é necessária.
      if (deviceInfo.version.sdkInt >= 30) {
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
        }
        return status.isGranted;
      } else {
        // Para versões mais antigas do Android, a permissão de storage é suficiente.
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
        return status.isGranted;
      }
    } else {
      // Para iOS e outras plataformas, a permissão de storage geralmente é suficiente.
      var status = await Permission.storage.request();
      return status.isGranted;
    }
  }
}
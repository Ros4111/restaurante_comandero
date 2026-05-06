// lib/services/kiosk_android.dart
// Canal nativo: administrador de dispositivo + lock task (kiosco). Solo Android.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class KioskAndroid {
  static const _channel =
      MethodChannel('com.restaurante.restaurante_tpv/kiosk');

  static bool get disponible => !kIsWeb && Platform.isAndroid;

  static Future<bool> administradorActivo() async {
    if (!disponible) return false;
    return await _channel.invokeMethod<bool>('isDeviceAdminActive') ?? false;
  }

  static Future<void> solicitarAdministrador() async {
    if (!disponible) return;
    await _channel.invokeMethod<void>('requestDeviceAdmin');
  }

  static Future<void> quitarAdministrador() async {
    if (!disponible) return;
    await _channel.invokeMethod<void>('removeDeviceAdmin');
  }

  static Future<bool> lockTaskPermitido() async {
    if (!disponible) return false;
    return await _channel.invokeMethod<bool>('isLockTaskPermitted') ?? false;
  }

  static Future<bool> iniciarBloqueoApp() async {
    if (!disponible) return false;
    return await _channel.invokeMethod<bool>('startLockTask') ?? false;
  }

  static Future<bool> detenerBloqueoApp() async {
    if (!disponible) return false;
    return await _channel.invokeMethod<bool>('stopLockTask') ?? false;
  }

  static Future<bool> enModoBloqueo() async {
    if (!disponible) return false;
    return await _channel.invokeMethod<bool>('isInLockTaskMode') ?? false;
  }

  /// Oculta barras del sistema (inmersivo), orientación retrato. Solo Android.
  static Future<void> aplicarUiModoKiosco() async {
    if (!disponible) return;
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// Vuelve a mostrar barras del sistema tras salir del kiosco. Solo Android.
  static Future<void> restaurarUiTrasKiosco() async {
    if (!disponible) return;
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }
}

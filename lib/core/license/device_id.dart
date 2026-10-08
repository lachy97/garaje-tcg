import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/ids.dart';

/// Identificador estable del teléfono para las licencias.
///
/// En Android se usa ANDROID_ID (no cambia al reinstalar la app; solo con un
/// restablecimiento de fábrica). En otras plataformas, o si falla, un id
/// aleatorio guardado en la app.
class DeviceId {
  const DeviceId._();

  static const _channel = MethodChannel('garage_tcg/device');
  static const _fallbackKey = 'device.fallbackId';

  static Future<String> raw(SharedPreferences prefs) async {
    if (Platform.isAndroid) {
      try {
        final id = await _channel.invokeMethod<String>('androidId');
        if (id != null && id.isNotEmpty) return 'android:$id';
      } on Exception {
        // sigue con el id de respaldo
      }
    }
    var fallback = prefs.getString(_fallbackKey);
    if (fallback == null) {
      fallback = newId();
      await prefs.setString(_fallbackKey, fallback);
    }
    return 'local:$fallback';
  }
}

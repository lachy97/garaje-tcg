import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_devices.dart';
import 'admin_vault.dart';
import 'device_id.dart';
import 'license_codec.dart';
import 'license_config.dart';

enum LicenseState {
  /// La app aún no tiene clave pública: no se pide licencia (modo desarrollo).
  notConfigured,
  valid,

  /// Válida, pero vence en [LicenseService.warnDays] días o menos.
  expiringSoon,
  missing,
  expired,

  /// La licencia guardada es de otro teléfono.
  wrongDevice,

  /// La licencia guardada no es auténtica (firma incorrecta, otra clave…).
  invalid,

  /// La fecha del teléfono está atrasada respecto a la última vez que se usó.
  clockBack,
}

class LicenseStatus {
  const LicenseStatus({
    required this.state,
    required this.deviceCode,
    this.data,
    this.message,
  });

  final LicenseState state;
  final String deviceCode;
  final LicenseData? data;
  final String? message;

  bool get allowsUse =>
      state == LicenseState.notConfigured ||
      state == LicenseState.valid ||
      state == LicenseState.expiringSoon;

  int? get daysLeft => data?.daysLeft(DateTime.now());
}

/// Licencias offline: guarda la licencia, la comprueba y protege contra
/// atrasar la fecha del teléfono.
class LicenseService {
  LicenseService(this._prefs);

  final SharedPreferences _prefs;

  static const warnDays = 7;
  static const _keyLicense = 'license.key';
  static const _keyLastSeen = 'license.lastSeenMs';
  static const _keyLastWarn = 'license.lastWarnDay';
  static const _keyAdminSeed = 'admin.seed';
  static const _keyAdminUnlocked = 'admin.unlocked';
  static const _keyAdminSealed = 'admin.sealedSeed';
  static const _keyPinFails = 'admin.pinFails';
  static const _keyPinLockedUntil = 'admin.pinLockedUntil';
  static const maxPinFails = 5;
  static const pinLockMinutes = 15;

  /// Margen para cambios de hora/zona horaria antes de considerar que se
  /// atrasó la fecha.
  static const _clockTolerance = Duration(hours: 36);

  static Future<LicenseService> create() async =>
      LicenseService(await SharedPreferences.getInstance());

  /// Clave pública compilada en la app (null = sin configurar).
  static Uint8List? get appPublicKey => LicenseCodec.decodePublicKey(kLicensePublicKey);

  Future<Uint8List> fingerprint() async =>
      LicenseCodec.deviceFingerprint(await DeviceId.raw(_prefs));

  Future<String> deviceCode() async => LicenseCodec.deviceCode(await fingerprint());

  String? get storedLicense => _prefs.getString(_keyLicense);

  Future<LicenseStatus> check({DateTime? now}) async {
    now ??= DateTime.now();
    final fp = await fingerprint();
    final code = LicenseCodec.deviceCode(fp);
    final key = appPublicKey;
    final text = storedLicense;

    if (key == null) {
      // Sin clave pública: se muestra la licencia guardada (si la hay) solo informativa.
      LicenseData? data;
      if (text != null) {
        try {
          data = LicenseCodec.decode(text).$1;
        } on LicenseFormatException {
          data = null;
        }
      }
      return LicenseStatus(state: LicenseState.notConfigured, deviceCode: code, data: data);
    }

    // Reloj: la fecha no puede ir hacia atrás respecto a la última vez.
    final lastSeen = _prefs.getInt(_keyLastSeen) ?? 0;
    if (now.millisecondsSinceEpoch < lastSeen - _clockTolerance.inMilliseconds) {
      return LicenseStatus(
        state: LicenseState.clockBack,
        deviceCode: code,
        message: 'La fecha del teléfono está atrasada. Pon la fecha y hora correctas.',
      );
    }
    if (now.millisecondsSinceEpoch > lastSeen) {
      await _prefs.setInt(_keyLastSeen, now.millisecondsSinceEpoch);
    }

    if (text == null) return LicenseStatus(state: LicenseState.missing, deviceCode: code);

    final LicenseData data;
    try {
      data = await LicenseCodec.verify(text, key);
    } on LicenseFormatException catch (e) {
      return LicenseStatus(state: LicenseState.invalid, deviceCode: code, message: e.message);
    }
    if (!data.isForDevice(fp)) {
      return LicenseStatus(state: LicenseState.wrongDevice, deviceCode: code, data: data);
    }
    final left = data.daysLeft(now);
    if (left < 0) return LicenseStatus(state: LicenseState.expired, deviceCode: code, data: data);
    return LicenseStatus(
      state: left <= warnDays ? LicenseState.expiringSoon : LicenseState.valid,
      deviceCode: code,
      data: data,
    );
  }

  /// Comprueba y guarda una licencia nueva (o renovación). Lanza
  /// [LicenseFormatException] con el motivo si no sirve.
  Future<LicenseData> activate(String text) async {
    final key = appPublicKey;
    final LicenseData data;
    if (key == null) {
      // Modo desarrollo: solo se comprueba el formato; se validará al configurar la clave.
      data = LicenseCodec.decode(text).$1;
    } else {
      data = await LicenseCodec.verify(text, key);
    }
    if (!data.isForDevice(await fingerprint())) {
      throw LicenseFormatException(
          'Esta licencia es para otro teléfono (código ${data.deviceCode}).');
    }
    if (data.daysLeft(DateTime.now()) < 0) {
      throw const LicenseFormatException('Esta licencia ya está vencida.');
    }
    await _prefs.setString(_keyLicense, text.replaceAll(RegExp(r'\s'), ''));
    final now = DateTime.now();
    if (data.issuedDay >= LicenseCodec.dayOf(now) - 1) {
      // Licencia recién emitida por el administrador: también sirve para
      // desbloquear un teléfono al que se le adelantó la fecha por error.
      await _prefs.setInt(_keyLastSeen, now.millisecondsSinceEpoch);
    } else {
      // La fecha nunca podrá ser anterior a la emisión de la licencia.
      final issuedMs = data.issued.millisecondsSinceEpoch;
      if ((_prefs.getInt(_keyLastSeen) ?? 0) < issuedMs) {
        await _prefs.setInt(_keyLastSeen, issuedMs);
      }
    }
    return data;
  }

  /// true una vez al día cuando la licencia está por vencer.
  Future<bool> shouldWarnToday() async {
    final today = LicenseCodec.dayOf(DateTime.now());
    if (_prefs.getInt(_keyLastWarn) == today) return false;
    await _prefs.setInt(_keyLastWarn, today);
    return true;
  }

  // ───────────────────── Administrador ─────────────────────

  /// Este teléfono es el del administrador (ver admin_devices.dart). Solo en
  /// él se muestra y se puede abrir el Modo administrador.
  Future<bool> isAdminDevice() async => isAdminDeviceCode(await deviceCode());

  bool get adminUnlocked => _prefs.getBool(_keyAdminUnlocked) ?? false;

  Future<void> setAdminUnlocked(bool v) => _prefs.setBool(_keyAdminUnlocked, v);

  /// Clave privada guardada SIN cifrar por una versión anterior (antes del
  /// PIN). Se migra a cifrada en cuanto se abre el Modo administrador.
  Uint8List? get legacyAdminSeed {
    final s = _prefs.getString(_keyAdminSeed);
    return s == null ? null : LicenseCodec.decodePrivateKey(s);
  }

  bool get hasAdminKey =>
      _prefs.getString(_keyAdminSealed) != null || legacyAdminSeed != null;

  /// Guarda la clave privada cifrada con el PIN (y borra cualquier copia sin cifrar).
  Future<void> saveAdminSeed(Uint8List seed, String pin) async {
    await _prefs.setString(_keyAdminSealed, await AdminVault.seal(seed, pin));
    await _prefs.remove(_keyAdminSeed);
    await _prefs.remove(_keyPinFails);
    await _prefs.remove(_keyPinLockedUntil);
  }

  /// Descifra la clave con el PIN. Lanza [AdminPinException] si el PIN es
  /// incorrecto o hay demasiados intentos fallidos.
  Future<Uint8List> openAdminSeed(String pin) async {
    final lockedUntil = _prefs.getInt(_keyPinLockedUntil) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < lockedUntil) {
      final min = ((lockedUntil - now) / 60000).ceil();
      throw AdminPinException('Demasiados intentos. Espera $min min.');
    }
    final sealed = _prefs.getString(_keyAdminSealed);
    final seed = sealed == null ? null : await AdminVault.open(sealed, pin);
    if (seed == null) {
      final fails = (_prefs.getInt(_keyPinFails) ?? 0) + 1;
      if (fails >= maxPinFails) {
        await _prefs.setInt(_keyPinLockedUntil, now + pinLockMinutes * 60000);
        await _prefs.setInt(_keyPinFails, 0);
        throw AdminPinException(
            'PIN incorrecto. Bloqueado $pinLockMinutes min por demasiados intentos.');
      }
      await _prefs.setInt(_keyPinFails, fails);
      throw AdminPinException('PIN incorrecto (${maxPinFails - fails} intento(s) más).');
    }
    await _prefs.remove(_keyPinFails);
    return seed;
  }

  Future<void> deleteAdminSeed() async {
    await _prefs.remove(_keyAdminSeed);
    await _prefs.remove(_keyAdminSealed);
  }
}

class AdminPinException implements Exception {
  const AdminPinException(this.message);

  final String message;

  @override
  String toString() => message;
}

final licenseServiceProvider = FutureProvider<LicenseService>((ref) => LicenseService.create());

/// Estado de la licencia de este teléfono. Se vuelve a comprobar al volver a
/// la app y al introducir una licencia.
class LicenseController extends AsyncNotifier<LicenseStatus> {
  @override
  Future<LicenseStatus> build() async {
    final service = await ref.watch(licenseServiceProvider.future);
    return service.check();
  }

  Future<void> refresh() async {
    final service = await ref.read(licenseServiceProvider.future);
    state = AsyncData(await service.check());
  }

  /// Devuelve la licencia activada o lanza [LicenseFormatException].
  Future<LicenseData> activate(String text) async {
    final service = await ref.read(licenseServiceProvider.future);
    final data = await service.activate(text);
    await refresh();
    return data;
  }
}

final licenseProvider =
    AsyncNotifierProvider<LicenseController, LicenseStatus>(LicenseController.new);

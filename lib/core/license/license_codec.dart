import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

/// Formato de las licencias offline (Dart puro, testeable).
///
/// Licencia = "GTCG1." + base64url( datos + firma Ed25519 de 64 bytes )
///
/// datos:
///   [0]      versión (1)
///   [1..10]  huella del dispositivo (10 bytes, ver [deviceFingerprint])
///   [11..12] día de emisión     (uint16, días desde 2024-01-01)
///   [13..14] día de vencimiento (uint16, válida hasta ese día incluido)
///   [15]     largo del nombre del cliente (0-40 bytes UTF-8)
///   [16..]   nombre del cliente
///
/// Solo quien tiene la clave PRIVADA puede firmar licencias. La app lleva la
/// clave PÚBLICA y con ella comprueba que la licencia es auténtica, que es
/// para este teléfono y que no ha vencido. No necesita internet.
class LicenseCodec {
  const LicenseCodec._();

  static const prefix = 'GTCG1.';
  static const privatePrefix = 'GTCG-PRIV-';
  static const version = 1;
  static const fingerprintLength = 10;
  static const maxHolderBytes = 40;
  static final epoch = DateTime.utc(2024, 1, 1);

  static final _ed = Ed25519();

  // ───────────────────── Dispositivo ─────────────────────

  /// Huella de 10 bytes del identificador del teléfono (no se guarda el id real).
  static Uint8List deviceFingerprint(String rawDeviceId) {
    final digest = hash.sha256.convert(utf8.encode('garage-tcg-device:$rawDeviceId'));
    return Uint8List.fromList(digest.bytes.sublist(0, fingerprintLength));
  }

  /// Código que ve el usuario: 16 caracteres en grupos de 4 ("7K3M-…").
  static String deviceCode(Uint8List fingerprint) {
    final s = Base32.encode(fingerprint);
    return [for (var i = 0; i < s.length; i += 4) s.substring(i, i + 4)].join('-');
  }

  /// Convierte un código escrito por el usuario a huella. null si no es válido.
  static Uint8List? parseDeviceCode(String code) {
    final bytes = Base32.decode(code);
    return bytes != null && bytes.length == fingerprintLength ? bytes : null;
  }

  // ───────────────────── Fechas ─────────────────────

  static int dayOf(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).difference(epoch).inDays;

  static DateTime dateOfDay(int day) => epoch.add(Duration(days: day));

  /// Fecha de vencimiento para [months] meses desde [from] (mismo día del mes;
  /// si no existe, el último día de ese mes).
  static DateTime addMonths(DateTime from, int months) {
    final target = DateTime.utc(from.year, from.month + months, 1);
    final lastDay = DateTime.utc(target.year, target.month + 1, 0).day;
    return DateTime.utc(target.year, target.month, from.day > lastDay ? lastDay : from.day);
  }

  // ───────────────────── Codificar / decodificar ─────────────────────

  static Uint8List payload(LicenseData d) {
    var name = utf8.encode(d.holder.trim());
    if (name.length > maxHolderBytes) {
      // Recorta sin partir un carácter UTF-8 por la mitad.
      var cut = maxHolderBytes;
      while (cut > 0 && (name[cut] & 0xC0) == 0x80) {
        cut--;
      }
      name = name.sublist(0, cut);
    }
    final b = BytesBuilder()
      ..addByte(version)
      ..add(d.fingerprint)
      ..add(_u16(d.issuedDay))
      ..add(_u16(d.expiresDay))
      ..addByte(name.length)
      ..add(name);
    return b.toBytes();
  }

  static List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];

  /// Lee la licencia SIN comprobar la firma. Lanza [LicenseFormatException].
  static (LicenseData, Uint8List payload, Uint8List signature) decode(String text) {
    final clean = text.replaceAll(RegExp(r'\s'), '');
    if (!clean.startsWith(prefix)) {
      throw const LicenseFormatException('No es una licencia de Garage TCG.');
    }
    final Uint8List raw;
    try {
      raw = base64Url.decode(base64Url.normalize(clean.substring(prefix.length)));
    } on FormatException {
      throw const LicenseFormatException('La licencia está incompleta o mal copiada.');
    }
    if (raw.length < 16 + 64 || raw[0] != version) {
      throw const LicenseFormatException('La licencia está incompleta o mal copiada.');
    }
    final nameLen = raw[15];
    final payloadLen = 16 + nameLen;
    if (raw.length != payloadLen + 64) {
      throw const LicenseFormatException('La licencia está incompleta o mal copiada.');
    }
    final p = Uint8List.sublistView(raw, 0, payloadLen);
    final data = LicenseData(
      fingerprint: Uint8List.fromList(raw.sublist(1, 11)),
      issuedDay: (raw[11] << 8) | raw[12],
      expiresDay: (raw[13] << 8) | raw[14],
      holder: utf8.decode(raw.sublist(16, payloadLen), allowMalformed: true),
    );
    return (data, Uint8List.fromList(p), Uint8List.fromList(raw.sublist(payloadLen)));
  }

  /// Comprueba firma y formato. Lanza [LicenseFormatException] si no es válida.
  static Future<LicenseData> verify(String text, Uint8List publicKey) async {
    final (data, p, sig) = decode(text);
    final ok = await _ed.verify(
      p,
      signature: Signature(sig,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519)),
    );
    if (!ok) {
      throw const LicenseFormatException(
          'La licencia no es auténtica (firma incorrecta).');
    }
    return data;
  }

  // ───────────────────── Administrador ─────────────────────

  static Future<SimpleKeyPair> newKeyPair() => _ed.newKeyPair();

  static Future<SimpleKeyPair> keyPairFromSeed(Uint8List seed) =>
      _ed.newKeyPairFromSeed(seed);

  static Future<Uint8List> publicKeyOf(SimpleKeyPair kp) async =>
      Uint8List.fromList((await kp.extractPublicKey()).bytes);

  static Future<Uint8List> seedOf(SimpleKeyPair kp) async =>
      Uint8List.fromList(await kp.extractPrivateKeyBytes());

  /// Firma una licencia con la clave privada del administrador.
  static Future<String> sign(LicenseData d, SimpleKeyPair kp) async {
    final p = payload(d);
    final sig = await _ed.sign(p, keyPair: kp);
    return prefix + base64Url.encode([...p, ...sig.bytes]).replaceAll('=', '');
  }

  static String encodePrivateKey(Uint8List seed) =>
      privatePrefix + base64Url.encode(seed).replaceAll('=', '');

  static Uint8List? decodePrivateKey(String text) {
    final clean = text.replaceAll(RegExp(r'\s'), '');
    if (!clean.startsWith(privatePrefix)) return null;
    try {
      final b = base64Url.decode(base64Url.normalize(clean.substring(privatePrefix.length)));
      return b.length == 32 ? b : null;
    } on FormatException {
      return null;
    }
  }

  static String encodePublicKey(Uint8List key) => base64Url.encode(key).replaceAll('=', '');

  static Uint8List? decodePublicKey(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return null;
    try {
      final b = base64Url.decode(base64Url.normalize(clean));
      return b.length == 32 ? b : null;
    } on FormatException {
      return null;
    }
  }
}

class LicenseData {
  const LicenseData({
    required this.fingerprint,
    required this.issuedDay,
    required this.expiresDay,
    required this.holder,
  });

  final Uint8List fingerprint;
  final int issuedDay;
  final int expiresDay;
  final String holder;

  DateTime get issued => LicenseCodec.dateOfDay(issuedDay);
  DateTime get expires => LicenseCodec.dateOfDay(expiresDay);
  String get deviceCode => LicenseCodec.deviceCode(fingerprint);

  bool isForDevice(Uint8List fp) {
    if (fp.length != fingerprint.length) return false;
    for (var i = 0; i < fp.length; i++) {
      if (fp[i] != fingerprint[i]) return false;
    }
    return true;
  }

  /// Días que quedan (0 = vence hoy; negativo = vencida).
  int daysLeft(DateTime now) => expiresDay - LicenseCodec.dayOf(now);
}

class LicenseFormatException implements Exception {
  const LicenseFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Base32 de Crockford (sin I, L, O, U): fácil de dictar y copiar.
class Base32 {
  const Base32._();

  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static String encode(List<int> bytes) {
    final out = StringBuffer();
    var buffer = 0, bits = 0;
    for (final b in bytes) {
      buffer = ((buffer << 8) | b) & 0xFFFF;
      bits += 8;
      while (bits >= 5) {
        out.write(_alphabet[(buffer >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
    return out.toString();
  }

  static Uint8List? decode(String text) {
    final clean = text
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    final out = <int>[];
    var buffer = 0, bits = 0;
    for (final ch in clean.split('')) {
      final v = _alphabet.indexOf(ch);
      if (v < 0) return null;
      buffer = ((buffer << 5) | v) & 0xFFFF;
      bits += 5;
      if (bits >= 8) {
        out.add((buffer >> (bits - 8)) & 0xFF);
        bits -= 8;
      }
    }
    return Uint8List.fromList(out);
  }
}

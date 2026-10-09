import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Guarda la clave privada del administrador CIFRADA con un PIN.
///
/// El PIN no se guarda en ningún sitio: de él se deriva una clave
/// (PBKDF2-HMAC-SHA256, [iterations] vueltas, sal aleatoria) que cifra la clave
/// privada con AES-256-GCM. Sin el PIN correcto no se puede descifrar, así que
/// aunque alguien abra el Modo administrador en tu teléfono no puede firmar
/// licencias.
class AdminVault {
  const AdminVault._();

  static const iterations = 30000;
  static const minPinLength = 4;
  static const maxPinLength = 8;

  static final _aes = AesGcm.with256bits();
  static final _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);

  static bool isValidPin(String pin) =>
      pin.length >= minPinLength && pin.length <= maxPinLength && RegExp(r'^\d+$').hasMatch(pin);

  static Uint8List _random(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  static Future<SecretKey> _keyFor(String pin, List<int> salt) =>
      _kdf.deriveKeyFromPassword(password: pin, nonce: salt);

  /// Cifra la clave privada (32 bytes) con el PIN. Devuelve un texto para guardar.
  static Future<String> seal(Uint8List seed, String pin) async {
    final salt = _random(16);
    final box = await _aes.encrypt(seed, secretKey: await _keyFor(pin, salt));
    return jsonEncode({
      'v': 1,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ct': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  /// Descifra con el PIN. null si el PIN es incorrecto o el texto está dañado.
  static Future<Uint8List?> open(String sealed, String pin) async {
    try {
      final j = jsonDecode(sealed) as Map<String, dynamic>;
      final key = await _keyFor(pin, base64Decode(j['salt'] as String));
      final seed = await _aes.decrypt(
        SecretBox(
          base64Decode(j['ct'] as String),
          nonce: base64Decode(j['nonce'] as String),
          mac: Mac(base64Decode(j['mac'] as String)),
        ),
        secretKey: key,
      );
      return seed.length == 32 ? Uint8List.fromList(seed) : null;
    } on SecretBoxAuthenticationError {
      return null;
    } catch (_) {
      // Texto dañado (JSON, base64…).
      return null;
    }
  }
}

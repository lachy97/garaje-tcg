import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/license/license_codec.dart';

/// Vector generado con el generador de PC (tools/license_core.js) y comprobado
/// contra la implementación Ed25519 de Node.js: garantiza que la app acepta las
/// licencias del generador y que ambos producen exactamente lo mismo.
const _seed = 'GTCG-PRIV-AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA';
const _public = 'ebVWLo_mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ';
const _rawId = 'test-android-id-123';
const _code = 'JF9A-26VJ-YG4X-NYWT';
const _license =
    'GTCG1.AZPSoRty9Ana-5oD8wRPEENsdWIgUGXDscOzbiBUQ0c3EJ0EGB4dnRNjbhXq286svpArZZVvlAgJkh6u'
    'JMVhu_3grafDfzY3F3MON4N39Xj8EQHYdu9A2I5bbPolmsMA';

void main() {
  final pub = LicenseCodec.decodePublicKey(_public)!;

  test('Código de dispositivo', () {
    final fp = LicenseCodec.deviceFingerprint(_rawId);
    expect(LicenseCodec.deviceCode(fp), _code);
    expect(LicenseCodec.parseDeviceCode('jf9a 26vj yg4x nywt'), fp);
    expect(LicenseCodec.parseDeviceCode('ABC'), isNull);
  });

  test('Verifica una licencia del generador de PC', () async {
    final d = await LicenseCodec.verify(_license, pub);
    expect(d.holder, 'Club Peñón TCG');
    expect(d.issued, DateTime.utc(2026, 10, 8));
    expect(d.expires, DateTime.utc(2027, 1, 8));
    expect(d.isForDevice(LicenseCodec.deviceFingerprint(_rawId)), isTrue);
    expect(d.isForDevice(LicenseCodec.deviceFingerprint('otro')), isFalse);
    expect(d.daysLeft(DateTime(2027, 1, 8, 23, 59)), 0);
    expect(d.daysLeft(DateTime(2027, 1, 9)), -1);
  });

  test('La app firma exactamente igual que el generador de PC', () async {
    final kp = await LicenseCodec.keyPairFromSeed(LicenseCodec.decodePrivateKey(_seed)!);
    expect(LicenseCodec.encodePublicKey(await LicenseCodec.publicKeyOf(kp)), _public);
    final text = await LicenseCodec.sign(
      LicenseData(
        fingerprint: LicenseCodec.deviceFingerprint(_rawId),
        issuedDay: LicenseCodec.dayOf(DateTime(2026, 10, 8)),
        expiresDay: LicenseCodec.dayOf(LicenseCodec.addMonths(DateTime(2026, 10, 8), 3)),
        holder: 'Club Peñón TCG',
      ),
      kp,
    );
    expect(text, _license);
  });

  test('Rechaza licencias alteradas o de otra clave', () async {
    final chars = _license.split('');
    final i = 30;
    chars[i] = chars[i] == 'A' ? 'B' : 'A';
    await expectLater(
        LicenseCodec.verify(chars.join(), pub), throwsA(isA<LicenseFormatException>()));

    final other = await LicenseCodec.newKeyPair();
    await expectLater(LicenseCodec.verify(_license, await LicenseCodec.publicKeyOf(other)),
        throwsA(isA<LicenseFormatException>()));

    expect(() => LicenseCodec.decode('hola'), throwsA(isA<LicenseFormatException>()));
    expect(() => LicenseCodec.decode('GTCG1.abc'), throwsA(isA<LicenseFormatException>()));
  });

  test('Nombre largo se recorta a 40 bytes sin romper caracteres', () async {
    final kp = await LicenseCodec.newKeyPair();
    final text = await LicenseCodec.sign(
      LicenseData(
        fingerprint: Uint8List(10),
        issuedDay: 0,
        expiresDay: 30,
        holder: 'ñ' * 30, // 60 bytes
      ),
      kp,
    );
    final d = await LicenseCodec.verify(text, await LicenseCodec.publicKeyOf(kp));
    expect(d.holder, 'ñ' * 20);
  });

  test('Sumar meses', () {
    expect(LicenseCodec.addMonths(DateTime(2026, 1, 31), 1), DateTime.utc(2026, 2, 28));
    expect(LicenseCodec.addMonths(DateTime(2026, 11, 30), 3), DateTime.utc(2027, 2, 28));
    expect(LicenseCodec.addMonths(DateTime(2026, 10, 8), 12), DateTime.utc(2027, 10, 8));
  });

  test('Clave privada: codificar y leer', () {
    final seed = Uint8List.fromList(List.generate(32, (i) => i + 1));
    expect(LicenseCodec.encodePrivateKey(seed), _seed);
    expect(LicenseCodec.decodePrivateKey(_seed), seed);
    expect(LicenseCodec.decodePrivateKey('GTCG-PRIV-xx'), isNull);
  });
}

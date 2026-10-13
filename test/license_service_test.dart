import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/license/license_codec.dart';
import 'package:garaje_tcg/core/license/license_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _seed = 'GTCG-PRIV-AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA';
const _deviceRaw = 'local:test-device';

Future<String> _license(DateTime issued, int months) async {
  final kp = await LicenseCodec.keyPairFromSeed(LicenseCodec.decodePrivateKey(_seed)!);
  return LicenseCodec.sign(
    LicenseData(
      fingerprint: LicenseCodec.deviceFingerprint(_deviceRaw),
      issuedDay: LicenseCodec.dayOf(issued),
      expiresDay: LicenseCodec.dayOf(LicenseCodec.addMonths(issued, months)),
      holder: 'Prueba',
    ),
    kp,
  );
}

Future<LicenseService> _service() async {
  SharedPreferences.setMockInitialValues({'device.fallbackId': 'test-device'});
  final prefs = await SharedPreferences.getInstance();
  final kp = await LicenseCodec.keyPairFromSeed(LicenseCodec.decodePrivateKey(_seed)!);
  return LicenseService(prefs, publicKey: await LicenseCodec.publicKeyOf(kp));
}

void main() {
  test('Activa una licencia válida y la comprueba', () async {
    final s = await _service();
    final day = DateTime(2026, 10, 1, 12);
    await s.activate(await _license(DateTime(2026, 10, 1), 3), now: day);
    final st = await s.check(now: day.add(const Duration(days: 10)));
    expect(st.state, LicenseState.valid);
  });

  test('Rechaza activar con la fecha anterior a la emisión', () async {
    final s = await _service();
    final text = await _license(DateTime(2026, 10, 10), 3);
    await expectLater(
      s.activate(text, now: DateTime(2026, 10, 1, 12)),
      throwsA(isA<LicenseFormatException>()),
    );
  });

  test('Volver a pegar la misma licencia no quita el bloqueo de reloj', () async {
    final s = await _service();
    final text = await _license(DateTime(2026, 10, 1), 1);
    await s.activate(text, now: DateTime(2026, 10, 1, 12));
    // Se usa la app hasta después del vencimiento…
    expect((await s.check(now: DateTime(2026, 11, 20, 12))).state, LicenseState.expired);
    // …y se atrasa la fecha para que vuelva a "valer".
    final back = DateTime(2026, 10, 2, 12);
    expect((await s.check(now: back)).state, LicenseState.clockBack);
    await expectLater(s.activate(text, now: back), throwsA(isA<LicenseFormatException>()));
    expect((await s.check(now: back)).state, LicenseState.clockBack);
  });

  test('Una licencia nueva y recién emitida sí desbloquea un reloj adelantado', () async {
    final s = await _service();
    await s.activate(await _license(DateTime(2026, 10, 1), 3), now: DateTime(2026, 10, 1, 12));
    // La fecha se adelantó por error a diciembre y luego se corrigió.
    await s.check(now: DateTime(2026, 12, 25, 12));
    final today = DateTime(2026, 10, 5, 12);
    expect((await s.check(now: today)).state, LicenseState.clockBack);
    await s.activate(await _license(DateTime(2026, 10, 5), 3), now: today);
    expect((await s.check(now: today)).state, LicenseState.valid);
  });

  test('lastSeen nunca retrocede al activar', () async {
    final s = await _service();
    await s.activate(await _license(DateTime(2026, 10, 1), 3), now: DateTime(2026, 10, 1, 12));
    await s.check(now: DateTime(2026, 10, 20, 12));
    // Renovación emitida antes de la última fecha vista: no baja lastSeen.
    await s.activate(await _license(DateTime(2026, 10, 2), 6), now: DateTime(2026, 10, 20, 13));
    expect((await s.check(now: DateTime(2026, 10, 3, 12))).state, LicenseState.clockBack);
  });

  test('Bloqueo progresivo del PIN', () {
    expect(LicenseService.pinLockMinutesFor(0), 15);
    expect(LicenseService.pinLockMinutesFor(1), 30);
    expect(LicenseService.pinLockMinutesFor(2), 60);
    expect(LicenseService.pinLockMinutesFor(3), 120);
    expect(LicenseService.pinLockMinutesFor(6), 960);
    expect(LicenseService.pinLockMinutesFor(7), 1440);
    expect(LicenseService.pinLockMinutesFor(20), 1440);
  });
}

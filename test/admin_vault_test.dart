import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/license/admin_vault.dart';

void main() {
  final seed = Uint8List.fromList(List.generate(32, (i) => i * 7 % 256));

  test('Con el PIN correcto se recupera la clave privada', () async {
    final sealed = await AdminVault.seal(seed, '2468');
    expect(sealed.contains('2468'), isFalse);
    expect(await AdminVault.open(sealed, '2468'), seed);
  });

  test('Con un PIN incorrecto o datos dañados no se recupera', () async {
    final sealed = await AdminVault.seal(seed, '2468');
    expect(await AdminVault.open(sealed, '2469'), isNull);
    expect(await AdminVault.open('basura', '2468'), isNull);
  });

  test('Formato del PIN', () {
    expect(AdminVault.isValidPin('1234'), isTrue);
    expect(AdminVault.isValidPin('12345678'), isTrue);
    expect(AdminVault.isValidPin('123'), isFalse);
    expect(AdminVault.isValidPin('123456789'), isFalse);
    expect(AdminVault.isValidPin('12a4'), isFalse);
  });
}

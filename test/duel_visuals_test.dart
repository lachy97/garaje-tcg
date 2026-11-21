import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/features/duel/domain/duel_visuals.dart';

void main() {
  test('dado: el giro de reposo deja la cara pedida de frente', () {
    for (var v = 1; v <= 6; v++) {
      final (ax, ay) = diceRestAngles(v);
      expect(diceFacing(ax, ay), v, reason: 'cara $v');
      // También con vueltas completas encima (la animación termina así).
      expect(diceFacing(ax + 6 * pi, ay - 8 * pi), v);
    }
    // De frente se ve una sola cara: la opuesta queda de espaldas.
    final (ax, ay) = diceRestAngles(3);
    expect(diceFaceZ(DiceFace.four, ax, ay), greaterThan(0.9));
  });

  test('barra de vida: verde a 8000, rojo intenso en 0, azul por encima', () {
    final green = lifeBarColor(8000);
    expect(green.g > green.r, isTrue);
    final zero = lifeBarColor(0);
    expect(zero.r > 0.6 && zero.g < 0.1, isTrue);
    final low = lifeBarColor(1500);
    expect(low.r > low.g, isTrue, reason: 'por debajo: rojo');
    // Más cerca de 0, más intenso (más oscuro y saturado).
    expect(HSLColor.fromColor(lifeBarColor(300)).lightness, lessThan(HSLColor.fromColor(lifeBarColor(2500)).lightness));
    final over = lifeBarColor(9000);
    final far = lifeBarColor(16000);
    expect(over.b > over.r && far.b > far.r, isTrue, reason: 'por encima: azul');
    expect(HSLColor.fromColor(far).saturation, greaterThanOrEqualTo(HSLColor.fromColor(over).saturation));
    expect(HSLColor.fromColor(far).lightness, lessThan(HSLColor.fromColor(over).lightness));
  });
}

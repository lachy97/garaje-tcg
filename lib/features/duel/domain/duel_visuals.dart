import 'dart:math';
import 'dart:ui' show Color, lerpDouble;

/// Color de la barra de vida (igual en todos los temas):
/// - 8000 → verde; cuanto más baja, más rojo, y cerca de 0 un rojo intenso.
/// - Por encima de 8000 → azul, más intenso cuanto más se aleja (16000 o más
///   = el azul más intenso).
Color lifeBarColor(int lp) {
  if (lp > 8000) {
    final t = ((lp - 8000) / 8000).clamp(0.0, 1.0);
    return Color.lerp(const Color(0xFF8FD3FF), const Color(0xFF0B3FFF), t)!;
  }
  final t = (lp / 8000).clamp(0.0, 1.0);
  // De 0 a 8000: rojo intenso → rojo → naranja → verde.
  const stops = [
    (0.0, Color(0xFFB00000)),
    (0.25, Color(0xFFFF3B30)),
    (0.55, Color(0xFFFF9F1A)),
    (1.0, Color(0xFF5BE15B)),
  ];
  for (var i = 1; i < stops.length; i++) {
    final (b, cb) = stops[i];
    final (a, ca) = stops[i - 1];
    if (t <= b) return Color.lerp(ca, cb, (t - a) / (b - a))!;
  }
  return stops.last.$2;
}

// ───────────── Dado en 3D ─────────────

/// Cara del dado y su giro respecto a la cara de delante (1): el 1 delante,
/// el 6 detrás, el 3 a la derecha, el 4 a la izquierda, el 2 arriba y el 5
/// abajo (las caras opuestas suman 7).
enum DiceFace {
  one(1, 0, 0),
  six(6, 0, pi),
  three(3, 0, -pi / 2),
  four(4, 0, pi / 2),
  two(2, -pi / 2, 0),
  five(5, pi / 2, 0);

  const DiceFace(this.value, this.rx, this.ry);

  final int value;

  /// Giro de la cara (sobre X y sobre Y) desde la posición de delante.
  final double rx;
  final double ry;
}

/// Giro del dado (sobre X y sobre Y) que deja [value] mirando de frente.
(double ax, double ay) diceRestAngles(int value) => switch (value) {
  1 => (0.0, 0.0),
  6 => (0.0, pi),
  3 => (0.0, pi / 2),
  4 => (0.0, -pi / 2),
  2 => (pi / 2, 0.0),
  5 => (-pi / 2, 0.0),
  _ => throw ArgumentError.value(value, 'value'),
};

List<double> _rotX(double a, List<double> v) => [v[0], v[1] * cos(a) - v[2] * sin(a), v[1] * sin(a) + v[2] * cos(a)];

List<double> _rotY(double a, List<double> v) => [v[0] * cos(a) + v[2] * sin(a), v[1], -v[0] * sin(a) + v[2] * cos(a)];

/// Hacia dónde mira la cara [f] con el dado girado (ax, ay): la z de su
/// normal (negativa = hacia quien mira; positiva = de espaldas).
double diceFaceZ(DiceFace f, double ax, double ay) {
  var n = const [0.0, 0.0, -1.0];
  n = _rotX(f.rx, n);
  n = _rotY(f.ry, n);
  n = _rotY(ay, n);
  n = _rotX(ax, n);
  return n[2];
}

/// La cara que se ve de frente con el dado girado (ax, ay).
int diceFacing(double ax, double ay) =>
    DiceFace.values.reduce((a, b) => diceFaceZ(a, ax, ay) <= diceFaceZ(b, ax, ay) ? a : b).value;

/// Interpola entre a y b (para las animaciones).
double lerp(double a, double b, double t) => lerpDouble(a, b, t)!;

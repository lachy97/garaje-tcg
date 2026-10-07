/// Escala de puntos de ranking según la posición final y el tamaño del Top Cut.
///
/// Regla acordada: escalonada +100 por cada nivel de Top Cut
/// (Top 4 para torneos de menos de 15 jugadores, con menos puntos).
/// Los jugadores que no entran al Top Cut reciben 0 puntos.
class PointsTier {
  const PointsTier(this.from, this.to, this.points)
      : assert(from >= 1 && to >= from && points >= 0);

  final int from;
  final int to;
  final int points;

  bool contains(int position) => position >= from && position <= to;
}

class PointsScale {
  const PointsScale(this.topCutSize, this.tiers);

  final int topCutSize;
  final List<PointsTier> tiers;

  int pointsFor(int position) {
    for (final t in tiers) {
      if (t.contains(position)) return t.points;
    }
    return 0;
  }

  /// Escala por defecto (se copia a la BD la primera vez; luego es editable).
  static const Map<int, List<PointsTier>> defaults = {
    4: [
      PointsTier(1, 1, 400),
      PointsTier(2, 2, 300),
      PointsTier(3, 3, 200),
      PointsTier(4, 4, 100),
    ],
    8: [
      PointsTier(1, 1, 500),
      PointsTier(2, 2, 400),
      PointsTier(3, 3, 300),
      PointsTier(4, 4, 200),
      PointsTier(5, 8, 100),
    ],
    16: [
      PointsTier(1, 1, 600),
      PointsTier(2, 2, 500),
      PointsTier(3, 3, 400),
      PointsTier(4, 4, 300),
      PointsTier(5, 8, 200),
      PointsTier(9, 16, 100),
    ],
    32: [
      PointsTier(1, 1, 700),
      PointsTier(2, 2, 600),
      PointsTier(3, 3, 500),
      PointsTier(4, 4, 400),
      PointsTier(5, 8, 300),
      PointsTier(9, 16, 200),
      PointsTier(17, 32, 100),
    ],
  };

  factory PointsScale.defaultFor(int topCutSize) =>
      PointsScale(topCutSize, defaults[topCutSize] ?? const []);
}

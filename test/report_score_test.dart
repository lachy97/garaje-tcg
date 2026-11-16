import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/play/play.dart';

void main() {
  test('el reporte se lee desde quien reportó: ganó / perdió / empate', () {
    // Marcador guardado desde el jugador 1 de la mesa.
    const twoZero = ReportScore(2, 0, 0);
    expect(twoZero.said('Pedro', asP1: true), 'Pedro ganó 2-0');
    expect(twoZero.said('Pedro', asP1: false), 'Pedro perdió 0-2');
    const twoOne = ReportScore(1, 0, 2);
    expect(twoOne.said('Ana', asP1: false), 'Ana ganó 2-1');
    expect(twoOne.said('Ana', asP1: true), 'Ana perdió 1-2');
    expect(const ReportScore(1, 1, 1).said('Leo', asP1: true), 'Leo: empate 1-1-1');
    expect(const ReportScore(2, 1, 0).said('Leo', asP1: false), 'Leo perdió 0-1-2');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/features/duel/domain/duel.dart';

void main() {
  test('teclado: autocompleta con 00 hasta 4 cifras', () {
    expect(typedAmount(''), isNull);
    expect(typedAmount('5'), 500);
    expect(typedAmount('18'), 1800);
    expect(typedAmount('99'), 9900);
    expect(typedAmount('150'), 150);
    expect(typedAmount('050'), 50);
    expect(typedAmount('1800'), 1800);
    expect(typedAmount('12000'), 12000);
    expect(typedPreview('18'), ('18', '00'));
    expect(typedPreview('180'), ('180', ''));
  });

  test('LP: daño, curación, mitad, no baja de 0, deshacer y rehacer', () {
    final m = DuelMatch(names: ['Yo', 'Rival']);
    m.damage(1, 1800);
    m.damage(1, -500);
    expect(m.lp, [8000, 6700]);
    m.halve(1);
    expect(m.lp[1], 3350);
    m.halve(0);
    m.halve(0);
    m.halve(0);
    m.halve(0);
    m.halve(0);
    m.halve(0);
    expect(m.lp[0], 125, reason: '8000 → … → 250 → 125');
    m.halve(0);
    expect(m.lp[0], 63, reason: 'impar: redondea hacia arriba');
    m.damage(1, 9999);
    expect(m.lp[1], 0);
    expect(m.loserAtZero, 1);
    m.undo();
    expect(m.lp[1], 3350);
    expect(m.log.last.text, '½');
    m.redo();
    expect(m.lp[1], 0);
    expect(m.log.last.to, 0);
    m.undo();
    m.damage(1, 100); // rehacer se pierde con un cambio nuevo
    expect(m.canRedo, isFalse);
  });

  test('reloj de ajedrez: solo corre el del que juega; tiempos por duelo', () {
    final t0 = DateTime(2026, 11, 16, 15);
    final m = DuelMatch(names: ['Yo', 'Rival']);
    m.startClock(0, now: t0);
    expect(m.turn, 1);
    m.passTurn(now: t0.add(const Duration(minutes: 3)));
    m.passTurn(now: t0.add(const Duration(minutes: 5)));
    final now = t0.add(const Duration(minutes: 6));
    expect(m.elapsed(0, now), const Duration(minutes: 4));
    expect(m.elapsed(1, now), const Duration(minutes: 2));
    expect(m.turn, 3);
    m.pauseClock(now: now);
    expect(m.elapsed(0, now.add(const Duration(hours: 1))), const Duration(minutes: 4), reason: 'en pausa no corre');

    m.endGame(0, now: now);
    expect(m.gameClockMs.single, [240000, 120000]);
    m.nextGame();
    expect(m.lp, [kStartLp, kStartLp]);
    expect(m.turn, 0);
    m.startClock(1, now: now);
    m.endGame(1, now: now.add(const Duration(minutes: 10)));
    expect(m.gameClockMs.last, [0, 600000]);
    expect(m.elapsed(1, now), const Duration(minutes: 12));
  });

  test('partida al mejor de 3 y marcador para reportar', () {
    final m = DuelMatch(names: ['Yo', 'Rival'], iAmP1: false);
    m.endGame(0);
    m.nextGame();
    m.endGame(1);
    expect(m.matchOver, isFalse);
    m.nextGame();
    m.endGame(0);
    expect(m.matchOver, isTrue);
    expect(m.score, (2, 0, 1));
    expect(m.reportScore(), (1, 0, 2), reason: 'yo no soy el jugador 1: se da la vuelta');

    final t = DuelMatch(names: ['A', 'B'], topCut: true)
      ..endGame(-1)
      ..nextGame()
      ..endGame(0)
      ..nextGame()
      ..endGame(1);
    expect(t.reportScore(), isNull, reason: 'en el Top no hay empates');
  });

  test('se guarda y se recupera igual (JSON)', () {
    final t0 = DateTime(2026, 11, 16, 15);
    final m = DuelMatch(names: ['Yo', 'Rival'], tournamentId: 't', matchId: 'm');
    m.startClock(0, now: t0);
    m.damage(1, 2000, now: t0);
    m.note('Moneda: cara', kind: 'coin');
    final c = m.copy();
    expect(c.lp, [8000, 6000]);
    expect(c.active, 0);
    expect(c.runningSince, t0);
    expect(c.log.map((e) => e.text), m.log.map((e) => e.text));
    expect(c.matchId, 'm');
    c.undo();
    expect(c.lp[1], 8000);
  });
}

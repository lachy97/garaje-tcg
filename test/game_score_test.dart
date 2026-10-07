import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/db/enums.dart';
import 'package:garaje_tcg/features/tournaments/domain/game_score.dart';

void main() {
  group('GameScore (mejor de 3, J1 - Empates - J2)', () {
    test('Los 5 marcadores válidos y su resultado', () {
      expect(const GameScore(2, 0, 1).result, MatchResult.p1Win);
      expect(const GameScore(2, 0, 0).result, MatchResult.p1Win);
      expect(const GameScore(0, 0, 2).result, MatchResult.p2Win);
      expect(const GameScore(1, 0, 2).result, MatchResult.p2Win);
      expect(const GameScore(1, 1, 1).result, MatchResult.draw);
      expect(GameScore.allowed.every((s) => s.isValid), isTrue);
    });

    test('Rechaza marcadores imposibles o no permitidos', () {
      for (final s in const [
        GameScore(3, 0, 0), // nadie gana 3 juegos
        GameScore(2, 0, 2), // los dos no pueden llegar a 2
        GameScore(1, 0, 0), // nadie llegó a 2
        GameScore(0, 0, 0),
        GameScore(1, 1, 0),
        GameScore(2, 1, 0),
      ]) {
        expect(s.isValid, isFalse, reason: '$s');
      }
    });

    test('En Top Cut no se acepta 1-1-1', () {
      expect(const GameScore(1, 1, 1).isValidForTopCut, isFalse);
      expect(GameScore.allowedTopCut.length, 4);
      expect(GameScore.allowedTopCut.every((s) => s.result != MatchResult.draw), isTrue);
    });

    test('Parseo, texto y vista del rival', () {
      expect(GameScore.tryParse('2 - 0 - 1'), const GameScore(2, 0, 1));
      expect(GameScore.tryParse('2-0'), isNull);
      expect(const GameScore(2, 0, 1).toString(), '2-0-1');
      expect(const GameScore(2, 0, 1).swapped, const GameScore(1, 0, 2));
      expect(GameScore.bye, const GameScore(2, 0, 0));
    });
  });
}

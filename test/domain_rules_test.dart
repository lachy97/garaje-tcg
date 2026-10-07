import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/utils/season_utils.dart';
import 'package:garaje_tcg/features/ranking/domain/points_scale.dart';
import 'package:garaje_tcg/features/tournaments/domain/tournament_rules.dart';

void main() {
  group('PointsScale por defecto', () {
    test('Top 16 coincide con la escala base', () {
      final s = PointsScale.defaultFor(16);
      expect([1, 2, 3, 4, 5, 8, 9, 16, 17].map(s.pointsFor),
          [600, 500, 400, 300, 200, 200, 100, 100, 0]);
    });
    test('Top 8 y Top 32 escalan ±100', () {
      expect(PointsScale.defaultFor(8).pointsFor(1), 500);
      expect(PointsScale.defaultFor(8).pointsFor(9), 0);
      expect(PointsScale.defaultFor(32).pointsFor(1), 700);
      expect(PointsScale.defaultFor(32).pointsFor(32), 100);
    });
    test('Top 4 da menos puntos', () {
      final s = PointsScale.defaultFor(4);
      expect([1, 2, 3, 4, 5].map(s.pointsFor), [400, 300, 200, 100, 0]);
    });
    test('Sin Top Cut nadie puntúa', () {
      expect(PointsScale.defaultFor(0).pointsFor(1), 0);
    });
  });

  group('TournamentRules', () {
    test('Rondas Swiss sugeridas', () {
      expect(TournamentRules.suggestedSwissRounds(6), 3);
      expect(TournamentRules.suggestedSwissRounds(16), 4);
      expect(TournamentRules.suggestedSwissRounds(17), 5);
      expect(TournamentRules.suggestedSwissRounds(64), 6);
    });
    test('Top Cut permitido', () {
      expect(TournamentRules.allowedTopCuts(5), isEmpty);
      expect(TournamentRules.allowedTopCuts(6), [4]);
      expect(TournamentRules.allowedTopCuts(14), [4]);
      expect(TournamentRules.allowedTopCuts(15), [8]);
      expect(TournamentRules.allowedTopCuts(30), [8, 16]);
      expect(TournamentRules.suggestedTopCut(50), 32);
    });
  });

  group('Temporadas', () {
    test('Trimestres', () {
      expect(quarterOf(DateTime(2026, 10, 5)), 4);
      final (start, end) = quarterRange(2026, 4);
      expect(start, DateTime(2026, 10, 1));
      expect(end.year, 2026);
      expect(end.month, 12);
      expect(end.day, 31);
    });
  });
}

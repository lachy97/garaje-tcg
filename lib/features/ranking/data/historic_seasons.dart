import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import '../../../core/db/app_database.dart';

/// Rankings finales de las temporadas anteriores a la app (T1, T2 y T3 de
/// 2026), copiados de las tablas de Excel de la comunidad. Solo el ranking
/// final: no hay partidas ni mazos. Se guardan como la foto de una temporada
/// cerrada (ranking_snapshots), así salen en Datos → Ranking al elegir esa
/// temporada y cuentan en el ranking global.
class HistoricRow {
  const HistoricRow(this.rank, this.name, this.points, this.games, this.wins, this.losses, this.tournaments, this.best,
      {this.draws});

  final int rank;

  /// Nombre como sale en el Excel.
  final String name;
  final int points;

  /// PJ, PG y PP del Excel (PE solo en la T3; en T1 y T2 se deduce).
  final int games;
  final int wins;
  final int losses;
  final int? draws;
  final int tournaments;

  /// "1", "2", "3", "4", "TOP 8", "TOP 16" o "MATAU" (sin Top).
  final String best;

  int get drawCount => draws ?? (games - wins - losses).clamp(0, games);

  /// Mejor posición como número (para ordenar) y como texto.
  (int, String?) get bestPosition => switch (best) {
        'TOP 8' => (5, 'Top 8'),
        'TOP 16' => (9, 'Top 16'),
        'MATAU' => (99, 'Sin Top'),
        _ => (int.parse(best), null),
      };
}

class HistoricSeason {
  const HistoricSeason(this.year, this.quarter, this.rows);
  final int year;
  final int quarter;
  final List<HistoricRow> rows;
}

typedef _R = HistoricRow;

const historicSeasons = [
  HistoricSeason(2026, 1, [
    _R(1, 'JAVIER', 3050, 70, 52, 18, 12, '1'),
    _R(2, 'JORGITO', 2500, 60, 42, 17, 10, '1'),
    _R(3, 'CHRISTIAN', 2050, 49, 35, 14, 9, '1'),
    _R(4, 'DARIEL BRITO', 1700, 49, 34, 15, 8, '1'),
    _R(5, 'BARBARO', 1500, 26, 21, 5, 4, '1'),
    _R(6, 'MARCOS', 1300, 59, 34, 25, 11, '2'),
    _R(7, 'DARIEL', 1200, 43, 26, 17, 8, '1'),
    _R(8, 'GERARDO', 1200, 60, 25, 35, 11, '2'),
    _R(9, 'RICHARD', 900, 58, 25, 33, 11, '2'),
    _R(10, 'KIRITACHI', 900, 59, 30, 33, 11, '3'),
    _R(11, 'EFRAIN', 800, 14, 9, 5, 2, '2'),
    _R(12, 'ALEXIS', 700, 32, 17, 15, 6, '2'),
    _R(13, 'RONALDO', 700, 40, 17, 23, 8, '2'),
    _R(14, 'ÑOÑO', 700, 47, 20, 27, 9, '3'),
    _R(15, 'CARLITOS', 500, 41, 21, 20, 8, '2'),
    _R(16, 'ZEFRA', 500, 28, 14, 14, 5, '2'),
    _R(17, 'JORGITO ARQ', 400, 32, 17, 12, 4, '4'),
    _R(18, 'ARBA', 400, 35, 17, 18, 7, '4'),
    _R(19, 'HECTOR', 300, 11, 8, 3, 2, '3'),
    _R(20, 'LEO', 300, 25, 13, 12, 5, 'TOP 8'),
    _R(21, 'MIGUEL ABACUA', 200, 26, 13, 13, 5, '4'),
    _R(22, 'TONY', 200, 21, 11, 10, 4, 'TOP 8'),
    _R(23, 'HEROX', 200, 14, 7, 7, 3, 'TOP 8'),
    _R(24, 'LUCKY', 200, 19, 8, 11, 4, 'TOP 8'),
    _R(25, 'MACHI', 100, 11, 6, 5, 2, 'TOP 8'),
    _R(26, 'MARCELO', 100, 5, 3, 2, 1, 'TOP 8'),
    _R(27, 'ANDY AHIJADO', 100, 19, 7, 12, 4, 'TOP 8'),
    _R(28, 'RONY', 100, 43, 14, 29, 7, 'TOP 8'),
    _R(29, 'LACHY(FRANKLIN)', 100, 28, 9, 19, 6, 'TOP 8'),
    _R(30, 'MIGUEL V.', 100, 39, 11, 28, 8, 'TOP 8'),
    _R(31, 'ROBERT', 0, 9, 4, 5, 2, 'MATAU'),
    _R(32, 'EDUARDO', 0, 18, 8, 10, 4, 'MATAU'),
    // En el Excel sale como 38 entre el 32 y el 33: se respeta el orden.
    _R(33, 'CORONA', 0, 28, 12, 16, 6, 'MATAU'),
    _R(34, 'MALEY', 0, 5, 2, 3, 1, 'MATAU'),
    _R(35, 'CHINO', 0, 5, 2, 3, 1, 'MATAU'),
    _R(36, 'LEANDRO', 0, 5, 2, 3, 1, 'MATAU'),
    _R(37, 'SADIEL', 0, 28, 10, 18, 6, 'MATAU'),
    _R(38, 'KIRITO', 0, 15, 5, 10, 2, 'MATAU'),
    _R(39, 'LACHY', 0, 30, 10, 20, 6, 'MATAU'),
    _R(40, 'ALBERTO', 0, 10, 3, 7, 2, 'MATAU'),
    _R(41, 'ELENDO', 0, 10, 3, 7, 2, 'MATAU'),
    _R(42, 'LORENZO', 0, 8, 2, 6, 1, 'MATAU'),
    _R(43, 'PABLO', 0, 4, 1, 3, 1, 'MATAU'),
    _R(44, 'ANGEL', 0, 5, 1, 4, 1, 'MATAU'),
    _R(45, 'KRISTER', 0, 9, 1, 8, 2, 'MATAU'),
    _R(46, 'JOSE MEDINA', 0, 4, 0, 4, 1, 'MATAU'),
  ]),
  HistoricSeason(2026, 2, [
    _R(1, 'JAVIER', 2400, 58, 45, 13, 9, '1'),
    _R(2, 'ERNESTO CACHARRO', 1800, 51, 34, 17, 9, '1'),
    _R(3, 'SADIEL', 1500, 50, 27, 23, 9, '1'),
    _R(4, 'MACHI', 1300, 37, 28, 9, 6, '1'),
    _R(5, 'EDUARDO', 1200, 47, 26, 21, 9, '1'),
    _R(6, 'DARIEL', 1100, 46, 27, 19, 8, '2'),
    _R(7, 'EFRAIN', 1000, 26, 20, 6, 4, '2'),
    _R(8, 'MARCOS', 1000, 51, 30, 21, 9, '2'),
    _R(9, 'DARIEL BRITO', 700, 25, 16, 9, 4, '1'),
    _R(10, 'MANUEL', 700, 50, 24, 26, 9, '1'),
    _R(11, 'KIRITACHI', 700, 53, 30, 23, 10, '2'),
    _R(12, 'JORGITO ARQ', 600, 27, 19, 8, 6, '1'),
    _R(13, 'ALEXIS', 600, 24, 15, 9, 3, '2'),
    _R(14, 'RICHARD', 600, 44, 26, 21, 8, '3'),
    _R(15, 'FABIO', 500, 37, 17, 20, 7, '3'),
    _R(16, 'LACHY', 400, 43, 21, 22, 8, '4'),
    _R(17, 'KRISTER', 300, 4, 2, 2, 2, '3'),
    _R(18, 'LEO', 300, 25, 12, 13, 5, '3'),
    _R(19, 'TONY', 300, 44, 17, 27, 9, '4'),
    _R(20, 'LACHY(FRANKLIN)', 300, 40, 22, 18, 9, 'TOP 8'),
    _R(21, 'EL POLACO', 200, 7, 5, 2, 1, '4'),
    _R(22, 'ARBA', 200, 13, 8, 5, 2, '4'),
    _R(23, 'THE SAMURAI', 200, 29, 14, 15, 5, 'TOP 8'),
    _R(24, 'DARIEL ALEJANDRO', 200, 18, 9, 9, 3, '4'),
    _R(25, 'CHRISTIAN', 200, 14, 6, 8, 3, '4'),
    _R(26, 'RONALDO', 200, 24, 11, 13, 5, 'TOP 8'),
    _R(27, 'MALEY', 100, 16, 11, 5, 3, 'TOP 8'),
    _R(28, 'CORONA', 100, 16, 10, 6, 3, 'TOP 8'),
    _R(29, 'CARLITOS', 100, 21, 13, 8, 4, 'TOP 8'),
    _R(30, 'LEOVALDO', 100, 11, 6, 5, 3, 'TOP 8'),
    _R(31, 'DANIEL', 100, 6, 3, 3, 1, 'TOP 8'),
    _R(32, 'ANDY AHIJADO', 100, 6, 3, 3, 1, 'TOP 8'),
    _R(33, 'ROBERT', 100, 24, 11, 13, 5, 'TOP 8'),
    _R(34, 'MARCELO', 100, 9, 4, 5, 3, 'TOP 8'),
    _R(35, 'ALBERTO', 100, 46, 20, 26, 11, 'TOP 8'),
    _R(36, 'ANGEL', 100, 18, 7, 11, 4, 'TOP 8'),
    _R(37, 'ELENDO', 100, 8, 3, 5, 2, 'TOP 8'),
    _R(38, 'CARLY', 100, 37, 13, 24, 8, 'TOP 8'),
    _R(39, 'RONY', 100, 47, 17, 30, 10, 'TOP 8'),
    _R(40, 'ARIEL', 0, 5, 3, 2, 1, 'MATAU'),
    _R(41, 'LIVAN', 0, 5, 3, 2, 1, 'MATAU'),
    _R(42, 'MIGUEL ABACUA', 0, 27, 15, 14, 6, 'MATAU'),
    _R(43, 'MIKE', 0, 8, 4, 4, 2, 'MATAU'),
    _R(44, 'JORGITO', 0, 4, 2, 2, 1, 'MATAU'),
    _R(45, 'JUAN CARLOS', 0, 10, 5, 5, 2, 'MATAU'),
    _R(46, 'LIONPRINCE', 0, 22, 10, 12, 5, 'MATAU'),
    _R(47, 'MIGUEL V.', 0, 10, 4, 6, 2, 'MATAU'),
    _R(48, 'YESLEY', 0, 10, 4, 6, 2, 'MATAU'),
    _R(49, 'IRVING', 0, 4, 1, 3, 1, 'MATAU'),
    _R(50, 'KIRITO', 0, 37, 9, 28, 8, 'MATAU'),
    _R(51, 'GERARDO', 0, 10, 2, 8, 2, 'MATAU'),
    _R(52, 'HEROX', 0, 5, 1, 4, 1, 'MATAU'),
    _R(53, 'CANDELA', 0, 5, 1, 4, 1, 'MATAU'),
    _R(54, 'LUCKY', 0, 5, 0, 5, 1, 'MATAU'),
  ]),
  HistoricSeason(2026, 3, [
    _R(1, 'EFRAIN', 2700, 70, 48, 21, 10, '1', draws: 1),
    _R(2, 'JORGITO ARQ', 1800, 65, 47, 18, 10, '1', draws: 0),
    _R(3, 'RONALDO', 1600, 75, 42, 33, 12, '1', draws: 0),
    _R(4, 'DARIEL', 1500, 66, 42, 24, 10, '1', draws: 0),
    _R(5, 'JAVIER', 1400, 47, 36, 11, 7, '1', draws: 0),
    _R(6, 'RONY', 1400, 73, 40, 33, 12, '2', draws: 0),
    _R(7, 'GERARDO', 1300, 55, 34, 20, 8, '1', draws: 1),
    _R(8, 'EDUARDO', 1200, 71, 38, 32, 11, '3', draws: 1),
    _R(9, 'KIRITACHI', 1100, 61, 39, 25, 10, '2', draws: 3),
    _R(10, 'RICHARD', 1000, 74, 41, 33, 13, '2', draws: 0),
    _R(11, 'MARCELO', 1000, 47, 24, 22, 6, '2', draws: 1),
    _R(12, 'ALEXIS', 900, 62, 31, 30, 9, '4', draws: 1),
    _R(13, 'LACHY PROWA', 800, 63, 33, 28, 11, '1', draws: 1),
    _R(14, 'IRVING', 800, 58, 27, 31, 10, '2', draws: 0),
    _R(15, 'ANDY AHIJADO', 700, 14, 11, 3, 2, '1', draws: 0),
    _R(16, 'MIGUEL ABACUA', 700, 61, 33, 27, 11, '2', draws: 1),
    _R(17, 'KRISTER', 700, 26, 13, 10, 4, '2', draws: 2),
    _R(18, 'SADIEL', 700, 68, 31, 35, 12, '4', draws: 2),
    _R(19, 'HANSEN', 600, 45, 22, 23, 7, '2', draws: 0),
    _R(20, 'THE SAMURAI', 600, 59, 29, 29, 10, '3', draws: 1),
    _R(21, 'MIKE', 600, 68, 29, 36, 12, '4', draws: 3),
    _R(22, 'ERNESTO CACHARRO', 700, 57, 30, 24, 10, 'TOP 8', draws: 3),
    _R(23, 'DANIEL', 500, 19, 14, 4, 3, '1', draws: 1),
    _R(24, 'OSMEL', 500, 14, 8, 6, 2, '2', draws: 0),
    _R(25, 'MARCOS', 500, 69, 27, 41, 13, '2', draws: 2),
    _R(26, 'MIGUEL VITILIGO', 500, 25, 15, 10, 4, '3', draws: 0),
    _R(27, 'DARIEL BRITO', 500, 30, 13, 16, 5, '3', draws: 1),
    _R(28, 'CHRISTIAN', 500, 40, 26, 14, 7, 'TOP 8', draws: 0),
    _R(29, 'JUAN CARLOS', 400, 20, 11, 9, 3, '4', draws: 0),
    _R(30, 'ROBERT', 300, 34, 14, 17, 5, '4', draws: 3),
    _R(31, 'JOTA', 300, 63, 25, 37, 12, '4', draws: 2),
    _R(32, 'FERNANDO', 300, 33, 18, 14, 6, 'TOP 8', draws: 1),
    _R(33, 'ARIEL ENRIQUE', 300, 13, 7, 6, 2, 'TOP 8', draws: 0),
    _R(34, 'LACHY(FRANKLIN)', 300, 33, 15, 17, 6, 'TOP 8', draws: 1),
    _R(35, 'DARIEL ALEJANDRO', 200, 7, 5, 2, 1, 'TOP 8', draws: 0),
    _R(36, 'RICK', 200, 52, 25, 26, 10, 'TOP 8', draws: 1),
    _R(37, 'CRIS', 200, 57, 26, 30, 10, 'TOP 8', draws: 1),
    _R(38, 'MALEY', 200, 17, 8, 9, 3, 'TOP 8', draws: 0),
    _R(39, 'JORGE DE LA VEGA', 200, 17, 7, 10, 3, 'TOP 8', draws: 0),
    _R(40, 'RANGO', 200, 17, 10, 7, 3, 'TOP 16', draws: 0),
    _R(41, 'EL POLACO', 200, 12, 6, 6, 2, 'TOP 16', draws: 0),
    _R(42, 'ALBERTO', 100, 21, 9, 12, 10, 'TOP 8', draws: 0),
    _R(43, 'LEO', 100, 31, 12, 18, 6, 'TOP 8', draws: 1),
    _R(44, 'ARBA', 100, 31, 11, 20, 6, 'TOP 8', draws: 0),
    _R(45, 'DIEGOFR', 100, 16, 8, 8, 3, 'TOP 16', draws: 0),
    _R(46, 'LIVAN', 100, 11, 5, 6, 2, 'TOP 16', draws: 0),
    _R(47, 'HEROX', 100, 11, 5, 6, 1, 'TOP 16', draws: 0),
    _R(48, 'MANUEL', 100, 66, 30, 35, 12, 'TOP 16', draws: 1),
    _R(49, 'YOANDRY', 100, 31, 12, 18, 6, 'TOP 16', draws: 1),
    _R(50, 'TONY', 100, 56, 22, 34, 11, 'TOP 16', draws: 0),
    _R(51, 'CARLY', 100, 51, 18, 33, 10, 'TOP 16', draws: 0),
    _R(52, 'ANDRES C.', 0, 5, 3, 2, 1, 'MATAU', draws: 0),
    _R(53, 'MACHADO', 0, 10, 5, 5, 2, 'MATAU', draws: 0),
    _R(54, 'YEISON', 0, 15, 6, 9, 3, 'MATAU', draws: 0),
    _R(55, 'JORDAN', 0, 20, 8, 12, 4, 'MATAU', draws: 0),
    _R(56, 'YESLEY', 0, 5, 2, 3, 1, 'MATAU', draws: 0),
    _R(57, 'ARNOLD', 0, 15, 6, 9, 3, 'MATAU', draws: 0),
    _R(58, 'LUIS ANGEL', 0, 5, 2, 3, 1, 'MATAU', draws: 0),
    _R(59, 'JOSE CARLOS', 0, 5, 2, 3, 1, 'MATAU', draws: 0),
    _R(60, 'ZEFRA', 0, 10, 4, 6, 2, 'MATAU', draws: 0),
    _R(61, 'LUCKY', 0, 10, 4, 6, 2, 'MATAU', draws: 0),
    _R(62, 'ALEJANDRO', 0, 20, 8, 12, 4, 'MATAU', draws: 0),
    _R(63, 'FABIO', 0, 30, 11, 19, 6, 'MATAU', draws: 0),
    _R(64, 'ANGEL', 0, 15, 5, 10, 3, 'MATAU', draws: 0),
    _R(65, 'MARCOS LUIS', 0, 10, 3, 7, 2, 'MATAU', draws: 0),
    _R(66, 'CARLITOS', 0, 15, 4, 11, 3, 'MATAU', draws: 0),
    _R(67, 'JORGITO', 0, 5, 1, 4, 1, 'MATAU', draws: 0),
    _R(68, 'MARLON', 0, 5, 1, 4, 1, 'MATAU', draws: 0),
    _R(69, 'CARLOS URRUTIA', 0, 5, 1, 4, 1, 'MATAU', draws: 0),
    _R(70, 'LIONPRINCE', 0, 15, 2, 13, 3, 'MATAU', draws: 0),
    _R(71, 'RODRIGO', 0, 10, 1, 7, 2, 'MATAU', draws: 1),
    _R(72, 'OSNIEL', 0, 10, 1, 9, 2, 'MATAU', draws: 0),
  ]),
];

/// Mismo jugador con otro nombre en el Excel (se proponen juntos).
const _sameAs = {
  'LACHY PROWA': 'LACHY',
  'MIGUEL VITILIGO': 'MIGUEL V.',
};

/// Nombre del Excel → apodos con los que puede estar ya en la app.
const _aliases = {
  'LACHY(FRANKLIN)': ['Lachy Lawton', 'Franklin'],
  'THE SAMURAI': ['El Samurai', 'The Samurai'],
  'ANDY AHIJADO': ['Andy', 'Andy Ahijado'],
  'ALEXIS': ['Alexy', 'Alexis'],
  'ANDRES C.': ['Andres', 'Andres C.'],
  'YEISON': ['Jeison', 'Yeison'],
};

/// Clave de un nombre del Excel (agrupa los que son la misma persona).
String historicKey(String name) => _sameAs[name] ?? name;

String _norm(String s) {
  const from = 'áéíóúüñÁÉÍÓÚÜÑ';
  const to = 'aeiouunAEIOUUN';
  final b = StringBuffer();
  for (final ch in s.characters) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// "JORGITO ARQ" → "Jorgito Arq" (para las fichas nuevas).
String historicNickname(String name) {
  if (name == 'LACHY(FRANKLIN)') return 'Lachy (Franklin)';
  return name
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Nombres distintos de las tres temporadas (por clave) con su ficha
/// propuesta: la que tiene ese apodo (o un alias conocido), o null = ficha
/// nueva.
Map<String, Player?> proposeHistoricMatches(List<Player> players) {
  final byNorm = <String, Player>{};
  for (final p in players) {
    if (p.deletedAt != null) continue;
    byNorm.putIfAbsent(_norm(p.nickname), () => p);
  }
  final out = <String, Player?>{};
  for (final s in historicSeasons) {
    for (final r in s.rows) {
      final key = historicKey(r.name);
      if (out.containsKey(key)) continue;
      Player? found = byNorm[_norm(key)];
      for (final a in _aliases[key] ?? const <String>[]) {
        found ??= byNorm[_norm(a)];
      }
      out[key] = found;
    }
  }
  return out;
}

/// Guarda las tres temporadas como cerradas con su ranking final.
/// [targets]: clave del nombre → id de ficha existente (las que falten se
/// crean como fichas nuevas). Se puede repetir: reemplaza la foto anterior.
Future<int> importHistoricSeasons(AppDatabase db, Map<String, String?> targets) {
  return db.transaction(() async {
    final ids = <String, String>{};
    for (final MapEntry(key: key, value: id) in targets.entries) {
      if (id != null) {
        ids[key] = id;
      } else {
        final p = await db.playersDao.create(nickname: historicNickname(key));
        ids[key] = p.id;
      }
    }
    final now = DateTime.now();
    var n = 0;
    for (final s in historicSeasons) {
      final season = await db.seasonsDao.seasonFor(DateTime(s.year, s.quarter * 3 - 1, 15));
      // Foto anterior (si se importa otra vez): borrado lógico.
      await (db.update(db.rankingSnapshots)
            ..where((r) => r.seasonId.equals(season.id) & r.deletedAt.isNull()))
          .write(RankingSnapshotsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      for (final r in s.rows) {
        final key = historicKey(r.name);
        final (best, label) = r.bestPosition;
        await db.into(db.rankingSnapshots).insert(RankingSnapshotsCompanion.insert(
              seasonId: season.id,
              playerId: ids[key]!,
              rank: r.rank,
              points: r.points,
              statsJson: jsonEncode({
                'nickname': historicNickname(key),
                'tournaments': r.tournaments,
                'best': best,
                'bestLabel': label,
                'w': r.wins,
                'l': r.losses,
                'd': r.drawCount,
                'games': r.games,
                'deck': null,
                'imported': true,
              }),
            ));
        n++;
      }
      await (db.update(db.seasons)..where((x) => x.id.equals(season.id))).write(SeasonsCompanion(
        status: const Value(SeasonStatus.closed),
        closedAt: Value(now),
        updatedAt: Value(now),
      ));
    }
    return n;
  });
}

/// Temporada importada (solo ranking final).
bool isHistoricSeason(Season s) =>
    historicSeasons.any((h) => h.year == s.year && h.quarter == s.quarter) && s.status == SeasonStatus.closed;

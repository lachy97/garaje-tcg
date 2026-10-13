import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../features/decks/domain/deck_matchups.dart';
import '../../../features/decks/domain/deck_stats.dart';
import '../../../features/ranking/domain/points_scale.dart';
import '../../../features/ranking/domain/ranking_row.dart';
import '../app_database.dart';
import '../tables.dart';

part 'ranking_dao.g.dart';

@DriftAccessor(tables: [PointsScaleEntries, SeasonResults])
class RankingDao extends DatabaseAccessor<AppDatabase> with _$RankingDaoMixin {
  RankingDao(super.attachedDatabase);

  /// Escala vigente para un tamaño de Top Cut (0 → escala vacía, nadie puntúa).
  Future<PointsScale> scaleFor(int topCutSize) async {
    final rows = await (select(pointsScaleEntries)
          ..where((e) => e.topCutSize.equals(topCutSize) & e.deletedAt.isNull())
          ..orderBy([(e) => OrderingTerm.asc(e.positionFrom)]))
        .get();
    return PointsScale(
      topCutSize,
      [for (final r in rows) PointsTier(r.positionFrom, r.positionTo, r.points)],
    );
  }

  /// Reemplaza la escala de un tamaño de Top Cut (pantalla de Ajustes).
  /// No recalcula torneos ya terminados.
  Future<void> replaceScale(PointsScale scale) {
    final now = DateTime.now();
    return transaction(() async {
      await (update(pointsScaleEntries)
            ..where((e) =>
                e.topCutSize.equals(scale.topCutSize) & e.deletedAt.isNull()))
          .write(PointsScaleEntriesCompanion(
              deletedAt: Value(now), updatedAt: Value(now)));
      await batch((b) => b.insertAll(pointsScaleEntries, [
            for (final t in scale.tiers)
              PointsScaleEntriesCompanion.insert(
                topCutSize: scale.topCutSize,
                positionFrom: t.from,
                positionTo: t.to,
                points: t.points,
              ),
          ]));
    });
  }

  /// Escribe los puntos de ranking de un torneo terminado.
  /// Idempotente: si se vuelve a finalizar el torneo, sobrescribe.
  Future<void> writeTournamentResults({
    required String seasonId,
    required String tournamentId,
    required int topCutSize,
    required Map<String, int> finalPositions, // playerId → posición
  }) async {
    final scale = await scaleFor(topCutSize);
    await batch((b) {
      b.deleteWhere(
          seasonResults, (r) => r.tournamentId.equals(tournamentId));
      b.insertAll(seasonResults, [
        for (final MapEntry(key: playerId, value: pos) in finalPositions.entries)
          SeasonResultsCompanion.insert(
            seasonId: seasonId,
            tournamentId: tournamentId,
            playerId: playerId,
            position: pos,
            points: scale.pointsFor(pos),
          ),
      ]);
    });
  }

  /// Ranking del trimestre con estadísticas completas.
  ///
  /// Solo cuentan los torneos **terminados** de la temporada (los mismos que dan
  /// puntos). Se recalcula cada vez que cambian los resultados de la temporada.
  ///
  /// Si la temporada está CERRADA se devuelve la foto guardada al cerrarla.
  Stream<List<RankingRow>> watchSeasonRanking(String seasonId) {
    final db = attachedDatabase;
    return customSelect(
      'SELECT COUNT(*) AS c FROM season_results WHERE season_id = ?',
      variables: [Variable.withString(seasonId)],
      readsFrom: {seasonResults, db.seasons, db.rankingSnapshots, db.players, db.tournaments},
    ).watch().asyncMap((_) => seasonRanking(seasonId));
  }

  Future<List<RankingRow>> seasonRanking(String seasonId) async {
    final season = await (attachedDatabase.select(attachedDatabase.seasons)
          ..where((s) => s.id.equals(seasonId)))
        .getSingleOrNull();
    if (season != null && season.status == SeasonStatus.closed) {
      final frozen = await _snapshotRanking(seasonId);
      if (frozen != null) return frozen;
    }
    return liveSeasonRanking(seasonId);
  }

  /// Ranking calculado con los torneos actuales (sin mirar la foto).
  Future<List<RankingRow>> liveSeasonRanking(String seasonId) async {
    final sid = Variable.withString(seasonId);
    const finished = "t.season_id = ? AND t.deleted_at IS NULL AND t.status = 'finished'";

    // 1) Puntos, torneos y mejor posición
    final base = await customSelect(
      'SELECT p.id AS id, p.nickname AS nickname, SUM(sr.points) AS pts, '
      'COUNT(*) AS t, MIN(sr.position) AS best '
      'FROM season_results sr JOIN players p ON p.id = sr.player_id '
      'JOIN tournaments t ON t.id = sr.tournament_id '
      'WHERE $finished AND sr.deleted_at IS NULL '
      'GROUP BY p.id, p.nickname',
      variables: [sid],
    ).get();

    // 2) Partidas (sin BYE) de esos torneos
    final matches = await customSelect(
      'SELECT m.player1_id AS p1, m.player2_id AS p2, m.result AS r '
      'FROM matches m JOIN tournaments t ON t.id = m.tournament_id '
      "WHERE $finished AND m.deleted_at IS NULL AND m.is_bye = 0 AND m.result != 'pending'",
      variables: [sid],
    ).get();

    // 3) Último mazo usado (torneo más reciente)
    final decks = await customSelect(
      'SELECT tp.player_id AS pid, d.name AS deck '
      'FROM tournament_players tp JOIN tournaments t ON t.id = tp.tournament_id '
      'LEFT JOIN decks d ON d.id = tp.deck_id '
      'WHERE $finished AND tp.deleted_at IS NULL '
      'ORDER BY t.date ASC, t.created_at ASC',
      variables: [sid],
    ).get();

    final w = <String, int>{}, l = <String, int>{}, d = <String, int>{};
    void add(Map<String, int> m, String id) => m[id] = (m[id] ?? 0) + 1;
    for (final row in matches) {
      final p1 = row.read<String>('p1');
      final p2 = row.read<String?>('p2');
      if (p2 == null) continue;
      switch (row.read<String>('r')) {
        case 'p1Win':
          add(w, p1);
          add(l, p2);
        case 'p2Win':
          add(w, p2);
          add(l, p1);
        case 'draw':
          add(d, p1);
          add(d, p2);
        case 'doubleLoss':
          add(l, p1);
          add(l, p2);
      }
    }
    final lastDeck = <String, String?>{
      for (final row in decks) row.read<String>('pid'): row.read<String?>('deck'),
    };

    return RankingRow.sortAndRank([
      for (final row in base)
        RankingRow(
          playerId: row.read<String>('id'),
          nickname: row.read<String>('nickname'),
          points: row.read<int>('pts'),
          tournaments: row.read<int>('t'),
          bestPosition: row.read<int>('best'),
          wins: w[row.read<String>('id')] ?? 0,
          losses: l[row.read<String>('id')] ?? 0,
          draws: d[row.read<String>('id')] ?? 0,
          lastDeck: lastDeck[row.read<String>('id')],
        ),
    ]);
  }

  /// Puntos obtenidos en un torneo (para la pantalla de resultado final).
  Stream<List<SeasonResult>> watchTournamentResults(String tournamentId) {
    return (select(seasonResults)
          ..where((r) => r.tournamentId.equals(tournamentId) & r.deletedAt.isNull())
          ..orderBy([(r) => OrderingTerm.asc(r.position)]))
        .watch();
  }

  // ───────────────────────── Mazos (tier list) ─────────────────────────

  /// Tabla de mazos de la temporada. Se recalcula al terminar torneos o al
  /// renombrar/fusionar mazos.
  ///
  /// Si la temporada está CERRADA se devuelve la foto guardada al cerrarla.
  Stream<List<DeckSeasonStats>> watchSeasonDecks(String seasonId) {
    final db = attachedDatabase;
    return customSelect(
      'SELECT COUNT(*) AS c FROM tournaments WHERE season_id = ?',
      variables: [Variable.withString(seasonId)],
      readsFrom: {
        db.tournaments,
        db.tournamentPlayers,
        db.decks,
        db.matches,
        db.seasons,
        db.deckSnapshots,
      },
    ).watch().asyncMap((_) => seasonDecks(seasonId));
  }

  Future<List<DeckSeasonStats>> seasonDecks(String seasonId) async {
    final season = await (attachedDatabase.select(attachedDatabase.seasons)
          ..where((s) => s.id.equals(seasonId)))
        .getSingleOrNull();
    if (season != null && season.status == SeasonStatus.closed) {
      final frozen = await _snapshotDecks(seasonId);
      if (frozen != null) return frozen;
    }
    return liveSeasonDecks(seasonId);
  }

  /// Tabla de mazos calculada con los torneos actuales (sin mirar la foto).
  Future<List<DeckSeasonStats>> liveSeasonDecks(String seasonId) async {
    final sid = Variable.withString(seasonId);
    const finished = "t.season_id = ? AND t.deleted_at IS NULL AND t.status = 'finished'";

    final entries = await customSelect(
      'SELECT tp.deck_id AS deck, d.name AS name, d.image_path AS img, tp.player_id AS pid, '
      't.top_cut_size AS top, tp.final_position AS pos '
      'FROM tournament_players tp '
      'JOIN tournaments t ON t.id = tp.tournament_id '
      'JOIN decks d ON d.id = tp.deck_id '
      'WHERE $finished AND tp.deleted_at IS NULL AND tp.deck_id IS NOT NULL',
      variables: [sid],
    ).get();

    final matches = await seasonDeckMatches(seasonId);

    return DeckStats.compute(
      entries: [
        for (final e in entries)
          DeckEntryRow(
            deckId: e.read<String>('deck'),
            deckName: e.read<String>('name'),
            playerId: e.read<String>('pid'),
            topCutSize: e.read<int>('top'),
            finalPosition: e.read<int?>('pos'),
            imagePath: e.read<String?>('img'),
          ),
      ],
      matches: matches,
    );
  }

  /// Partidas (sin BYE, reportadas) de los torneos terminados de la temporada,
  /// con el mazo de cada lado.
  Future<List<DeckMatchRow>> seasonDeckMatches(String seasonId) async {
    const finished = "t.season_id = ? AND t.deleted_at IS NULL AND t.status = 'finished'";
    final rows = await customSelect(
      'SELECT m.deck1_id AS d1, m.deck2_id AS d2, m.result AS r, rd.phase AS phase '
      'FROM matches m '
      'JOIN tournaments t ON t.id = m.tournament_id '
      'JOIN rounds rd ON rd.id = m.round_id '
      "WHERE $finished AND m.deleted_at IS NULL AND m.is_bye = 0 AND m.result != 'pending'",
      variables: [Variable.withString(seasonId)],
    ).get();
    return [
      for (final m in rows)
        DeckMatchRow(
          deck1Id: m.read<String?>('d1'),
          deck2Id: m.read<String?>('d2'),
          result: MatchResult.values.byName(m.read<String>('r')),
          isTopCut: m.read<String>('phase') == RoundPhase.topCut.name,
        ),
    ];
  }

  /// Matriz de enfrentamientos de la temporada (se recalcula con los torneos).
  Stream<DeckMatchups> watchSeasonMatchups(String seasonId) {
    final db = attachedDatabase;
    return customSelect(
      'SELECT COUNT(*) AS c FROM tournaments WHERE season_id = ?',
      variables: [Variable.withString(seasonId)],
      readsFrom: {db.tournaments, db.matches, db.decks},
    ).watch().asyncMap((_) async => DeckMatchups.compute(await seasonDeckMatches(seasonId)));
  }

  /// Inscripciones con [deckId] en los torneos terminados de la temporada
  /// (ficha del mazo), del torneo más reciente al más antiguo.
  Stream<List<DeckTournamentEntry>> watchDeckEntries(String seasonId, String deckId) {
    final db = attachedDatabase;
    return customSelect(
      'SELECT t.id AS tid, t.name AS tname, t.date AS tdate, t.top_cut_size AS top, '
      'p.id AS pid, p.nickname AS nick, tp.final_position AS pos '
      'FROM tournament_players tp '
      'JOIN tournaments t ON t.id = tp.tournament_id '
      'JOIN players p ON p.id = tp.player_id '
      "WHERE t.season_id = ? AND t.deleted_at IS NULL AND t.status = 'finished' "
      'AND tp.deleted_at IS NULL AND tp.deck_id = ? '
      'ORDER BY t.date DESC, tp.final_position ASC',
      variables: [Variable.withString(seasonId), Variable.withString(deckId)],
      readsFrom: {db.tournaments, db.tournamentPlayers, db.players},
    ).watch().map((rows) => [
          for (final r in rows)
            DeckTournamentEntry(
              tournamentId: r.read<String>('tid'),
              tournamentName: r.read<String>('tname'),
              date: r.read<DateTime>('tdate'),
              playerId: r.read<String>('pid'),
              playerName: r.read<String>('nick'),
              topCutSize: r.read<int>('top'),
              finalPosition: r.read<int?>('pos'),
            ),
        ]);
  }

  // ───────────────────────── Cierre de temporada ─────────────────────────

  /// Torneos sin terminar de la temporada (impiden cerrarla).
  Future<List<Tournament>> unfinishedTournaments(String seasonId) {
    final t = attachedDatabase.tournaments;
    return (attachedDatabase.select(t)
          ..where((x) =>
              x.seasonId.equals(seasonId) &
              x.deletedAt.isNull() &
              x.status.equalsValue(TournamentStatus.finished).not()))
        .get();
  }

  /// Cierra la temporada: guarda la foto del ranking de jugadores y de la
  /// tabla de mazos y marca la temporada como cerrada. A partir de ahí sus
  /// torneos no se pueden cambiar (ver TournamentsDao.ensureEditable).
  Future<void> closeSeason(String seasonId) {
    final db = attachedDatabase;
    return transaction(() async {
      final pending = await unfinishedTournaments(seasonId);
      if (pending.isNotEmpty) {
        throw StateError('Termina o borra antes estos torneos: '
            '${pending.map((t) => t.name).join(', ')}.');
      }
      final ranking = await liveSeasonRanking(seasonId);
      final decks = await liveSeasonDecks(seasonId);
      final now = DateTime.now();
      // Borrado lógico de la foto anterior (listo para sincronizar).
      await (update(db.rankingSnapshots)
            ..where((r) => r.seasonId.equals(seasonId) & r.deletedAt.isNull()))
          .write(RankingSnapshotsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      await (update(db.deckSnapshots)
            ..where((r) => r.seasonId.equals(seasonId) & r.deletedAt.isNull()))
          .write(DeckSnapshotsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      await batch((b) {
        b.insertAll(db.rankingSnapshots, [
          for (final r in ranking)
            RankingSnapshotsCompanion.insert(
              seasonId: seasonId,
              playerId: r.playerId,
              rank: r.rank,
              points: r.points,
              statsJson: jsonEncode({
                'nickname': r.nickname,
                'tournaments': r.tournaments,
                'best': r.bestPosition,
                'w': r.wins,
                'l': r.losses,
                'd': r.draws,
                'deck': r.lastDeck,
              }),
            ),
        ]);
        b.insertAll(db.deckSnapshots, [
          for (final d in decks)
            DeckSnapshotsCompanion.insert(
              seasonId: seasonId,
              deckId: d.deckId,
              rank: d.rank,
              score: d.power.toDouble(),
              statsJson: jsonEncode({
                'name': d.name,
                'tier': d.tier.name,
                'power': d.power,
                'presence': d.presence,
                'conversion': d.conversion,
                'entries': d.entries,
                'pilots': d.pilots.toList(),
                'topEntries': d.topEntries,
                'titles': d.titles,
                'best': d.bestPosition,
                'swiss': [d.swissWins, d.swissLosses, d.swissDraws],
                'top': [d.topWins, d.topLosses],
              }),
            ),
        ]);
      });
      await (update(db.seasons)..where((s) => s.id.equals(seasonId))).write(
        SeasonsCompanion(
          status: const Value(SeasonStatus.closed),
          closedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });
  }

  /// Reabre una temporada cerrada (Modo administrador): borra la foto y sus
  /// torneos vuelven a ser editables; el ranking vuelve a calcularse en vivo.
  Future<void> reopenSeason(String seasonId) {
    final db = attachedDatabase;
    return transaction(() async {
      final now = DateTime.now();
      // Borrado lógico de la foto anterior (listo para sincronizar).
      await (update(db.rankingSnapshots)
            ..where((r) => r.seasonId.equals(seasonId) & r.deletedAt.isNull()))
          .write(RankingSnapshotsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      await (update(db.deckSnapshots)
            ..where((r) => r.seasonId.equals(seasonId) & r.deletedAt.isNull()))
          .write(DeckSnapshotsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      await (update(db.seasons)..where((s) => s.id.equals(seasonId))).write(
        SeasonsCompanion(
          status: const Value(SeasonStatus.active),
          closedAt: const Value(null),
          updatedAt: Value(now),
        ),
      );
    });
  }

  /// Ranking guardado al cerrar la temporada (null = no hay foto).
  Future<List<RankingRow>?> _snapshotRanking(String seasonId) async {
    final db = attachedDatabase;
    final rows = await (select(db.rankingSnapshots)
          ..where((r) => r.seasonId.equals(seasonId) & r.deletedAt.isNull())
          ..orderBy([(r) => OrderingTerm.asc(r.rank)]))
        .get();
    if (rows.isEmpty) return null;
    return [
      for (final r in rows)
        () {
          final j = jsonDecode(r.statsJson) as Map<String, dynamic>;
          return RankingRow(
            playerId: r.playerId,
            nickname: j['nickname'] as String? ?? '?',
            points: r.points,
            tournaments: j['tournaments'] as int? ?? 0,
            bestPosition: j['best'] as int? ?? 0,
            wins: j['w'] as int? ?? 0,
            losses: j['l'] as int? ?? 0,
            draws: j['d'] as int? ?? 0,
            lastDeck: j['deck'] as String?,
            rank: r.rank,
          );
        }(),
    ];
  }

  /// Tabla de mazos guardada al cerrar la temporada (null = no hay foto).
  /// El nombre es el de ese momento; la imagen, la actual del mazo.
  Future<List<DeckSeasonStats>?> _snapshotDecks(String seasonId) async {
    final db = attachedDatabase;
    final rows = await (select(db.deckSnapshots)
          ..where((r) => r.seasonId.equals(seasonId) & r.deletedAt.isNull())
          ..orderBy([(r) => OrderingTerm.asc(r.rank)]))
        .get();
    if (rows.isEmpty) return null;
    final images = {
      for (final d in await select(db.decks).get()) d.id: d.imagePath,
    };
    int n(Object? v) => v is num ? v.toInt() : 0;
    return [
      for (final r in rows)
        () {
          final j = jsonDecode(r.statsJson) as Map<String, dynamic>;
          final swiss = (j['swiss'] as List?) ?? const [0, 0, 0];
          final top = (j['top'] as List?) ?? const [0, 0];
          final s = DeckSeasonStats(r.deckId, j['name'] as String? ?? '?',
              imagePath: images[r.deckId])
            ..entries = n(j['entries'])
            ..swissWins = n(swiss.elementAtOrNull(0))
            ..swissLosses = n(swiss.elementAtOrNull(1))
            ..swissDraws = n(swiss.elementAtOrNull(2))
            ..topWins = n(top.elementAtOrNull(0))
            ..topLosses = n(top.elementAtOrNull(1))
            ..topEntries = n(j['topEntries'])
            ..titles = n(j['titles'])
            ..bestPosition = j['best'] as int?
            ..power = n(j['power'])
            ..presence = (j['presence'] as num?)?.toDouble() ?? 0
            ..rank = r.rank
            ..tier = DeckTier.values.asNameMap()[j['tier']] ?? DeckTier.rogue;
          final pilots = j['pilots'];
          if (pilots is List) s.pilots.addAll(pilots.whereType<String>());
          return s;
        }(),
    ];
  }
}

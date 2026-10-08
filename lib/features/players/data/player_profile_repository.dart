import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import '../domain/player_profile.dart';

/// Lee de la BD todo lo que necesita el perfil de un jugador.
/// Los matches son la fuente de verdad: nada se guarda aparte.
class PlayerProfileRepository {
  PlayerProfileRepository(this._db);

  final AppDatabase _db;

  /// Se recalcula cuando cambia cualquier match, inscripción, torneo o nombre.
  Stream<PlayerProfileData> watch(String playerId) {
    return _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM matches m '
          'WHERE m.player1_id = ? OR m.player2_id = ?',
          variables: [Variable.withString(playerId), Variable.withString(playerId)],
          readsFrom: {
            _db.matches,
            _db.rounds,
            _db.tournaments,
            _db.tournamentPlayers,
            _db.players,
            _db.decks,
          },
        )
        .watch()
        .asyncMap((_) => load(playerId));
  }

  Future<PlayerProfileData> load(String playerId) async {
    final pid = Variable.withString(playerId);

    // Nombres (incluye borrados: el historial debe seguir mostrando al rival).
    final names = {
      for (final p in await _db.select(_db.players).get()) p.id: p.nickname,
    };
    final decks = {
      for (final d in await _db.select(_db.decks).get()) d.id: d.name,
    };

    final matchRows = await _db.customSelect(
      'SELECT m.player1_id AS p1, m.player2_id AS p2, m.deck1_id AS d1, m.deck2_id AS d2, '
      'm.result AS res, m.games1 AS g1, m.games_draw AS gd, m.games2 AS g2, '
      'm.is_bye AS bye, m.is_third_place AS third, '
      'r.number AS rnum, r.phase AS phase, r.bracket_size AS bsize, '
      't.id AS tid, t.name AS tname, t.date AS tdate '
      'FROM matches m '
      'JOIN rounds r ON r.id = m.round_id '
      'JOIN tournaments t ON t.id = m.tournament_id '
      'WHERE (m.player1_id = ? OR m.player2_id = ?) '
      'AND m.deleted_at IS NULL AND t.deleted_at IS NULL '
      'ORDER BY t.date DESC, t.created_at DESC, r.number DESC',
      variables: [pid, pid],
    ).get();

    final history = <HistoryEntry>[];
    for (final r in matchRows) {
      final isP1 = r.read<String>('p1') == playerId;
      final oppId = isP1 ? r.read<String?>('p2') : r.read<String>('p1');
      final ownDeckId = isP1 ? r.read<String?>('d1') : r.read<String?>('d2');
      final oppDeckId = isP1 ? r.read<String?>('d2') : r.read<String?>('d1');
      final phase = RoundPhase.values.byName(r.read<String>('phase'));
      final (outcome, score) = outcomeFor(
        isPlayer1: isP1,
        isBye: r.read<bool>('bye'),
        result: MatchResult.values.byName(r.read<String>('res')),
        games1: r.read<int?>('g1'),
        gamesDraw: r.read<int?>('gd'),
        games2: r.read<int?>('g2'),
      );
      history.add(HistoryEntry(
        tournamentId: r.read<String>('tid'),
        tournamentName: r.read<String>('tname'),
        date: r.read<DateTime>('tdate'),
        phase: phase,
        phaseLabel: phaseLabel(
          phase: phase,
          roundNumber: r.read<int>('rnum'),
          bracketSize: r.read<int?>('bsize'),
          isThirdPlace: r.read<bool>('third'),
        ),
        outcome: outcome,
        score: score,
        ownDeck: ownDeckId == null ? null : decks[ownDeckId],
        opponentName: oppId == null ? null : (names[oppId] ?? '?'),
        opponentDeck: oppDeckId == null ? null : decks[oppDeckId],
      ));
    }

    final tournamentRows = await _db.customSelect(
      'SELECT t.id AS tid, t.name AS tname, t.date AS tdate, t.status AS status, '
      'tp.final_position AS pos, tp.dropped AS dropped, tp.deck_id AS deck '
      'FROM tournament_players tp JOIN tournaments t ON t.id = tp.tournament_id '
      'WHERE tp.player_id = ? AND tp.deleted_at IS NULL AND t.deleted_at IS NULL '
      'ORDER BY t.date DESC, t.created_at DESC',
      variables: [pid],
    ).get();

    final tournaments = [
      for (final r in tournamentRows)
        TournamentEntry(
          tournamentId: r.read<String>('tid'),
          name: r.read<String>('tname'),
          date: r.read<DateTime>('tdate'),
          finished: r.read<String>('status') == TournamentStatus.finished.name,
          finalPosition: r.read<int?>('pos'),
          dropped: r.read<bool>('dropped'),
          deck: r.read<String?>('deck') == null ? null : decks[r.read<String>('deck')],
        ),
    ];

    return PlayerProfileData(history: history, tournaments: tournaments);
  }
}

final playerProfileRepositoryProvider =
    Provider((ref) => PlayerProfileRepository(ref.watch(databaseProvider)));

final playerProfileProvider =
    StreamProvider.autoDispose.family<PlayerProfileData, String>((ref, playerId) {
  return ref.watch(playerProfileRepositoryProvider).watch(playerId);
});

final playerByIdProvider =
    StreamProvider.autoDispose.family<Player?, String>((ref, playerId) {
  return ref.watch(playersDaoProvider).watchById(playerId);
});

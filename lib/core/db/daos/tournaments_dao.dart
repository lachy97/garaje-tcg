import 'package:drift/drift.dart';

import '../../../features/tournaments/domain/game_score.dart';
import '../../../features/tournaments/domain/tournament_rules.dart';
import '../app_database.dart';
import '../tables.dart';

part 'tournaments_dao.g.dart';

/// Jugador inscrito con sus datos y mazo (para listas de inscripción).
class RegisteredPlayer {
  const RegisteredPlayer({required this.entry, required this.player, this.deck});
  final TournamentPlayer entry;
  final Player player;
  final Deck? deck;
}

/// Match a crear (lo produce el motor de pairings / el bracket del Top Cut).
class NewMatch {
  const NewMatch({
    required this.player1Id,
    this.player2Id,
    this.deck1Id,
    this.deck2Id,
    this.tableNumber,
    this.isThirdPlace = false,
  });

  final String player1Id;
  final String? player2Id; // null = BYE
  final String? deck1Id;
  final String? deck2Id;
  final int? tableNumber;
  final bool isThirdPlace;

  bool get isBye => player2Id == null;
}

@DriftAccessor(
    tables: [Tournaments, TournamentPlayers, Rounds, Matches, Players, Decks])
class TournamentsDao extends DatabaseAccessor<AppDatabase>
    with _$TournamentsDaoMixin {
  TournamentsDao(super.attachedDatabase);

  // ───────────────────────── Torneo ─────────────────────────

  Future<Tournament> createTournament({
    required String name,
    required DateTime date,
    required int swissRounds,
    int topCutSize = 0,
    bool hasThirdPlaceMatch = true,
    int roundMinutes = TournamentRules.defaultRoundMinutes,
    String game = kDefaultGame,
    String? notes,
  }) {
    if (swissRounds < TournamentRules.minSwissRounds ||
        swissRounds > TournamentRules.maxSwissRounds) {
      throw ArgumentError.value(swissRounds, 'swissRounds',
          'Debe estar entre ${TournamentRules.minSwissRounds} y ${TournamentRules.maxSwissRounds}');
    }
    return transaction(() async {
      final season = await attachedDatabase.seasonsDao.seasonFor(date, game: game);
      if (season.status == SeasonStatus.closed) {
        throw StateError('La temporada T${season.quarter} ${season.year} está cerrada: '
            'no se pueden crear torneos en esa fecha.');
      }
      return into(tournaments).insertReturning(TournamentsCompanion.insert(
        seasonId: season.id,
        game: Value(game),
        name: name.trim(),
        date: date,
        swissRounds: swissRounds,
        topCutSize: Value(topCutSize),
        hasThirdPlaceMatch: Value(hasThirdPlaceMatch),
        roundMinutes: Value(roundMinutes),
        notes: Value(notes),
      ));
    });
  }

  Stream<List<Tournament>> watchAll({String game = kDefaultGame}) {
    return (select(tournaments)
          ..where((t) => t.game.equals(game) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .watch();
  }

  Stream<Tournament?> watchById(String id) =>
      (select(tournaments)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<Tournament?> getById(String id) =>
      (select(tournaments)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Lanza [StateError] si el torneo es de una temporada CERRADA: sus torneos
  /// quedan de solo lectura (se reabre desde Modo administrador).
  Future<void> ensureEditable(String tournamentId) async {
    final row = await customSelect(
      'SELECT s.status AS st, s.year AS y, s.quarter AS q FROM tournaments t '
      'JOIN seasons s ON s.id = t.season_id WHERE t.id = ?',
      variables: [Variable.withString(tournamentId)],
      readsFrom: {tournaments, attachedDatabase.seasons},
    ).getSingleOrNull();
    if (row != null && row.read<String>('st') == SeasonStatus.closed.name) {
      throw StateError('La temporada T${row.read<int>('q')} ${row.read<int>('y')} está cerrada: '
          'sus torneos no se pueden cambiar. Se reabre desde Modo administrador.');
    }
  }

  /// true si el torneo es de una temporada cerrada (solo lectura).
  Stream<bool> watchIsLocked(String tournamentId) {
    return customSelect(
      'SELECT s.status AS st FROM tournaments t '
      'JOIN seasons s ON s.id = t.season_id WHERE t.id = ?',
      variables: [Variable.withString(tournamentId)],
      readsFrom: {tournaments, attachedDatabase.seasons},
    ).watchSingleOrNull().map((r) => r?.read<String>('st') == SeasonStatus.closed.name);
  }

  Future<void> updateSettings(
    String id, {
    String? name,
    int? swissRounds,
    int? topCutSize,
    bool? hasThirdPlaceMatch,
    int? roundMinutes,
  }) {
    return (update(tournaments)..where((t) => t.id.equals(id))).write(
      TournamentsCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        swissRounds: Value.absentIfNull(swissRounds),
        topCutSize: Value.absentIfNull(topCutSize),
        hasThirdPlaceMatch: Value.absentIfNull(hasThirdPlaceMatch),
        roundMinutes: Value.absentIfNull(roundMinutes),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Pone en marcha (o reinicia) el reloj de una ronda. null = lo detiene.
  Future<void> setRoundTimer(String roundId, DateTime? startedAt) {
    return (update(rounds)..where((r) => r.id.equals(roundId))).write(
      RoundsCompanion(
        timerStartedAt: Value(startedAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Borra el torneo (lógico) y retira sus puntos del ranking.
  Future<void> softDelete(String id) {
    final now = DateTime.now();
    return transaction(() async {
      await ensureEditable(id);
      // Borrado lógico también de sus puntos (listo para sincronizar).
      await (update(attachedDatabase.seasonResults)
            ..where((r) => r.tournamentId.equals(id)))
          .write(SeasonResultsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      await (update(tournaments)..where((t) => t.id.equals(id))).write(
        TournamentsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
    });
  }

  Future<void> setStatus(String id, TournamentStatus status) {
    return (update(tournaments)..where((t) => t.id.equals(id))).write(
      TournamentsCompanion(status: Value(status), updatedAt: Value(DateTime.now())),
    );
  }

  // ───────────────────────── Inscripción ─────────────────────────

  JoinedSelectStatement<HasResultSet, dynamic> _registeredQuery(String tournamentId) {
    return select(tournamentPlayers).join([
      innerJoin(players, players.id.equalsExp(tournamentPlayers.playerId)),
      leftOuterJoin(decks, decks.id.equalsExp(tournamentPlayers.deckId)),
    ])
      ..where(tournamentPlayers.tournamentId.equals(tournamentId) &
          tournamentPlayers.deletedAt.isNull())
      ..orderBy([OrderingTerm.asc(players.nickname.lower())]);
  }

  List<RegisteredPlayer> _mapRegistered(List<TypedResult> rows) => [
        for (final r in rows)
          RegisteredPlayer(
            entry: r.readTable(tournamentPlayers),
            player: r.readTable(players),
            deck: r.readTableOrNull(decks),
          ),
      ];

  Stream<List<RegisteredPlayer>> watchRegistered(String tournamentId) =>
      _registeredQuery(tournamentId).watch().map(_mapRegistered);

  Future<List<RegisteredPlayer>> registeredPlayers(String tournamentId) async =>
      _mapRegistered(await _registeredQuery(tournamentId).get());

  /// Inscribe (o reinscribe) a un jugador. [deckName] crea el mazo si no existe.
  Future<void> registerPlayer(
    String tournamentId,
    String playerId, {
    String? deckName,
    int lateRounds = 0,
  }) {
    return transaction(() async {
      await ensureEditable(tournamentId);
      final deckId = (deckName == null || deckName.trim().isEmpty)
          ? null
          : (await attachedDatabase.decksDao.findOrCreate(deckName)).id;
      final now = DateTime.now();
      await into(tournamentPlayers).insert(
        TournamentPlayersCompanion.insert(
          tournamentId: tournamentId,
          playerId: playerId,
          deckId: Value(deckId),
          lateRounds: Value(lateRounds),
        ),
        onConflict: DoUpdate(
          (old) => TournamentPlayersCompanion(
            deckId: Value(deckId),
            lateRounds: Value(lateRounds),
            dropped: const Value(false),
            dropRound: const Value(null),
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ),
          target: [tournamentPlayers.tournamentId, tournamentPlayers.playerId],
        ),
      );
    });
  }

  Future<void> unregisterPlayer(String tournamentId, String playerId) async {
    await ensureEditable(tournamentId);
    final now = DateTime.now();
    await (update(tournamentPlayers)
          ..where((t) =>
              t.tournamentId.equals(tournamentId) & t.playerId.equals(playerId)))
        .write(TournamentPlayersCompanion(
            deletedAt: Value(now), updatedAt: Value(now)));
  }

  Future<void> setPlayerDeck(
      String tournamentId, String playerId, String deckName) {
    return transaction(() async {
      await ensureEditable(tournamentId);
      final deck = await attachedDatabase.decksDao.findOrCreate(deckName);
      await (update(tournamentPlayers)
            ..where((t) =>
                t.tournamentId.equals(tournamentId) &
                t.playerId.equals(playerId)))
          .write(TournamentPlayersCompanion(
              deckId: Value(deck.id), updatedAt: Value(DateTime.now())));
    });
  }

  /// Marca si el jugador pagó el cover del torneo.
  Future<void> setPaid(String tournamentId, String playerId, bool paid) async {
    await ensureEditable(tournamentId);
    await (update(tournamentPlayers)
          ..where((t) =>
              t.tournamentId.equals(tournamentId) & t.playerId.equals(playerId)))
        .write(TournamentPlayersCompanion(
      paid: Value(paid),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Último mazo con el que jugó cada jugador: el de su inscripción en el
  /// torneo empezado más reciente (por fecha), sin contar [excludeTournamentId]
  /// ni torneos, inscripciones o mazos borrados.
  Future<Map<String, Deck>> lastDecks({String? excludeTournamentId}) async {
    final q = select(tournamentPlayers).join([
      innerJoin(tournaments, tournaments.id.equalsExp(tournamentPlayers.tournamentId)),
      innerJoin(decks, decks.id.equalsExp(tournamentPlayers.deckId)),
    ])
      ..where(tournamentPlayers.deletedAt.isNull() &
          tournaments.deletedAt.isNull() &
          decks.deletedAt.isNull() &
          tournaments.status.equalsValue(TournamentStatus.draft).not());
    if (excludeTournamentId != null) {
      q.where(tournaments.id.equals(excludeTournamentId).not());
    }
    final rows = [
      for (final r in await q.get())
        (r.readTable(tournamentPlayers), r.readTable(tournaments), r.readTable(decks)),
    ]..sort((a, b) {
        final byDate = b.$2.date.compareTo(a.$2.date);
        return byDate != 0 ? byDate : b.$2.createdAt.compareTo(a.$2.createdAt);
      });
    final out = <String, Deck>{};
    for (final (tp, _, deck) in rows) {
      out.putIfAbsent(tp.playerId, () => deck);
    }
    return out;
  }

  /// Retira a un jugador a partir de la ronda [afterRound] (no se empareja más).
  Future<void> dropPlayer(String tournamentId, String playerId, int afterRound) async {
    await ensureEditable(tournamentId);
    await (update(tournamentPlayers)
          ..where((t) =>
              t.tournamentId.equals(tournamentId) & t.playerId.equals(playerId)))
        .write(TournamentPlayersCompanion(
      dropped: const Value(true),
      dropRound: Value(afterRound),
      updatedAt: Value(DateTime.now()),
    ));
  }

  // ───────────────────────── Rondas y matches ─────────────────────────

  /// Crea una ronda con sus matches en una sola transacción.
  /// Los BYE se guardan ya reportados como victoria de player1.
  Future<Round> createRound({
    required String tournamentId,
    required int number,
    required RoundPhase phase,
    int? bracketSize,
    required List<NewMatch> pairings,
  }) {
    return transaction(() async {
      final round = await into(rounds).insertReturning(RoundsCompanion.insert(
        tournamentId: tournamentId,
        number: number,
        phase: phase,
        bracketSize: Value(bracketSize),
      ));
      final now = DateTime.now();
      await batch((b) => b.insertAll(matches, [
            for (final m in pairings)
              MatchesCompanion.insert(
                tournamentId: tournamentId,
                roundId: round.id,
                tableNumber: Value(m.tableNumber),
                player1Id: m.player1Id,
                player2Id: Value(m.player2Id),
                deck1Id: Value(m.deck1Id),
                deck2Id: Value(m.deck2Id),
                isBye: Value(m.isBye),
                isThirdPlace: Value(m.isThirdPlace),
                result: Value(m.isBye ? MatchResult.p1Win : MatchResult.pending),
                reportedAt: Value(m.isBye ? now : null),
                games1: Value(m.isBye ? GameScore.bye.p1 : null),
                gamesDraw: Value(m.isBye ? GameScore.bye.draws : null),
                games2: Value(m.isBye ? GameScore.bye.p2 : null),
              ),
          ]));
      await (update(tournaments)..where((t) => t.id.equals(tournamentId)))
          .write(TournamentsCompanion(
        currentRound: Value(number),
        status: Value(phase == RoundPhase.swiss
            ? TournamentStatus.swiss
            : TournamentStatus.topCut),
        updatedAt: Value(now),
      ));
      return round;
    });
  }

  Stream<List<Round>> watchRounds(String tournamentId) {
    return (select(rounds)
          ..where((r) => r.tournamentId.equals(tournamentId) & r.deletedAt.isNull())
          ..orderBy([(r) => OrderingTerm.asc(r.number)]))
        .watch();
  }

  Future<List<Round>> roundsOf(String tournamentId) {
    return (select(rounds)
          ..where((r) => r.tournamentId.equals(tournamentId) & r.deletedAt.isNull())
          ..orderBy([(r) => OrderingTerm.asc(r.number)]))
        .get();
  }

  Stream<List<Match>> watchMatchesOfRound(String roundId) {
    return (select(matches)
          ..where((m) => m.roundId.equals(roundId) & m.deletedAt.isNull())
          ..orderBy([
            (m) => OrderingTerm.asc(m.isBye), // BYE al final
            (m) => OrderingTerm.asc(m.tableNumber),
          ]))
        .watch();
  }

  /// Todos los matches del torneo (para standings y para evitar rematches).
  Future<List<Match>> matchesOfTournament(String tournamentId) {
    return (select(matches)
          ..where((m) => m.tournamentId.equals(tournamentId) & m.deletedAt.isNull()))
        .get();
  }

  Stream<List<Match>> watchMatchesOfTournament(String tournamentId) {
    return (select(matches)
          ..where((m) => m.tournamentId.equals(tournamentId) & m.deletedAt.isNull()))
        .watch();
  }

  /// Guarda el marcador (mejor de 3). El resultado del match se deriva de él.
  /// La validación por fase (sin empates en Top Cut) la hace el servicio.
  Future<void> reportScore(String matchId, GameScore score) {
    if (!score.isValid) {
      throw ArgumentError.value(score.toString(), 'score', 'Marcador no válido');
    }
    final now = DateTime.now();
    return (update(matches)..where((m) => m.id.equals(matchId))).write(
      MatchesCompanion(
        result: Value(score.result),
        games1: Value(score.p1),
        gamesDraw: Value(score.draws),
        games2: Value(score.p2),
        reportedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// Doble derrota (se acabó el tiempo): 0-0-0 y pierden los dos.
  Future<void> reportDoubleLoss(String matchId) {
    final now = DateTime.now();
    return (update(matches)..where((m) => m.id.equals(matchId))).write(
      MatchesCompanion(
        result: const Value(MatchResult.doubleLoss),
        games1: const Value(0),
        gamesDraw: const Value(0),
        games2: const Value(0),
        reportedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// Empate intencional (ID): empate 0-0-0, cada uno suma el punto del empate.
  Future<void> reportIntentionalDraw(String matchId) {
    final now = DateTime.now();
    return (update(matches)..where((m) => m.id.equals(matchId))).write(
      MatchesCompanion(
        result: const Value(MatchResult.draw),
        games1: const Value(0),
        gamesDraw: const Value(0),
        games2: const Value(0),
        reportedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// Borra el resultado (vuelve a pendiente), p. ej. si se reportó por error.
  Future<void> clearResult(String matchId) {
    return (update(matches)..where((m) => m.id.equals(matchId))).write(
      MatchesCompanion(
        result: const Value(MatchResult.pending),
        games1: const Value(null),
        gamesDraw: const Value(null),
        games2: const Value(null),
        reportedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<Match?> matchById(String id) =>
      (select(matches)..where((m) => m.id.equals(id))).getSingleOrNull();

  Future<void> closeRound(String roundId) {
    return (update(rounds)..where((r) => r.id.equals(roundId))).write(
      RoundsCompanion(
          status: const Value(RoundStatus.closed),
          updatedAt: Value(DateTime.now())),
    );
  }

  /// Deshace la última ronda: borra sus matches y la ronda, y reabre
  /// [previous] (null = no quedan rondas → vuelve a la inscripción).
  /// [leavingTopCut] = se deshace la 1ª ronda del Top Cut: se borran las
  /// posiciones Swiss guardadas al cerrarlo.
  Future<void> undoRound({
    required String tournamentId,
    required String roundId,
    required Round? previous,
    required bool leavingTopCut,
  }) {
    return transaction(() async {
      final now = DateTime.now();
      await (delete(matches)..where((m) => m.roundId.equals(roundId))).go();
      await (delete(rounds)..where((r) => r.id.equals(roundId))).go();
      if (previous != null) {
        await (update(rounds)..where((r) => r.id.equals(previous.id))).write(
          RoundsCompanion(status: const Value(RoundStatus.open), updatedAt: Value(now)),
        );
      }
      // Inscritos tarde: no pueden haberse perdido más rondas de las que quedan.
      final remaining = previous?.number ?? 0;
      // customUpdate (no customStatement) para que las pantallas se refresquen.
      await customUpdate(
        'UPDATE tournament_players SET late_rounds = ? '
        'WHERE tournament_id = ? AND late_rounds > ?',
        variables: [
          Variable.withInt(remaining),
          Variable.withString(tournamentId),
          Variable.withInt(remaining),
        ],
        updates: {tournamentPlayers},
        updateKind: UpdateKind.update,
      );
      if (leavingTopCut) {
        await (update(tournamentPlayers)
              ..where((tp) => tp.tournamentId.equals(tournamentId)))
            .write(TournamentPlayersCompanion(
                swissPosition: const Value(null), updatedAt: Value(now)));
      }
      await (update(tournaments)..where((t) => t.id.equals(tournamentId))).write(
        TournamentsCompanion(
          currentRound: Value(previous?.number ?? 0),
          status: Value(previous == null
              ? TournamentStatus.draft
              : previous.phase == RoundPhase.swiss
                  ? TournamentStatus.swiss
                  : TournamentStatus.topCut),
          updatedAt: Value(now),
        ),
      );
    });
  }

  /// Intercambia dos jugadores de la ronda actual (emparejamiento manual).
  /// [slotA]/[slotB]: 1 = jugador 1, 2 = jugador 2 de cada match. El mazo
  /// viaja con el jugador. Si uno de los dos matches es un BYE, el que entra
  /// recibe el BYE y el otro match queda pendiente.
  Future<void> swapPlayers({
    required Match a,
    required int slotA,
    required Match b,
    required int slotB,
  }) {
    return transaction(() async {
      await ensureEditable(a.tournamentId);
      final now = DateTime.now();
      final pa = slotA == 1 ? a.player1Id : a.player2Id!;
      final da = slotA == 1 ? a.deck1Id : a.deck2Id;
      final pb = slotB == 1 ? b.player1Id : b.player2Id!;
      final deckB = slotB == 1 ? b.deck1Id : b.deck2Id;
      MatchesCompanion put(int slot, String player, String? deck) => slot == 1
          ? MatchesCompanion(player1Id: Value(player), deck1Id: Value(deck), updatedAt: Value(now))
          : MatchesCompanion(player2Id: Value(player), deck2Id: Value(deck), updatedAt: Value(now));
      await (update(matches)..where((m) => m.id.equals(a.id))).write(put(slotA, pb, deckB));
      await (update(matches)..where((m) => m.id.equals(b.id))).write(put(slotB, pa, da));
    });
  }

  // ───────────────────────── Penalizaciones ─────────────────────────

  Future<void> addPenalty({
    required String tournamentId,
    required String playerId,
    required int round,
    required PenaltyKind kind,
    String? reason,
  }) async {
    await ensureEditable(tournamentId);
    final r = reason?.trim();
    await into(attachedDatabase.penalties).insert(PenaltiesCompanion.insert(
      tournamentId: tournamentId,
      playerId: playerId,
      round: Value(round),
      kind: kind,
      reason: Value(r == null || r.isEmpty ? null : r),
    ));
  }

  Future<void> deletePenalty(Penalty p) async {
    await ensureEditable(p.tournamentId);
    final now = DateTime.now();
    await (update(attachedDatabase.penalties)..where((x) => x.id.equals(p.id)))
        .write(PenaltiesCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }

  Stream<List<Penalty>> watchPenalties(String tournamentId) {
    final t = attachedDatabase.penalties;
    return (select(t)
          ..where((x) => x.tournamentId.equals(tournamentId) & x.deletedAt.isNull())
          ..orderBy([(x) => OrderingTerm.asc(x.round), (x) => OrderingTerm.asc(x.createdAt)]))
        .watch();
  }

  /// Penalizaciones de un jugador en todos los torneos (para su ficha).
  Stream<List<(Penalty, Tournament)>> watchPlayerPenalties(String playerId) {
    final p = attachedDatabase.penalties;
    return (select(p).join([innerJoin(tournaments, tournaments.id.equalsExp(p.tournamentId))])
          ..where(p.playerId.equals(playerId) &
              p.deletedAt.isNull() &
              tournaments.deletedAt.isNull())
          ..orderBy([OrderingTerm.desc(tournaments.date)]))
        .watch()
        .map((rows) => [for (final r in rows) (r.readTable(p), r.readTable(tournaments))]);
  }

  // ───────────────────────── Cierre ─────────────────────────

  /// Guarda posiciones Swiss (al terminar el Swiss, antes del Top Cut).
  Future<void> saveSwissPositions(
      String tournamentId, Map<String, int> positions) {
    return _writePositions(tournamentId, positions, swiss: true);
  }

  /// Finaliza el torneo: guarda posiciones finales y suma puntos al ranking
  /// de la temporada del torneo.
  Future<void> finishTournament(
      String tournamentId, Map<String, int> finalPositions) {
    return transaction(() async {
      final t = await (select(tournaments)
            ..where((x) => x.id.equals(tournamentId)))
          .getSingle();
      await _writePositions(tournamentId, finalPositions, swiss: false);
      await attachedDatabase.rankingDao.writeTournamentResults(
        seasonId: t.seasonId,
        tournamentId: tournamentId,
        topCutSize: t.topCutSize,
        finalPositions: finalPositions,
      );
      final now = DateTime.now();
      await (update(tournaments)..where((x) => x.id.equals(tournamentId)))
          .write(TournamentsCompanion(
        status: const Value(TournamentStatus.finished),
        finishedAt: Value(now),
        updatedAt: Value(now),
      ));
    });
  }

  Future<void> _writePositions(
      String tournamentId, Map<String, int> positions,
      {required bool swiss}) async {
    final now = DateTime.now();
    await batch((b) {
      for (final MapEntry(key: playerId, value: pos) in positions.entries) {
        b.update(
          tournamentPlayers,
          TournamentPlayersCompanion(
            swissPosition: swiss ? Value(pos) : const Value.absent(),
            finalPosition: swiss ? const Value.absent() : Value(pos),
            updatedAt: Value(now),
          ),
          where: (t) =>
              t.tournamentId.equals(tournamentId) & t.playerId.equals(playerId),
        );
      }
    });
  }
}

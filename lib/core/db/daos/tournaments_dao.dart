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
      await (delete(attachedDatabase.seasonResults)
            ..where((r) => r.tournamentId.equals(id)))
          .go();
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
  }) {
    return transaction(() async {
      final deckId = (deckName == null || deckName.trim().isEmpty)
          ? null
          : (await attachedDatabase.decksDao.findOrCreate(deckName)).id;
      final now = DateTime.now();
      await into(tournamentPlayers).insert(
        TournamentPlayersCompanion.insert(
          tournamentId: tournamentId,
          playerId: playerId,
          deckId: Value(deckId),
        ),
        onConflict: DoUpdate(
          (old) => TournamentPlayersCompanion(
            deckId: Value(deckId),
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

  Future<void> unregisterPlayer(String tournamentId, String playerId) {
    final now = DateTime.now();
    return (update(tournamentPlayers)
          ..where((t) =>
              t.tournamentId.equals(tournamentId) & t.playerId.equals(playerId)))
        .write(TournamentPlayersCompanion(
            deletedAt: Value(now), updatedAt: Value(now)));
  }

  Future<void> setPlayerDeck(
      String tournamentId, String playerId, String deckName) {
    return transaction(() async {
      final deck = await attachedDatabase.decksDao.findOrCreate(deckName);
      await (update(tournamentPlayers)
            ..where((t) =>
                t.tournamentId.equals(tournamentId) &
                t.playerId.equals(playerId)))
          .write(TournamentPlayersCompanion(
              deckId: Value(deck.id), updatedAt: Value(DateTime.now())));
    });
  }

  /// Retira a un jugador a partir de la ronda [afterRound] (no se empareja más).
  Future<void> dropPlayer(String tournamentId, String playerId, int afterRound) {
    return (update(tournamentPlayers)
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

  /// Borra la última ronda (p. ej. pairings generados por error).
  Future<void> deleteRound(String tournamentId, String roundId) {
    return transaction(() async {
      await (delete(matches)..where((m) => m.roundId.equals(roundId))).go();
      final round = await (select(rounds)..where((r) => r.id.equals(roundId)))
          .getSingle();
      await (delete(rounds)..where((r) => r.id.equals(roundId))).go();
      await (update(tournaments)..where((t) => t.id.equals(tournamentId)))
          .write(TournamentsCompanion(
        currentRound: Value(round.number - 1),
        updatedAt: Value(DateTime.now()),
      ));
    });
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

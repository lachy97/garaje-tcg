import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/tournaments_dao.dart';
import '../../../core/db/database_provider.dart';
import '../domain/game_score.dart';
import '../domain/models.dart';
import '../domain/swiss/standings_calculator.dart';
import '../domain/swiss/swiss_pairing_engine.dart';
import '../domain/top_cut/top_cut_bracket.dart';
import '../domain/tournament_rules.dart';

/// Orquesta el flujo del torneo: une la BD con los motores de dominio.
///
/// Flujo: inscripción → [generateNextSwissRound] × N → [startTopCut]
///        → [advanceTopCut] × … → torneo terminado (puntos al ranking).
class TournamentService {
  TournamentService(this._db, {SwissPairingEngine? engine})
      : _engine = engine ?? SwissPairingEngine();

  final AppDatabase _db;
  final SwissPairingEngine _engine;

  TournamentsDao get _dao => _db.tournamentsDao;

  // ───────────────────────── Lectura ─────────────────────────

  /// Standings Swiss actuales (solo cuentan rondas Swiss reportadas).
  Future<List<Standing>> standings(String tournamentId) async {
    final ctx = await _load(tournamentId);
    return StandingsCalculator.compute(
      players: ctx.swissPlayers,
      matches: ctx.swissRecords,
    );
  }

  /// Se recalcula cada vez que cambia un match del torneo.
  Stream<List<Standing>> watchStandings(String tournamentId) => _dao
      .watchMatchesOfTournament(tournamentId)
      .asyncMap((_) => standings(tournamentId));

  /// La ronda actual está completa (todos los resultados reportados).
  Future<bool> isCurrentRoundComplete(String tournamentId) async {
    final ctx = await _load(tournamentId);
    final current = ctx.currentRound;
    if (current == null) return true;
    return ctx.matchesOf(current).every((m) => m.result.isReported);
  }

  // ───────────────────────── Resultados ─────────────────────────

  /// Reporta un match al mejor de 3 (`J1 - Empates - J2`).
  /// Solo acepta los marcadores de [GameScore.allowed]; en Top Cut no hay 1-1-1.
  /// Se puede corregir mientras la ronda siga siendo la actual.
  Future<void> reportScore(String matchId, GameScore score) async {
    final m = await _dao.matchById(matchId);
    if (m == null) throw const TournamentException('Match no encontrado.');
    if (m.isBye) throw const TournamentException('El BYE no se reporta.');
    final ctx = await _load(m.tournamentId);
    final round = ctx.roundById[m.roundId]!;
    if (round.id != ctx.currentRound?.id) {
      throw const TournamentException(
          'Solo se pueden reportar o corregir resultados de la ronda actual.');
    }
    if (!score.isValid) {
      throw TournamentException(
          'Marcador $score no válido. Opciones: ${GameScore.allowed.join(', ')}.');
    }
    if (round.phase == RoundPhase.topCut && !score.isValidForTopCut) {
      throw const TournamentException('En el Top Cut no hay empates: debe haber un ganador.');
    }
    await _dao.reportScore(matchId, score);
  }

  Future<void> clearResult(String matchId) async {
    final m = await _dao.matchById(matchId);
    if (m == null || m.isBye) return;
    final ctx = await _load(m.tournamentId);
    if (m.roundId != ctx.currentRound?.id) {
      throw const TournamentException('Solo se pueden corregir resultados de la ronda actual.');
    }
    await _dao.clearResult(matchId);
  }

  // ───────────────────────── Configuración ─────────────────────────

  /// Cambia cuántas rondas Swiss se juegan antes del Top Cut.
  /// Solo durante la inscripción: al generar la ronda 1 la configuración queda fija.
  Future<void> setSwissRounds(String tournamentId, int rounds) async {
    final ctx = await _load(tournamentId);
    _ensureNotStarted(ctx.tournament);
    if (rounds < TournamentRules.minSwissRounds || rounds > TournamentRules.maxSwissRounds) {
      throw const TournamentException('Las rondas deben estar entre '
          '${TournamentRules.minSwissRounds} y ${TournamentRules.maxSwissRounds}.');
    }
    await _dao.updateSettings(tournamentId, swissRounds: rounds);
  }

  /// Cambia el tamaño del Top Cut (0 = sin Top). Solo durante la inscripción.
  Future<void> setTopCutSize(String tournamentId, int size) async {
    final ctx = await _load(tournamentId);
    _ensureNotStarted(ctx.tournament);
    if (size != 0 && !TournamentRules.topCutSizes.contains(size)) {
      throw TournamentException('Top Cut no válido: $size');
    }
    await _dao.updateSettings(tournamentId, topCutSize: size);
  }

  void _ensureNotStarted(Tournament t) {
    if (t.status != TournamentStatus.draft) {
      throw const TournamentException(
          'El torneo ya empezó: las rondas y el Top Cut no se pueden cambiar.');
    }
  }

  // ───────────────────────── Swiss ─────────────────────────

  Future<PairingOutcome> generateNextSwissRound(String tournamentId) async {
    final ctx = await _load(tournamentId);
    final t = ctx.tournament;
    if (t.status == TournamentStatus.topCut || t.status == TournamentStatus.finished) {
      throw const TournamentException('El Swiss ya terminó.');
    }
    if (ctx.swissRoundCount >= t.swissRounds) {
      throw const TournamentException(
          'Ya se jugaron todas las rondas Swiss. Pasa al Top Cut o finaliza.');
    }
    _ensureCurrentRoundComplete(ctx);

    if (t.status == TournamentStatus.draft) {
      // Antes de fijar la configuración, comprobar que el Top Cut elegido es posible.
      final active = ctx.swissPlayers.where((p) => !p.dropped).length;
      if (active < 2) {
        throw const TournamentException('Inscribe al menos 2 jugadores.');
      }
      if (t.topCutSize > active) {
        throw TournamentException('Hay $active jugadores: no alcanzan para un '
            'Top ${t.topCutSize}. Cambia el Top Cut antes de empezar.');
      }
    }

    final roundNumber = t.currentRound + 1;
    final outcome = _engine.pairRound(
      round: roundNumber,
      players: ctx.swissPlayers,
      previous: ctx.swissRecords,
    );

    await _db.transaction(() async {
      if (ctx.currentRound != null) await _dao.closeRound(ctx.currentRound!.id);
      await _dao.createRound(
        tournamentId: tournamentId,
        number: roundNumber,
        phase: RoundPhase.swiss,
        pairings: [
          for (final p in outcome.pairings)
            NewMatch(
              player1Id: p.player1Id,
              player2Id: p.player2Id,
              deck1Id: ctx.deckOf[p.player1Id],
              deck2Id: p.player2Id == null ? null : ctx.deckOf[p.player2Id],
              tableNumber: p.table,
            ),
        ],
      );
    });
    return outcome;
  }

  // ───────────────────────── Top Cut ─────────────────────────

  /// Cierra el Swiss: guarda posiciones Swiss y crea la primera ronda del Top Cut.
  /// Si el torneo no tiene Top Cut, lo finaliza directamente.
  Future<void> startTopCut(String tournamentId) async {
    final ctx = await _load(tournamentId);
    final t = ctx.tournament;
    if (t.status != TournamentStatus.swiss) {
      throw const TournamentException('El torneo no está en fase Swiss.');
    }
    if (ctx.swissRoundCount < t.swissRounds) {
      throw TournamentException(
          'Faltan rondas Swiss (${ctx.swissRoundCount}/${t.swissRounds}).');
    }
    _ensureCurrentRoundComplete(ctx);

    final table = StandingsCalculator.compute(
        players: ctx.swissPlayers, matches: ctx.swissRecords);
    final swissPositions = {for (final s in table) s.playerId: s.rank};

    if (t.topCutSize == 0) {
      await _db.transaction(() async {
        await _dao.closeRound(ctx.currentRound!.id);
        await _dao.saveSwissPositions(tournamentId, swissPositions);
        await _dao.finishTournament(tournamentId, swissPositions);
      });
      return;
    }

    final seeds = table.where((s) => !s.dropped).take(t.topCutSize).map((s) => s.playerId).toList();
    if (seeds.length < t.topCutSize) {
      throw TournamentException(
          'No hay suficientes jugadores activos para un Top ${t.topCutSize}.');
    }
    final first = TopCutBracket.firstRound(seeds);

    await _db.transaction(() async {
      await _dao.closeRound(ctx.currentRound!.id);
      await _dao.saveSwissPositions(tournamentId, swissPositions);
      await _createTopCutRound(ctx, t.currentRound + 1, first);
    });
  }

  /// Crea la siguiente ronda del Top Cut o, si se jugó la final, finaliza el torneo.
  /// Devuelve true si el torneo quedó terminado.
  Future<bool> advanceTopCut(String tournamentId) async {
    final ctx = await _load(tournamentId);
    final t = ctx.tournament;
    if (t.status != TournamentStatus.topCut) {
      throw const TournamentException('El torneo no está en Top Cut.');
    }
    _ensureCurrentRoundComplete(ctx);

    final topRounds = ctx.topCutBracketRounds(); // valida que no haya empates
    final next = TopCutBracket.nextRound(topRounds.last,
        thirdPlaceMatch: t.hasThirdPlaceMatch);

    if (next.isNotEmpty) {
      await _db.transaction(() async {
        await _dao.closeRound(ctx.currentRound!.id);
        await _createTopCutRound(ctx, t.currentRound + 1, next);
      });
      return false;
    }

    final swissOrder = StandingsCalculator.compute(
            players: ctx.swissPlayers, matches: ctx.swissRecords)
        .map((s) => s.playerId)
        .toList();
    final positions = TopCutBracket.finalPositions(
        rounds: topRounds, swissOrder: swissOrder);
    await _db.transaction(() async {
      await _dao.closeRound(ctx.currentRound!.id);
      await _dao.finishTournament(tournamentId, positions);
    });
    return true;
  }

  Future<void> _createTopCutRound(
      _Ctx ctx, int number, List<BracketMatch> matches) {
    final mainCount = matches.where((m) => !m.isThirdPlace).length;
    return _dao.createRound(
      tournamentId: ctx.tournament.id,
      number: number,
      phase: RoundPhase.topCut,
      bracketSize: mainCount * 2,
      pairings: [
        for (final m in matches)
          NewMatch(
            player1Id: m.player1Id,
            player2Id: m.player2Id,
            deck1Id: ctx.deckOf[m.player1Id],
            deck2Id: ctx.deckOf[m.player2Id],
            tableNumber: m.isThirdPlace ? mainCount + 1 : m.slot,
            isThirdPlace: m.isThirdPlace,
          ),
      ],
    );
  }

  void _ensureCurrentRoundComplete(_Ctx ctx) {
    final current = ctx.currentRound;
    if (current == null) return;
    final pending = ctx.matchesOf(current).where((m) => !m.result.isReported).length;
    if (pending > 0) {
      throw TournamentException(
          'Faltan $pending resultado(s) de la ronda ${current.number}.');
    }
  }

  // ───────────────────────── Carga ─────────────────────────

  Future<_Ctx> _load(String tournamentId) async {
    final t = await _dao.getById(tournamentId);
    if (t == null) throw const TournamentException('Torneo no encontrado.');
    final registered = await _dao.registeredPlayers(tournamentId);
    final rounds = await _dao.roundsOf(tournamentId);
    final matches = await _dao.matchesOfTournament(tournamentId);
    return _Ctx(t, registered, rounds, matches);
  }
}

/// Foto del torneo cargada de la BD para una operación.
class _Ctx {
  _Ctx(this.tournament, this.registered, this.rounds, this.matches)
      : roundById = {for (final r in rounds) r.id: r};

  final Tournament tournament;
  final List<RegisteredPlayer> registered;
  final List<Round> rounds;
  final List<Match> matches;
  final Map<String, Round> roundById;

  late final Map<String, String?> deckOf = {
    for (final r in registered) r.player.id: r.entry.deckId,
  };

  late final List<SwissPlayer> swissPlayers = [
    for (final r in registered)
      SwissPlayer(r.player.id, dropped: r.entry.dropped, dropRound: r.entry.dropRound),
  ];

  List<Round> get swissRounds =>
      rounds.where((r) => r.phase == RoundPhase.swiss).toList();

  int get swissRoundCount => swissRounds.length;

  Round? get currentRound => rounds.isEmpty ? null : rounds.last;

  List<Match> matchesOf(Round r) => matches.where((m) => m.roundId == r.id).toList();

  late final List<MatchRecord> swissRecords = [
    for (final m in matches)
      if (roundById[m.roundId]?.phase == RoundPhase.swiss)
        MatchRecord(
          round: roundById[m.roundId]!.number,
          player1Id: m.player1Id,
          player2Id: m.player2Id,
          result: m.result,
          games1: m.games1,
          gamesDraw: m.gamesDraw,
          games2: m.games2,
        ),
  ];

  List<List<BracketMatch>> topCutBracketRounds() => [
        for (final r in rounds.where((r) => r.phase == RoundPhase.topCut))
          [
            for (final m in matchesOf(r))
              BracketMatch(
                // la mesa del 3er puesto es mainCount+1; su slot real no importa
                slot: m.tableNumber ?? 0,
                player1Id: m.player1Id,
                player2Id: m.player2Id!,
                isThirdPlace: m.isThirdPlace,
                result: m.result,
              ),
          ],
      ];
}

final tournamentServiceProvider =
    Provider((ref) => TournamentService(ref.watch(databaseProvider)));

final standingsProvider =
    StreamProvider.family<List<Standing>, String>((ref, tournamentId) {
  return ref.watch(tournamentServiceProvider).watchStandings(tournamentId);
});

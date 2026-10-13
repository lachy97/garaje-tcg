import 'package:drift/drift.dart' show Variable;
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
  /// También con las inscripciones (drops, inscripción tardía).
  Stream<List<Standing>> watchStandings(String tournamentId) => _db
      .customSelect('SELECT COUNT(*) AS c FROM matches WHERE tournament_id = ?',
          variables: [Variable.withString(tournamentId)],
          readsFrom: {_db.matches, _db.tournamentPlayers})
      .watch()
      .asyncMap((_) => standings(tournamentId));

  /// La ronda actual está completa (todos los resultados reportados).
  Future<bool> isCurrentRoundComplete(String tournamentId) async {
    final ctx = await _load(tournamentId);
    final current = ctx.currentRound;
    if (current == null) return true;
    return ctx.matchesOf(current).every((m) => m.result.isReported);
  }

  // ───────────────────────── Resultados ─────────────────────────

  /// true si los resultados de [round] se pueden poner o corregir:
  /// - la ronda actual, mientras el torneo no haya terminado;
  /// - una ronda Swiss anterior, mientras el torneo siga en el Swiss (la
  ///   clasificación se recalcula; los cruces ya hechos no cambian).
  static bool canEditResults(Tournament t, Round round, {required bool isCurrent}) {
    if (t.status == TournamentStatus.finished) return false;
    if (isCurrent) return true;
    return round.phase == RoundPhase.swiss && t.status == TournamentStatus.swiss;
  }

  void _ensureResultEditable(_Ctx ctx, Round round) {
    if (ctx.tournament.status == TournamentStatus.finished) {
      throw const TournamentException('El torneo ya terminó: no se pueden cambiar resultados.');
    }
    if (!canEditResults(ctx.tournament, round, isCurrent: round.id == ctx.currentRound?.id)) {
      throw const TournamentException(
          'Esa ronda ya no se puede corregir: el Swiss terminó o es una ronda anterior del Top Cut.');
    }
  }

  /// Reporta un match al mejor de 3 (`J1 - Empates - J2`).
  /// Solo acepta los marcadores de [GameScore.allowed]; en Top Cut no hay 1-1-1.
  /// Ver [canEditResults] para saber qué rondas se pueden corregir.
  Future<void> reportScore(String matchId, GameScore score) async {
    final m = await _dao.matchById(matchId);
    if (m == null) throw const TournamentException('Match no encontrado.');
    if (m.isBye) throw const TournamentException('El BYE no se reporta.');
    final ctx = await _load(m.tournamentId);
    await _dao.ensureEditable(m.tournamentId);
    final round = ctx.roundById[m.roundId]!;
    _ensureResultEditable(ctx, round);
    if (!score.isValid) {
      throw TournamentException(
          'Marcador $score no válido. Opciones: ${GameScore.allowed.join(', ')}.');
    }
    if (round.phase == RoundPhase.topCut && !score.isValidForTopCut) {
      throw const TournamentException('En el Top Cut no hay empates: debe haber un ganador.');
    }
    await _dao.reportScore(matchId, score);
  }

  /// Doble derrota: se acabó el tiempo y los dos pierden (0-0-0). Solo en Swiss.
  Future<void> reportDoubleLoss(String matchId) async {
    final m = await _dao.matchById(matchId);
    if (m == null) throw const TournamentException('Match no encontrado.');
    if (m.isBye) throw const TournamentException('El BYE no se reporta.');
    final ctx = await _load(m.tournamentId);
    await _dao.ensureEditable(m.tournamentId);
    final round = ctx.roundById[m.roundId]!;
    _ensureResultEditable(ctx, round);
    if (round.phase == RoundPhase.topCut) {
      throw const TournamentException(
          'En el Top Cut no puede haber doble derrota: debe haber un ganador.');
    }
    await _dao.reportDoubleLoss(matchId);
  }

  /// Empate intencional (ID): los dos jugadores acuerdan empatar. Solo en Swiss.
  Future<void> reportIntentionalDraw(String matchId) async {
    final m = await _dao.matchById(matchId);
    if (m == null) throw const TournamentException('Match no encontrado.');
    if (m.isBye) throw const TournamentException('El BYE no se reporta.');
    final ctx = await _load(m.tournamentId);
    await _dao.ensureEditable(m.tournamentId);
    final round = ctx.roundById[m.roundId]!;
    _ensureResultEditable(ctx, round);
    if (round.phase == RoundPhase.topCut) {
      throw const TournamentException(
          'En el Top Cut no puede haber empate intencional: debe haber un ganador.');
    }
    await _dao.reportIntentionalDraw(matchId);
  }

  /// Vuelve un match a pendiente. Solo en la ronda actual (una ronda cerrada
  /// no puede quedar con resultados pendientes).
  Future<void> clearResult(String matchId) async {
    final m = await _dao.matchById(matchId);
    if (m == null || m.isBye) return;
    final ctx = await _load(m.tournamentId);
    await _dao.ensureEditable(m.tournamentId);
    if (ctx.tournament.status == TournamentStatus.finished) {
      throw const TournamentException('El torneo ya terminó: no se pueden cambiar resultados.');
    }
    if (m.roundId != ctx.currentRound?.id) {
      throw const TournamentException(
          'En una ronda cerrada se puede cambiar el resultado, pero no dejarlo pendiente.');
    }
    await _dao.clearResult(matchId);
  }


  // ───────────────────────── Configuración ─────────────────────────

  /// Cambia cuántas rondas Swiss se juegan antes del Top Cut.
  /// Solo durante la inscripción: al generar la ronda 1 la configuración queda fija.
  Future<void> setSwissRounds(String tournamentId, int rounds) async {
    final ctx = await _load(tournamentId);
    await _dao.ensureEditable(tournamentId);
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
    await _dao.ensureEditable(tournamentId);
    _ensureNotStarted(ctx.tournament);
    if (size != 0 && !TournamentRules.topCutSizes.contains(size)) {
      throw TournamentException('Top Cut no válido: $size');
    }
    await _dao.updateSettings(tournamentId, topCutSize: size);
  }

  /// Cambia el tiempo por ronda. Solo durante la inscripción.
  Future<void> setRoundMinutes(String tournamentId, int minutes) async {
    final ctx = await _load(tournamentId);
    await _dao.ensureEditable(tournamentId);
    _ensureNotStarted(ctx.tournament);
    if (minutes < TournamentRules.minRoundMinutes ||
        minutes > TournamentRules.maxRoundMinutes) {
      throw const TournamentException('El tiempo por ronda debe estar entre '
          '${TournamentRules.minRoundMinutes} y ${TournamentRules.maxRoundMinutes} min.');
    }
    await _dao.updateSettings(tournamentId, roundMinutes: minutes);
  }

  /// Inicia (o reinicia) el reloj de la ronda actual. El tiempo solo avisa:
  /// los resultados los pone siempre el organizador.
  Future<void> startRoundTimer(String roundId) => _dao.setRoundTimer(roundId, DateTime.now());

  /// Detiene el reloj (vuelve a "sin iniciar").
  Future<void> stopRoundTimer(String roundId) => _dao.setRoundTimer(roundId, null);

  void _ensureNotStarted(Tournament t) {
    if (t.status != TournamentStatus.draft) {
      throw const TournamentException(
          'El torneo ya empezó: las rondas y el Top Cut no se pueden cambiar.');
    }
  }

  // ───────────────────────── Swiss ─────────────────────────

  Future<PairingOutcome> generateNextSwissRound(String tournamentId) async {
    final ctx = await _load(tournamentId);
    await _dao.ensureEditable(tournamentId);
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

  /// Emparejamiento manual: intercambia dos jugadores de la ronda Swiss
  /// actual, en mesas aún sin resultado (el BYE se puede intercambiar).
  /// Devuelve avisos (cruces repetidos, segundo BYE) para mostrarlos.
  Future<List<String>> swapPlayers({
    required String matchIdA,
    required int slotA,
    required String matchIdB,
    required int slotB,
    Map<String, String> names = const {},
  }) async {
    final a = await _dao.matchById(matchIdA);
    final b = await _dao.matchById(matchIdB);
    if (a == null || b == null) throw const TournamentException('Match no encontrado.');
    final ctx = await _load(a.tournamentId);
    await _dao.ensureEditable(a.tournamentId);
    final current = ctx.currentRound;
    if (ctx.tournament.status != TournamentStatus.swiss ||
        current == null ||
        current.phase != RoundPhase.swiss) {
      throw const TournamentException('Solo se pueden cambiar cruces en una ronda Swiss en juego.');
    }
    if (a.roundId != current.id || b.roundId != current.id) {
      throw const TournamentException('Solo se pueden cambiar cruces de la ronda actual.');
    }
    if (a.id == b.id) {
      throw const TournamentException('Elige jugadores de mesas distintas.');
    }
    for (final (m, slot) in [(a, slotA), (b, slotB)]) {
      if (!m.isBye && m.result.isReported) {
        throw TournamentException(
            'La mesa ${m.tableNumber ?? ''} ya tiene resultado: bórralo antes de cambiar el cruce.');
      }
      if (m.isBye && slot != 1) throw const TournamentException('El BYE no tiene rival.');
    }

    String playerAt(Match m, int slot) => slot == 1 ? m.player1Id : m.player2Id!;
    final pa = playerAt(a, slotA), pb = playerAt(b, slotB);
    // Cómo quedan las dos mesas.
    String? other(Match m, int slot) => m.isBye ? null : (slot == 1 ? m.player2Id : m.player1Id);
    final newA = (pb, other(a, slotA));
    final newB = (pa, other(b, slotB));

    final previous = ctx.swissRecords.where((r) => r.round < current.number);
    bool played(String x, String y) => previous.any((r) =>
        (r.player1Id == x && r.player2Id == y) || (r.player1Id == y && r.player2Id == x));
    bool hadBye(String x) => previous.any((r) => r.isBye && r.player1Id == x);
    String n(String id) => names[id] ?? '?';
    final warnings = <String>[
      for (final (p, q) in [newA, newB])
        if (q == null && hadBye(p))
          '${n(p)} ya tuvo BYE'
        else if (q != null && played(p, q))
          '${n(p)} y ${n(q)} ya jugaron',
    ];
    await _dao.swapPlayers(a: a, slotA: slotA, b: b, slotB: slotB);
    return warnings;
  }

  /// Inscripción tardía con el Swiss empezado: cada ronda ya creada cuenta como
  /// derrota 0-2 sin rival. Entran a emparejarse desde la siguiente ronda.
  Future<void> registerLate(String tournamentId, Iterable<String> playerIds) async {
    final ctx = await _load(tournamentId);
    await _dao.ensureEditable(tournamentId);
    if (ctx.tournament.status != TournamentStatus.swiss) {
      throw const TournamentException('La inscripción tardía es solo durante el Swiss.');
    }
    final missed = ctx.tournament.currentRound;
    if (missed >= ctx.tournament.swissRounds) {
      throw const TournamentException('Ya no quedan rondas Swiss por jugar.');
    }
    for (final id in playerIds) {
      await _dao.registerPlayer(tournamentId, id, lateRounds: missed);
    }
  }

  /// Deshace la ronda actual: borra sus cruces y resultados y vuelve a abrir
  /// la anterior. Si era la 1ª del Top Cut, el torneo vuelve al Swiss; si era
  /// la ronda 1, vuelve a la inscripción. No se puede en un torneo terminado.
  Future<void> undoLastRound(String tournamentId) async {
    final ctx = await _load(tournamentId);
    await _dao.ensureEditable(tournamentId);
    final t = ctx.tournament;
    if (t.status == TournamentStatus.finished) {
      throw const TournamentException('El torneo ya terminó: no se puede deshacer.');
    }
    final current = ctx.currentRound;
    if (current == null) throw const TournamentException('Aún no hay rondas.');
    final previous = ctx.rounds.length > 1 ? ctx.rounds[ctx.rounds.length - 2] : null;
    await _dao.undoRound(
      tournamentId: tournamentId,
      roundId: current.id,
      previous: previous,
      leavingTopCut:
          current.phase == RoundPhase.topCut && previous?.phase != RoundPhase.topCut,
    );
  }

  // ───────────────────────── Top Cut ─────────────────────────

  /// Cierra el Swiss: guarda posiciones Swiss y crea la primera ronda del Top Cut.
  /// Si el torneo no tiene Top Cut, lo finaliza directamente.
  Future<void> startTopCut(String tournamentId) async {
    final ctx = await _load(tournamentId);
    await _dao.ensureEditable(tournamentId);
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

    // Con drops pueden quedar menos activos que el Top elegido: se reduce el
    // cuadro en vez de bloquear el torneo.
    final active = table.where((s) => !s.dropped).toList();
    final size = TournamentRules.effectiveTopCut(t.topCutSize, active.length);

    if (size == 0) {
      await _db.transaction(() async {
        await _dao.closeRound(ctx.currentRound!.id);
        await _dao.saveSwissPositions(tournamentId, swissPositions);
        if (t.topCutSize != 0) await _dao.updateSettings(tournamentId, topCutSize: 0);
        await _dao.finishTournament(tournamentId, swissPositions);
      });
      return;
    }

    final seeds = active.take(size).map((s) => s.playerId).toList();
    final first = TopCutBracket.firstRound(seeds);

    await _db.transaction(() async {
      await _dao.closeRound(ctx.currentRound!.id);
      await _dao.saveSwissPositions(tournamentId, swissPositions);
      if (size != t.topCutSize) await _dao.updateSettings(tournamentId, topCutSize: size);
      await _createTopCutRound(ctx, t.currentRound + 1, first);
    });
  }

  /// Crea la siguiente ronda del Top Cut o, si se jugó la final, finaliza el torneo.
  /// Devuelve true si el torneo quedó terminado.
  Future<bool> advanceTopCut(String tournamentId) async {
    final ctx = await _load(tournamentId);
    await _dao.ensureEditable(tournamentId);
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
      SwissPlayer(r.player.id,
          dropped: r.entry.dropped,
          dropRound: r.entry.dropRound,
          lateLosses: r.entry.lateRounds),
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

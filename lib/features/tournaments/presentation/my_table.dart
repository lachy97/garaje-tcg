import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/database_provider.dart';
import 'table_actions.dart';

/// Mi partida de la ronda actual en un torneo en juego.
class MyTableInfo {
  const MyTableInfo({
    required this.tournamentId,
    required this.tournamentName,
    required this.roundLabel,
    required this.table,
    required this.bye,
    required this.opponent,
    required this.opponentDeck,
    required this.score,
    required this.timerStartedAt,
    required this.roundMinutes,
    required this.matchId,
    required this.iAmP1,
    required this.topCut,
    this.extraMinutes = 0,
    this.playerId,
    this.opponentId,
  });

  /// Yo y mi rival (para el historial entre los dos).
  final String? playerId;
  final String? opponentId;

  /// Tiempo extra que dio el juez a esta mesa (ya sumado en [roundMinutes]).
  final int extraMinutes;

  final String matchId;

  /// Soy el jugador 1 de la mesa (los marcadores se guardan desde él).
  final bool iAmP1;

  /// Ronda del Top Cut (sin empates).
  final bool topCut;

  final String tournamentId;
  final String tournamentName;
  final String roundLabel;
  final int? table;
  final bool bye;
  final String? opponent;
  final String? opponentDeck;

  /// Marcador visto desde mí ("2-1"), null si aún no hay resultado.
  final String? score;
  final DateTime? timerStartedAt;
  final int roundMinutes;
}

String _round(String phase, int number, int? bracket, bool third) {
  if (third) return '3.er puesto';
  if (phase == 'swiss') return 'Ronda $number';
  return switch (bracket) {
    2 => 'Final',
    4 => 'Semis',
    8 => 'Cuartos',
    final n? => 'Top $n',
    null => 'Top Cut',
  };
}

/// Mi mesa en la última ronda de cada torneo en juego donde estoy inscrito.
final myTablesProvider = StreamProvider.autoDispose.family<List<MyTableInfo>, String>((ref, playerId) {
  final db = ref.watch(databaseProvider);
  final me = Variable.withString(playerId);
  return db
      .customSelect(
        'SELECT t.id AS tid, t.name AS tname, t.round_minutes AS rm, m.id AS mid, '
        'r.number AS rnum, r.phase AS rphase, r.bracket_size AS rbs, r.timer_started_at AS rts, '
        'm.table_number AS tbl, m.is_bye AS bye, m.result AS res, m.is_third_place AS third, '
        'm.extra_minutes AS ex, '
        'm.player1_id AS p1, m.games1 AS g1, m.games_draw AS gd, m.games2 AS g2, '
        'op.nickname AS opn, od.name AS opdeck, op.id AS opid '
        'FROM matches m '
        'JOIN rounds r ON r.id = m.round_id '
        'JOIN tournaments t ON t.id = m.tournament_id '
        'LEFT JOIN players op ON op.id = CASE WHEN m.player1_id = ?1 THEN m.player2_id ELSE m.player1_id END '
        'LEFT JOIN decks od ON od.id = CASE WHEN m.player1_id = ?1 THEN m.deck2_id ELSE m.deck1_id END '
        "WHERE (m.player1_id = ?1 OR m.player2_id = ?1) AND t.status IN ('swiss', 'topCut') "
        'AND t.deleted_at IS NULL AND r.deleted_at IS NULL AND m.deleted_at IS NULL '
        'AND r.number = (SELECT MAX(r2.number) FROM rounds r2 '
        '  WHERE r2.tournament_id = t.id AND r2.deleted_at IS NULL) '
        'ORDER BY t.date DESC',
        variables: [me],
        readsFrom: {db.matches, db.rounds, db.tournaments, db.players, db.decks},
      )
      .watch()
      .map((rows) => [
            for (final r in rows)
              () {
                final iAmP1 = r.read<String>('p1') == playerId;
                final g1 = r.readNullable<int>('g1');
                final gd = r.readNullable<int>('gd') ?? 0;
                final g2 = r.readNullable<int>('g2');
                final res = r.read<String>('res');
                String? score;
                if (res == 'doubleLoss') {
                  score = 'Doble derrota';
                } else if (res != 'pending' && g1 != null && g2 != null) {
                  final mine = iAmP1 ? g1 : g2;
                  final theirs = iAmP1 ? g2 : g1;
                  score = gd > 0 ? '$mine-$gd-$theirs' : '$mine-$theirs';
                  if (mine + theirs + gd == 0) score = 'Empate (ID)';
                }
                return MyTableInfo(
                  tournamentId: r.read<String>('tid'),
                  tournamentName: r.read<String>('tname'),
                  roundLabel: _round(r.read<String>('rphase'), r.read<int>('rnum'),
                      r.readNullable<int>('rbs'), r.read<bool>('third')),
                  table: r.readNullable<int>('tbl'),
                  bye: r.read<bool>('bye'),
                  opponent: r.readNullable<String>('opn'),
                  opponentDeck: r.readNullable<String>('opdeck'),
                  score: score,
                  timerStartedAt: r.readNullable<DateTime>('rts'),
                  roundMinutes: r.read<int>('rm') + r.read<int>('ex'),
                  extraMinutes: r.read<int>('ex'),
                  matchId: r.read<String>('mid'),
                  iAmP1: iAmP1,
                  topCut: r.read<String>('rphase') != 'swiss',
                  playerId: playerId,
                  opponentId: r.readNullable<String>('opid'),
                );
              }(),
          ]);
});

/// Historial entre dos jugadores (partidas con resultado, sin la actual).
class HeadToHead {
  const HeadToHead(this.wins, this.losses, this.draws, this.last);

  final int wins;
  final int losses;
  final int draws;

  /// Resultado de la última vez, visto desde mí: 'win', 'loss', 'draw' (null: nunca).
  final String? last;

  int get played => wins + losses + draws;
}

/// Clave: "yo|rival|partida actual".
final headToHeadProvider = StreamProvider.autoDispose.family<HeadToHead, String>((ref, key) {
  final [me, op, current] = key.split('|');
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        "SELECT m.player1_id AS p1, m.result AS res FROM matches m "
        'JOIN tournaments t ON t.id = m.tournament_id '
        'JOIN rounds r ON r.id = m.round_id '
        'WHERE ((m.player1_id = ?1 AND m.player2_id = ?2) OR (m.player1_id = ?2 AND m.player2_id = ?1)) '
        "AND m.id <> ?3 AND m.result <> 'pending' AND m.is_bye = 0 "
        'AND m.deleted_at IS NULL AND t.deleted_at IS NULL AND r.deleted_at IS NULL '
        'ORDER BY t.date, r.number',
        variables: [Variable.withString(me), Variable.withString(op), Variable.withString(current)],
        readsFrom: {db.matches, db.tournaments, db.rounds},
      )
      .watch()
      .map((rows) {
    var w = 0, l = 0, d = 0;
    String? last;
    for (final r in rows) {
      final iAmP1 = r.read<String>('p1') == me;
      final res = r.read<String>('res');
      final out = switch (res) {
        'p1Win' => iAmP1 ? 'win' : 'loss',
        'p2Win' => iAmP1 ? 'loss' : 'win',
        'doubleLoss' => 'loss',
        _ => 'draw',
      };
      switch (out) {
        case 'win':
          w++;
        case 'loss':
          l++;
        default:
          d++;
      }
      last = out;
    }
    return HeadToHead(w, l, d, last);
  });
});

/// "Contra Leo: 2-1 · la última vez ganaste" (o primera vez).
class HeadToHeadLine extends ConsumerWidget {
  const HeadToHeadLine({super.key, required this.info});

  final MyTableInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = info.playerId;
    final op = info.opponentId;
    if (me == null || op == null || info.bye) return const SizedBox.shrink();
    final h = ref.watch(headToHeadProvider('$me|$op|${info.matchId}')).value;
    if (h == null) return const SizedBox.shrink();
    final text = h.played == 0
        ? 'Primera vez que se enfrentan'
        : 'Historial: ${h.wins}-${h.losses}${h.draws > 0 ? '-${h.draws}' : ''} · la última vez '
            '${switch (h.last) {
              'win' => 'ganaste',
              'loss' => 'perdiste',
              _ => 'empataron',
            }}';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.history, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta fija arriba en Torneos: ronda, mesa, rival, su mazo y el tiempo.
class MyTablesSection extends ConsumerWidget {
  const MyTablesSection({super.key, required this.playerId});

  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myTablesProvider(playerId)).value ?? const <MyTableInfo>[];
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Mi mesa ahora'),
        for (final t in list) _MyTableCard(info: t),
      ],
    );
  }
}

class _MyTableCard extends StatelessWidget {
  const _MyTableCard({required this.info});

  final MyTableInfo info;

  @override
  Widget build(BuildContext context) {
    final i = info;
    final big = TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w900,
      color: AppColors.neonBright,
      shadows: AppColors.textGlow(blur: 10),
    );
    return Semantics(
      container: true,
      label: '${i.tournamentName}, ${i.roundLabel}. '
          '${i.bye ? 'Tienes BYE' : 'Mesa ${i.table ?? '?'} contra ${i.opponent ?? '?'}'}',
      child: NeonCard(
        glow: true,
        onTap: () => context.push('/torneos/${i.tournamentId}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${i.tournamentName} · ${i.roundLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (i.bye)
              Text('BYE · ganas 2-0', style: big)
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      Text('MESA', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, letterSpacing: 1.2)),
                      Text('${i.table ?? '?'}', style: big),
                    ],
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('contra', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        Text(i.opponent ?? '?',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        Text(i.opponentDeck ?? 'Sin mazo',
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        HeadToHeadLine(info: i),
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    i.score == null
                        ? 'Sin resultado todavía${i.extraMinutes > 0 ? ' · +${i.extraMinutes} min del juez' : ''}'
                        : 'Resultado: ${i.score}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: i.score == null ? AppColors.textSecondary : AppColors.neon),
                  ),
                ),
                if (i.timerStartedAt != null && i.score == null)
                  RoundCountdown(start: i.timerStartedAt!, minutes: i.roundMinutes),
              ],
            ),
            // Reportar / confirmar el resultado, llamar al juez, drop.
            TableActions(info: i),
          ],
        ),
      ),
    );
  }
}

/// Tiempo que queda de ronda (se actualiza cada segundo).
class RoundCountdown extends StatefulWidget {
  const RoundCountdown({super.key, required this.start, required this.minutes, this.fontSize = 14});

  final DateTime start;
  final int minutes;
  final double fontSize;

  @override
  State<RoundCountdown> createState() => _RoundCountdownState();
}

class _RoundCountdownState extends State<RoundCountdown> {
  late final Timer _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = Duration(minutes: widget.minutes) - DateTime.now().difference(widget.start);
    final over = left.isNegative;
    final s = left.inSeconds.abs();
    final text = '${over ? '+' : ''}${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
    final color = over
        ? AppColors.loss
        : left.inMinutes < 5
            ? AppColors.draw
            : AppColors.neon;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(over ? Icons.alarm : Icons.timer_outlined, size: widget.fontSize * 1.25, color: color),
        SizedBox(width: widget.fontSize * 0.3),
        Text(text,
            style: TextStyle(
                fontSize: widget.fontSize,
                fontWeight: FontWeight.w900,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    );
  }
}

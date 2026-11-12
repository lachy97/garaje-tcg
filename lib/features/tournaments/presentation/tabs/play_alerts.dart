import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/brand.dart';
import '../../../../app/widgets/common.dart';
import '../../../../core/auth/account.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/play/play.dart';
import '../../../../core/sync/sync_service.dart';
import '../../application/tournament_service.dart';

/// Avisos desde los móviles de los jugadores, en la ronda actual del
/// organizador: llamadas al juez, resultados que no coinciden o sin
/// confirmar, y drops pedidos. Los confirmados por los dos y los drops se
/// aplican solos al sincronizar.
class PlayAlertsPanel extends ConsumerStatefulWidget {
  const PlayAlertsPanel({
    super.key,
    required this.tournament,
    required this.matches,
    required this.names,
    this.asJudge = false,
  });

  /// Teléfono de un juez: los resultados se envían al servidor (los pone el
  /// teléfono del organizador al sincronizar).
  final bool asJudge;

  final Tournament tournament;

  /// Partidas de la ronda actual (para la mesa de cada aviso).
  final List<Match> matches;
  final Map<String, String> names;

  @override
  ConsumerState<PlayAlertsPanel> createState() => _PlayAlertsPanelState();
}

class _PlayAlertsPanelState extends ConsumerState<PlayAlertsPanel> {
  String? _busy;

  Future<void> _run(PlayAction a, Future<void> Function(PlayApi api) action, String ok) async {
    final api = ref.read(playApiProvider);
    if (api == null || _busy != null) return;
    setState(() => _busy = a.id);
    try {
      await action(api);
      if (mounted) showMessage(context, ok);
    } on AuthException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = null);
        ref.invalidate(tournamentPlayProvider(widget.tournament.id));
      }
    }
  }

  /// Pone el resultado reportado (aunque el rival aún no lo haya confirmado).
  Future<void> _apply(PlayAction a) => _run(a, (api) async {
        if (widget.asJudge) {
          await api.judgeResult(widget.tournament.id, a.matchId!, score: a.score!.game);
          return;
        }
        await ref.read(tournamentServiceProvider).reportScore(a.matchId!, a.score!.game);
        await api.done(a.id);
        await ref.read(syncControllerProvider.notifier).sync();
      }, widget.asJudge ? 'Enviado: lo pone el organizador al sincronizar' : 'Resultado puesto');

  String _ago(DateTime t) {
    final m = DateTime.now().difference(t).inMinutes;
    return m < 1 ? 'ahora' : 'hace $m min';
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(playApiProvider) == null) return const SizedBox.shrink();
    final all = ref.watch(tournamentPlayProvider(widget.tournament.id)).value ?? const <PlayAction>[];
    final byMatch = {for (final m in widget.matches) m.id: m};
    final roundIds = byMatch.keys.toSet();
    // De esta ronda (o sin mesa), y sin los resultados ya puestos a mano.
    final items = [
      for (final a in all)
        if (a.matchId == null || roundIds.contains(a.matchId))
          if (!(a.kind == PlayKind.report && (byMatch[a.matchId]?.result.isReported ?? false))) a,
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    String table(PlayAction a) {
      final m = byMatch[a.matchId];
      return m?.tableNumber == null ? '' : 'Mesa ${m!.tableNumber} · ';
    }

    String vs(PlayAction a) {
      final m = byMatch[a.matchId];
      if (m == null) return '';
      return '${widget.names[m.player1Id] ?? '?'} vs ${widget.names[m.player2Id] ?? '?'}';
    }

    Widget tile(PlayAction a) {
      final busy = _busy == a.id;
      final (IconData icon, Color color, String title, String detail) = switch (a.kind) {
        PlayKind.judge => (
            Icons.campaign,
            AppColors.loss,
            '${table(a)}${a.nickname ?? '?'} llama al juez',
            [if (a.note != null) '"${a.note}"', _ago(a.createdAt)].join(' · '),
          ),
        PlayKind.drop => (
            Icons.logout,
            AppColors.draw,
            '${a.nickname ?? '?'} pide drop',
            'Se aplica solo al sincronizar · ${_ago(a.createdAt)}',
          ),
        PlayKind.report => switch (a.status) {
            PlayStatus.disputed => (
                Icons.report_problem_outlined,
                AppColors.loss,
                '${table(a)}No coinciden',
                '${vs(a)}: ${a.nickname ?? '?'} dice ${a.score?.label(asP1: true)}, el rival '
                    '${a.otherScore?.label(asP1: true) ?? 'no está de acuerdo'} (desde el jugador 1)',
              ),
            PlayStatus.confirmed => (
                Icons.check_circle_outline,
                AppColors.neon,
                '${table(a)}Confirmado ${a.score?.label(asP1: true)}',
                '${vs(a)} · se pone solo al sincronizar',
              ),
            _ => (
                Icons.hourglass_top,
                AppColors.textSecondary,
                '${table(a)}${a.nickname ?? '?'} reportó ${a.score?.label(asP1: true)}',
                '${vs(a)} · falta que confirme el rival',
              ),
          },
      };
      final canApply = a.kind == PlayKind.report && a.score != null && a.matchId != null &&
          a.status != PlayStatus.confirmed;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
                  Text(detail, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  if (busy)
                    const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator())
                  else
                    Wrap(
                      spacing: 8,
                      children: [
                        if (canApply)
                          TextButton(
                            onPressed: () => _apply(a),
                            child: Text('Poner ${a.score!.label(asP1: true)}'),
                          ),
                        if (a.kind != PlayKind.drop)
                          TextButton(
                            onPressed: () => _run(a, (api) => api.done(a.id),
                                a.kind == PlayKind.judge ? 'Atendido' : 'Descartado'),
                            child: Text(a.kind == PlayKind.judge ? 'Atendido' : 'Descartar'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final judges = items.where((a) => a.kind == PlayKind.judge).length;
    return NeonCard(
      glow: judges > 0,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Avisos de los jugadores (${items.length})',
              style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          for (final a in items) tile(a),
        ],
      ),
    );
  }
}

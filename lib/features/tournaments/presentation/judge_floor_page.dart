import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/auth/account.dart';
import '../../../core/db/app_database.dart';
import '../../../core/play/play.dart';
import '../../../core/sync/sync_service.dart';
import '../domain/game_score.dart';
import 'providers.dart';
import 'tabs/play_alerts.dart';

/// Vista de sala del juez: la ronda actual mesa por mesa (sin resultado,
/// reportada, con tiempo extra) y, por mesa, poner resultado, dar tiempo
/// extra o una penalización. Lo que hace el juez llega al teléfono del
/// organizador y se aplica al sincronizar.
class JudgeFloorPage extends ConsumerWidget {
  const JudgeFloorPage({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tournamentProvider(tournamentId)).value;
    final rounds = ref.watch(roundsProvider(tournamentId)).value ?? const <Round>[];
    final round = rounds.isEmpty ? null : rounds.last;
    final matches = round == null ? const <Match>[] : ref.watch(roundMatchesProvider(round.id)).value ?? const <Match>[];
    final registered = ref.watch(registeredProvider(tournamentId)).value ?? const [];
    final names = {for (final r in registered) r.player.id: r.player.nickname};
    final sorted = [...matches]..sort((a, b) {
        if (a.isBye != b.isBye) return a.isBye ? 1 : -1;
        return (a.tableNumber ?? 1 << 20).compareTo(b.tableNumber ?? 1 << 20);
      });
    final pending = sorted.where((m) => !m.isBye && !m.result.isReported).length;

    return Scaffold(
      appBar: AppBar(title: const Text('VISTA DE SALA')),
      body: t == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref.read(syncControllerProvider.notifier).sync(),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      round == null
                          ? '${t.name}: aún no hay rondas'
                          : '${t.name} · ${roundLabel(round)} · faltan $pending resultado(s)',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (round != null)
                    PlayAlertsPanel(tournament: t, matches: matches, names: names, asJudge: true),
                  for (final m in sorted) _TableTile(tournamentId: tournamentId, match: m, names: names),
                ],
              ),
            ),
    );
  }
}

class _TableTile extends ConsumerWidget {
  const _TableTile({required this.tournamentId, required this.match, required this.names});

  final String tournamentId;
  final Match match;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = match;
    final p1 = names[m.player1Id] ?? '?';
    final p2 = m.player2Id == null ? 'BYE' : names[m.player2Id] ?? '?';
    final done = m.result.isReported;
    final score = m.result == MatchResult.doubleLoss
        ? 'Doble derrota'
        : done && m.games1 != null
            ? '${m.games1}-${m.gamesDraw ?? 0}-${m.games2}'
            : null;
    return NeonCard(
      onTap: m.isBye ? null : () => _actions(context, ref, p1, p2),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(m.isBye ? 'BYE' : '${m.tableNumber ?? ''}',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.neon)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$p1 vs $p2', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  [
                    score ?? 'Sin resultado',
                    if (m.extraMinutes > 0) '+${m.extraMinutes} min',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: done ? AppColors.neon : AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (!m.isBye) Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  Future<void> _actions(BuildContext context, WidgetRef ref, String p1, String p2) async {
    final m = match;
    final what = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Mesa ${m.tableNumber ?? ''}: $p1 vs $p2', style: const TextStyle(fontWeight: FontWeight.w800)),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Poner resultado'),
              onTap: () => Navigator.pop(ctx, 'result'),
            ),
            ListTile(
              leading: const Icon(Icons.more_time),
              title: const Text('Tiempo extra'),
              subtitle: Text(m.extraMinutes > 0 ? 'Ahora: +${m.extraMinutes} min' : 'Sin tiempo extra'),
              onTap: () => Navigator.pop(ctx, 'time'),
            ),
            ListTile(
              leading: const Icon(Icons.gavel),
              title: const Text('Penalización'),
              onTap: () => Navigator.pop(ctx, 'penalty'),
            ),
          ],
        ),
      ),
    );
    if (what == null || !context.mounted) return;
    final api = ref.read(playApiProvider);
    if (api == null) return;
    try {
      switch (what) {
        case 'result':
          final pick = await showModalBottomSheet<(GameScore?, bool)>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (label, s) in [
                      ('Gana $p1 2-0', const GameScore(2, 0, 0)),
                      ('Gana $p1 2-1', const GameScore(2, 0, 1)),
                      ('Empate 1-1-1', const GameScore(1, 1, 1)),
                      ('Gana $p2 2-1', const GameScore(1, 0, 2)),
                      ('Gana $p2 2-0', const GameScore(0, 0, 2)),
                    ]) ...[
                      OutlinedButton(onPressed: () => Navigator.pop(ctx, (s, false)), child: Text(label)),
                      const SizedBox(height: 10),
                    ],
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, (null, true)),
                      child: Text('Doble derrota', style: TextStyle(color: AppColors.loss)),
                    ),
                  ],
                ),
              ),
            ),
          );
          if (pick == null) return;
          await api.judgeResult(tournamentId, m.id, score: pick.$1, doubleLoss: pick.$2);
        case 'time':
          final txt = await promptText(context,
              title: 'Tiempo extra (minutos)', label: 'Total para esta mesa (0 = quitar)',
              initial: m.extraMinutes > 0 ? '${m.extraMinutes}' : '', confirm: 'Dar tiempo');
          final n = int.tryParse(txt?.trim() ?? '');
          if (n == null) return;
          await api.extension(tournamentId, m.id, n);
        case 'penalty':
          if (!context.mounted) return;
          final p = await _askPenalty(context, p1, p2);
          if (p == null) return;
          await api.penalty(tournamentId, p.$1, p.$2.name, reason: p.$3, matchId: m.id);
      }
      if (context.mounted) showMessage(context, 'Enviado: lo aplica el organizador al sincronizar');
      ref.invalidate(tournamentPlayProvider(tournamentId));
    } on AuthException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (context.mounted) showMessage(context, 'No se pudo: $e', error: true);
    }
  }

  /// Jugador, tipo y motivo.
  Future<(String, PenaltyKind, String)?> _askPenalty(BuildContext context, String p1, String p2) {
    var who = match.player1Id;
    var kind = PenaltyKind.warning;
    final reason = TextEditingController();
    return showDialog<(String, PenaltyKind, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          actionsOverflowButtonSpacing: 10,
          title: const Text('Penalización'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: match.player1Id, label: Text(p1, overflow: TextOverflow.ellipsis)),
                    if (match.player2Id != null)
                      ButtonSegment(value: match.player2Id!, label: Text(p2, overflow: TextOverflow.ellipsis)),
                  ],
                  selected: {who},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => set(() => who = s.first),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in PenaltyKind.values)
                      ChoiceChip(
                        label: Text(k.label),
                        selected: kind == k,
                        onSelected: (_) => set(() => kind = k),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reason,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Motivo'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, (who, kind, reason.text.trim())),
              child: const Text('Poner'),
            ),
          ],
        ),
      ),
    );
  }
}

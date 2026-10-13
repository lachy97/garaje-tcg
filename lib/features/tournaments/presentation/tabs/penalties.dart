import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/common.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/db/database_provider.dart';

/// Penalizaciones del torneo (solo registro).
final tournamentPenaltiesProvider =
    StreamProvider.autoDispose.family<List<Penalty>, String>((ref, id) {
  return ref.watch(tournamentsDaoProvider).watchPenalties(id);
});

Color penaltyColor(PenaltyKind k) => switch (k) {
      PenaltyKind.warning => AppColors.draw,
      PenaltyKind.gameLoss || PenaltyKind.matchLoss => AppColors.loss,
      PenaltyKind.disqualification => AppColors.loss,
    };

/// Diálogo para registrar una penalización a [player].
Future<void> addPenaltyDialog(
  BuildContext context,
  WidgetRef ref, {
  required Tournament tournament,
  required Player player,
}) async {
  final result = await showDialog<(PenaltyKind, String)>(
    context: context,
    builder: (_) => _PenaltyDialog(player: player.nickname),
  );
  if (result == null || !context.mounted) return;
  await runGuarded(
    context,
    () => ref.read(tournamentsDaoProvider).addPenalty(
          tournamentId: tournament.id,
          playerId: player.id,
          round: tournament.currentRound,
          kind: result.$1,
          reason: result.$2,
        ),
    success: 'Penalización registrada',
  );
}

class _PenaltyDialog extends StatefulWidget {
  const _PenaltyDialog({required this.player});

  final String player;

  @override
  State<_PenaltyDialog> createState() => _PenaltyDialogState();
}

class _PenaltyDialogState extends State<_PenaltyDialog> {
  PenaltyKind _kind = PenaltyKind.warning;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Penalización · ${widget.player}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final k in PenaltyKind.values)
              RadioListTile<PenaltyKind>(
                contentPadding: EdgeInsets.zero,
                value: k,
                groupValue: _kind,
                onChanged: (v) => setState(() => _kind = v!),
                title: Text(k.label),
              ),
            TextField(
              controller: _reason,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Solo queda anotada. Si cambia el resultado de una mesa o el jugador '
              'debe salir del torneo, hazlo a mano (resultado o Drop).',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_kind, _reason.text)),
          child: const Text('Registrar'),
        ),
      ],
    );
  }
}

/// Lista plegable de penalizaciones del torneo, con opción de quitarlas.
class PenaltiesSection extends ConsumerWidget {
  const PenaltiesSection({super.key, required this.tournament, required this.names});

  final Tournament tournament;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(tournamentPenaltiesProvider(tournament.id)).value ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      leading: const Icon(Icons.gavel, color: AppColors.loss),
      title: Text('Penalizaciones (${list.length})'),
      children: [
        for (final p in list)
          ListTile(
            dense: true,
            title: Text('${names[p.playerId] ?? '?'} · ${p.kind.label}',
                style: TextStyle(color: penaltyColor(p.kind), fontWeight: FontWeight.w700)),
            subtitle: Text([
              p.round == 0 ? 'Antes de empezar' : 'Ronda ${p.round}',
              if (p.reason != null) p.reason!,
            ].join(' · ')),
            trailing: IconButton(
              tooltip: 'Quitar',
              icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
              onPressed: () => runGuarded(context, () async {
                final ok = await confirmDialog(context,
                    title: 'Quitar penalización',
                    message: '¿Quitar esta penalización de ${names[p.playerId] ?? '?'}?',
                    confirm: 'Quitar',
                    danger: true);
                if (!ok) throw const ActionCancelled();
                await ref.read(tournamentsDaoProvider).deletePenalty(p);
              }),
            ),
          ),
      ],
    );
  }
}

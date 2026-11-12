import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/auth/account.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/play/play.dart';
import '../../../core/sync/sync_service.dart';

/// Torneo en inscripción con check-in activo donde estoy inscrito.
class MyCheckIn {
  const MyCheckIn({required this.tournamentId, required this.name, required this.done});

  final String tournamentId;
  final String name;
  final bool done;
}

final myCheckInsProvider = StreamProvider.autoDispose.family<List<MyCheckIn>, String>((ref, playerId) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        'SELECT t.id AS tid, t.name AS tname, e.checked_in AS done FROM tournaments t '
        'JOIN tournament_players e ON e.tournament_id = t.id '
        "WHERE e.player_id = ? AND e.deleted_at IS NULL AND t.deleted_at IS NULL AND t.status = 'draft' "
        'AND t.check_in = 1 ORDER BY t.date',
        variables: [Variable.withString(playerId)],
        readsFrom: {db.tournaments, db.tournamentPlayers},
      )
      .watch()
      .map((rows) => [
            for (final r in rows)
              MyCheckIn(
                tournamentId: r.read<String>('tid'),
                name: r.read<String>('tname'),
                done: r.read<bool>('done'),
              ),
          ]);
});

/// En Torneos: hacer check-in con el código que da el organizador.
class CheckInSection extends ConsumerWidget {
  const CheckInSection({super.key, required this.playerId});

  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myCheckInsProvider(playerId)).value ?? const <MyCheckIn>[];
    if (list.isEmpty || ref.watch(playApiProvider) == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Check-in'),
        for (final c in list)
          NeonCard(
            glow: !c.done,
            child: Row(
              children: [
                Icon(c.done ? Icons.check_circle : Icons.login, color: c.done ? AppColors.neon : AppColors.draw),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(
                        c.done
                            ? 'Check-in hecho'
                            : 'Al llegar, escribe el código que da el organizador.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (!c.done)
                  FilledButton(
                    onPressed: () => _checkIn(context, ref, c),
                    child: const Text('Check-in'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _checkIn(BuildContext context, WidgetRef ref, MyCheckIn c) async {
    final code = await promptText(context, title: 'Check-in · ${c.name}', label: 'Código', confirm: 'Enviar');
    if (code == null || code.trim().isEmpty || !context.mounted) return;
    try {
      await ref.read(playApiProvider)!.checkin(c.tournamentId, code.trim());
      if (context.mounted) {
        showMessage(context, 'Check-in enviado: queda marcado cuando sincronice el organizador');
      }
      await ref.read(syncControllerProvider.notifier).sync();
    } on AuthException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (context.mounted) showMessage(context, 'No se pudo: $e', error: true);
    }
  }
}

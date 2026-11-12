import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/brand.dart';
import '../../../../app/widgets/common.dart';
import '../../../../core/auth/account.dart';
import '../../../../core/auth/auth_providers.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/db/daos/tournaments_dao.dart';
import '../../../../core/db/database_provider.dart';
import '../../../../core/play/play.dart';
import '../../../../core/sync/sync_service.dart';

/// Código corto de check-in (sin letras que se confunden: 0/O, 1/I).
String newCheckinCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Check-in el día del torneo (organizador, en inscripción): activarlo, el
/// código que se dice en voz alta o se proyecta, y cuántos lo han hecho.
class CheckInCard extends ConsumerWidget {
  const CheckInCard({super.key, required this.tournament, required this.registered});

  final Tournament tournament;
  final List<RegisteredPlayer> registered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tournament;
    if (t.status != TournamentStatus.draft || !ref.watch(permissionsProvider).canManageTournament(isOwner: true)) {
      return const SizedBox.shrink();
    }
    final done = registered.where((r) => r.entry.checkedIn).length;

    Future<void> save({bool? on, String? code}) async {
      await ref.read(tournamentsDaoProvider).updateSettings(t.id, checkIn: on, checkinCode: code);
      await ref.read(syncControllerProvider.notifier).sync();
    }

    return NeonCard(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.how_to_reg_outlined, color: AppColors.neon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t.checkIn ? 'Check-in · $done de ${registered.length}' : 'Check-in el día del torneo',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Switch(
                value: t.checkIn,
                onChanged: (v) => runGuarded(
                  context,
                  () => save(on: v, code: v && (t.checkinCode ?? '').isEmpty ? newCheckinCode() : null),
                ),
              ),
            ],
          ),
          if (t.checkIn)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Código: ${t.checkinCode ?? '—'}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      color: AppColors.neonBright,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => runGuarded(context, () => save(code: newCheckinCode())),
                  child: const Text('Nuevo código'),
                ),
              ],
            ),
          if (t.checkIn)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Los jugadores lo escriben en Torneos (con conexión) o lo marcas tú en cada inscrito. '
                'Al generar la ronda 1 podrás quitar a los que no lo hicieron.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Jueces del torneo (organizador): ven todas las partidas y penalizaciones,
/// y desde su móvil ponen resultados, tiempo extra y penalizaciones.
class JudgesCard extends ConsumerWidget {
  const JudgesCard({super.key, required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tournament;
    final api = ref.watch(playApiProvider);
    if (api == null ||
        t.status == TournamentStatus.finished ||
        !ref.watch(permissionsProvider).canManageTournament(isOwner: true)) {
      return const SizedBox.shrink();
    }
    final judges = ref.watch(tournamentJudgesProvider(t.id));
    final list = judges.value ?? const <StaffAccount>[];

    Future<void> run(Future<void> Function() f) async {
      try {
        await f();
      } on AuthException catch (e) {
        if (context.mounted) showMessage(context, e.message, error: true);
      } catch (e) {
        if (context.mounted) showMessage(context, 'No se pudo: $e', error: true);
      }
      ref.invalidate(tournamentJudgesProvider(t.id));
    }

    return NeonCard(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      child: Row(
        children: [
          Icon(Icons.gavel, color: AppColors.neon),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              judges.hasError
                  ? 'Jueces (sin conexión)'
                  : list.isEmpty
                      ? 'Sin jueces'
                      : 'Jueces: ${list.map((j) => j.nickname).join(', ')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => FractionallySizedBox(
                heightFactor: 0.75,
                child: _JudgesSheet(tournamentId: t.id, run: run),
              ),
            ),
            child: const Text('Gestionar'),
          ),
        ],
      ),
    );
  }
}

class _JudgesSheet extends ConsumerWidget {
  const _JudgesSheet({required this.tournamentId, required this.run});

  final String tournamentId;
  final Future<void> Function(Future<void> Function()) run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(playApiProvider)!;
    final judges = ref.watch(tournamentJudgesProvider(tournamentId)).value ?? const <StaffAccount>[];
    final ids = {for (final j in judges) j.id};
    return FutureBuilder<List<StaffAccount>>(
      future: api.candidates(),
      builder: (context, snap) {
        final all = snap.data ?? const <StaffAccount>[];
        return ListView(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('JUECES DEL TORNEO',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Ven todas las partidas y penalizaciones de este torneo (sin teléfonos ni cover) y, '
                'desde "Vista de sala", ponen resultados, tiempo extra y penalizaciones. Salen las '
                'cuentas con rol Juez u Organizador (el rol lo da el administrador).',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            if (snap.hasError)
              const Padding(padding: EdgeInsets.all(16), child: Text('Sin conexión con el servidor.')),
            if (!snap.hasData && !snap.hasError)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            for (final a in all)
              CheckboxListTile(
                value: ids.contains(a.id),
                title: Text(a.nickname),
                subtitle: Text('@${a.username} · ${a.role == 'judge' ? 'Juez' : a.role == 'admin' ? 'Administrador' : 'Organizador'}'),
                onChanged: (v) => run(() async {
                  if (v ?? false) {
                    await api.addJudge(tournamentId, a.id);
                  } else {
                    await api.removeJudge(tournamentId, a.id);
                  }
                }),
              ),
            if (snap.hasData && all.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No hay cuentas con rol Juez. Pídele al administrador que se lo dé.'),
              ),
          ],
        );
      },
    );
  }
}

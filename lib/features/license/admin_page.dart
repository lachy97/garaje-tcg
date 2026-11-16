import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/auth/account.dart';
import '../../core/auth/http_auth_api.dart';
import '../../core/sync/sync_service.dart';
import '../../core/utils/season_utils.dart';
import '../ranking/data/historic_seasons.dart';
import '../ranking/presentation/historic_import_page.dart';
import '../tournaments/domain/tournament_names.dart';
import '../ranking/presentation/season_picker.dart';

/// Modo administrador: tareas poco frecuentes del administrador (reabrir
/// temporadas cerradas). Ya no hay licencias: la app se paga aparte.
class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(permissionsProvider).isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('MODO ADMINISTRADOR')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'No disponible',
          subtitle: 'Solo para la cuenta de administrador.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('MODO ADMINISTRADOR')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const SectionLabel('Temporadas anteriores a la app'),
          NeonCard(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const HistoricImportPage())),
            child: Row(
              children: [
                Icon(Icons.history, color: AppColors.neon),
                const SizedBox(width: 12),
                const Expanded(child: Text('Importar el ranking final de T1, T2 y T3 2026')),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SectionLabel('Nombres de los torneos'),
          const NeonCard(child: _TournamentNames()),
          const SectionLabel('Temporadas cerradas'),
          const NeonCard(child: _ClosedSeasons()),
        ],
      ),
    );
  }
}

/// Temporadas cerradas, con opción de reabrirlas (sus torneos vuelven a ser
/// editables y el ranking deja de ser la foto guardada).
class _ClosedSeasons extends ConsumerWidget {
  const _ClosedSeasons();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasons = ref.watch(seasonListProvider).value ?? const <Season>[];
    // Las importadas (antes de la app) no se reabren: no tienen torneos y se
    // perdería su ranking (se vuelven a importar arriba si hace falta).
    final closed = seasons.where((s) => s.status == SeasonStatus.closed && !isHistoricSeason(s)).toList();
    if (closed.isEmpty) {
      return Text('No hay temporadas cerradas. Se cierran desde Datos → Ranking (botón de ajustes).',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary));
    }
    return Column(
      children: [
        for (final s in closed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: Text('Temporada ${seasonLabel(s.year, s.quarter)}'),
            trailing: TextButton(
              onPressed: () => runGuarded(context, () async {
                final label = seasonLabel(s.year, s.quarter);
                final ok = await confirmDialog(
                  context,
                  title: 'Reabrir temporada $label',
                  message: 'Se borra el ranking definitivo guardado y sus torneos '
                      'vuelven a poder editarse. Ciérrala otra vez cuando termines.',
                  confirm: 'Reabrir',
                  danger: true,
                );
                if (!ok) throw const ActionCancelled();
                await ref.read(rankingDaoProvider).reopenSeason(s.id);
              }, success: 'Temporada reabierta'),
              child: const Text('Reabrir'),
            ),
          ),
      ],
    );
  }
}

/// Pone a los torneos terminados el nombre de la comunidad ("Torneo #1 ·
/// T4 2026"), numerados por fecha dentro de su temporada. Se ve antes lo que
/// cambia; los de prueba se pueden dejar fuera (no cuentan para el número).
/// Se guarda en el servidor y llega a todos al sincronizar.
class _TournamentNames extends ConsumerStatefulWidget {
  const _TournamentNames();

  @override
  ConsumerState<_TournamentNames> createState() => _TournamentNamesState();
}

class _TournamentNamesState extends ConsumerState<_TournamentNames> {
  final Set<String> _skip = {};
  bool _busy = false;

  Future<void> _apply(List<(Tournament, String)> changes) async {
    final api = ref.read(authApiProvider);
    final session = ref.read(sessionProvider).value;
    if (api is! HttpAuthApi || session == null) {
      showMessage(context, 'Necesitas conexión con el servidor.', error: true);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Renombrar ${changes.length} torneo(s)',
      message: 'Se cambia solo el nombre (no los resultados ni el ranking). '
          'Llega a todos los teléfonos al sincronizar.',
      confirm: 'Renombrar',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await api.request('POST', 'v1/admin/tournaments/rename', token: session.token, body: {
        'items': [for (final (t, name) in changes) {'id': t.id, 'name': name}],
      });
      await ref.read(syncControllerProvider.notifier).sync();
      if (mounted) showMessage(context, '${r['renamed'] ?? 0} torneo(s) renombrados');
    } on AuthException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(_allTournamentsProvider).value ?? const <Tournament>[];
    final finished = [
      for (final t in all)
        if (t.status == TournamentStatus.finished) t,
    ]..sort((a, b) => a.date.compareTo(b.date));
    final changes = renameProposals(all, skip: _skip);
    final byId = {for (final (t, name) in changes) t.id: name};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Formato: ${tournamentName(1, 2026, 4)}, numerados por fecha dentro de cada temporada. '
          'Desmarca los torneos de prueba: no cuentan para el número ni se renombran.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        if (finished.isEmpty)
          Text('No hay torneos terminados.', style: TextStyle(color: AppColors.textSecondary))
        else
          for (final t in finished)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: !_skip.contains(t.id),
              onChanged: (v) => setState(() => v == true ? _skip.remove(t.id) : _skip.add(t.id)),
              title: Text(byId[t.id] ?? t.name,
                  style: TextStyle(fontWeight: FontWeight.w700, color: byId.containsKey(t.id) ? AppColors.neon : null)),
              subtitle: Text(
                _skip.contains(t.id)
                    ? '${t.name} · no se toca'
                    : byId.containsKey(t.id)
                        ? 'Antes: ${t.name}'
                        : 'Ya tiene el formato',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        const SizedBox(height: 8),
        _busy
            ? const Center(child: CircularProgressIndicator())
            : FilledButton.icon(
                onPressed: changes.isEmpty ? null : () => _apply(changes),
                icon: const Icon(Icons.drive_file_rename_outline),
                label: Text(changes.isEmpty ? 'Todos tienen el formato' : 'Renombrar ${changes.length} torneo(s)'),
              ),
      ],
    );
  }
}

final _allTournamentsProvider = StreamProvider.autoDispose<List<Tournament>>(
  (ref) => ref.watch(tournamentsDaoProvider).watchAll(),
);

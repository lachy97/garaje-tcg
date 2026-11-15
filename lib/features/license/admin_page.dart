import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/utils/season_utils.dart';
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
        children: const [
          SectionLabel('Temporadas cerradas'),
          NeonCard(child: _ClosedSeasons()),
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
    final closed = seasons.where((s) => s.status == SeasonStatus.closed).toList();
    if (closed.isEmpty) {
      return Text('No hay temporadas cerradas. Se cierran desde la pantalla de Ranking.',
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

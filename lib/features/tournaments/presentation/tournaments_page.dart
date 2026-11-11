import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../app/widgets/sync_widgets.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/auth/auth_providers.dart';
import 'providers.dart';

class TournamentsPage extends ConsumerWidget {
  const TournamentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permissionsProvider);
    final all = ref.watch(tournamentsProvider);
    // Quien no lleva torneos ve solo aquellos en los que está inscrito.
    final mine = perms.canCreateTournaments || perms.playerId == null
        ? null
        : ref.watch(playerTournamentIdsProvider(perms.playerId!)).value;
    final tournaments = perms.canCreateTournaments
        ? all
        : all.whenData((list) => [for (final t in list) if (mine?.contains(t.id) ?? false) t]);
    return Scaffold(
      body: SafeArea(
        child: SyncRefresh(
          child: CustomScrollView(
            // Para poder arrastrar y sincronizar aunque la lista sea corta.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 16, bottom: 4),
                      child: Center(
                        child: Column(
                          children: [
                            GlowLogo(size: 72),
                            SizedBox(height: 8),
                            BrandTitle(fontSize: 22),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Row(
                        children: [
                          const SyncStatusIcon(),
                          IconButton(
                            tooltip: 'Ajustes',
                            onPressed: () => context.push('/ajustes'),
                            icon: const Icon(Icons.settings_outlined,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ...tournaments.when<List<Widget>>(
                skipLoadingOnReload: true,
                loading: () => [
                  const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
                ],
                error: (e, _) => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                        icon: Icons.error_outline, title: 'No se pudo cargar', subtitle: '$e'),
                  ),
                ],
                data: (list) {
                  if (list.isEmpty) {
                    return [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: Icons.emoji_events_outlined,
                          title: 'Aún no hay torneos',
                          subtitle: perms.canCreateTournaments
                              ? 'Crea el primero con "Nuevo torneo".'
                              : 'Aquí verás los torneos en los que estés inscrito.',
                        ),
                      ),
                    ];
                  }
                  // Agrupados: en juego primero, luego inscripción y terminados.
                  final live = [
                    for (final t in list)
                      if (t.status == TournamentStatus.swiss || t.status == TournamentStatus.topCut) t,
                  ];
                  final draft = [for (final t in list) if (t.status == TournamentStatus.draft) t];
                  final done = [for (final t in list) if (t.status == TournamentStatus.finished) t];
                  List<Widget> group(String label, List<Tournament> items) => [
                        if (items.isNotEmpty) ...[
                          SliverToBoxAdapter(child: SectionLabel('$label (${items.length})')),
                          SliverList.builder(
                            itemCount: items.length,
                            itemBuilder: (_, i) => _TournamentTile(t: items[i]),
                          ),
                        ],
                      ];
                  return [
                    ...group('En juego', live),
                    ...group('Inscripción abierta', draft),
                    ...group('Terminados', done),
                    const SliverToBoxAdapter(child: SizedBox(height: 96)),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: perms.canCreateTournaments
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/torneos/nuevo'),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo torneo'),
            )
          : null,
    );
  }
}

class _TournamentTile extends ConsumerWidget {
  const _TournamentTile({required this.t});

  final Tournament t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = t.status == TournamentStatus.swiss || t.status == TournamentStatus.topCut;
    final date = DateFormat.yMMMd('es').format(t.date);
    final detail = switch (t.status) {
      TournamentStatus.draft => 'Inscripción abierta',
      TournamentStatus.swiss => 'Ronda ${t.currentRound} de ${t.swissRounds}',
      TournamentStatus.topCut => 'Top ${t.topCutSize} en juego',
      TournamentStatus.finished => 'Terminado',
    };
    return NeonCard(
      glow: live,
      onTap: () => context.push('/torneos/${t.id}'),
      child: Row(
        children: [
          Icon(
            switch (t.status) {
              TournamentStatus.finished => Icons.emoji_events,
              TournamentStatus.draft => Icons.how_to_reg,
              _ => Icons.bolt,
            },
            color: live ? AppColors.neon : AppColors.leaf,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text('$date · $detail',
                    style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (ref.watch(permissionsProvider).canManageTournament(isOwner: true))
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
            onSelected: (_) => runGuarded(context, () async {
              final ok = await confirmDialog(
                context,
                title: 'Eliminar torneo',
                message: '¿Eliminar "${t.name}"? Sus puntos se quitarán del ranking.',
                confirm: 'Eliminar',
                danger: true,
              );
              if (ok) await ref.read(tournamentsDaoProvider).softDelete(t.id);
            }),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Eliminar')),
            ],
          ),
        ],
      ),
    );
  }
}

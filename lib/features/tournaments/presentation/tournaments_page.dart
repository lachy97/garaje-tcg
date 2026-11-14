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
import '../../../core/registrations/registrations.dart';
import '../../../core/play/play.dart';
import 'check_in.dart';
import 'my_table.dart';
import 'open_registrations.dart';
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
    // Torneos con la inscripción desde la app abierta (según el servidor):
    // se muestran aparte, con el botón para inscribirse.
    final player = !perms.canCreateTournaments;
    final openIds = player
        ? {for (final t in ref.watch(myRegistrationsProvider).value?.open ?? const []) t.id}
        : const <String>{};
    // Torneos donde es juez (los ve enteros).
    final judging = player ? ref.watch(judgingProvider).value ?? const <String>{} : const <String>{};
    final tournaments = perms.canCreateTournaments
        ? all
        : all.whenData((list) {
            // Los suyos (inscrito o juez) y, para que la app no se vea vacía,
            // los últimos torneos terminados de la comunidad.
            var finished = 0;
            return [
              for (final t in list)
                if (!openIds.contains(t.id) &&
                    ((mine?.contains(t.id) ?? false) ||
                        judging.contains(t.id) ||
                        (t.status == TournamentStatus.finished && finished++ < 10)))
                  t,
            ];
          });
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
                            // El logo ya lleva el nombre.
                            GlowLogo(size: 120),
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
                            icon: Icon(Icons.settings_outlined,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Quien juega (tenga el rol que tenga): su mesa de la ronda actual.
              if (perms.playerId != null)
                SliverToBoxAdapter(child: MyTablesSection(playerId: perms.playerId!)),
              if (perms.playerId != null)
                SliverToBoxAdapter(child: CheckInSection(playerId: perms.playerId!)),
              if (player) const SliverToBoxAdapter(child: OpenRegistrationsSection()),
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
                  if (list.isEmpty && openIds.isNotEmpty) {
                    return [const SliverToBoxAdapter(child: SizedBox(height: 96))];
                  }
                  if (list.isEmpty) {
                    return [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: Icons.emoji_events_outlined,
                          title: 'Aún no hay torneos',
                          subtitle: perms.canCreateTournaments
                              ? 'Crea el primero con "Nuevo torneo".'
                              : 'Aquí verás los torneos en los que estés inscrito, '
                                  'los que tengan la inscripción abierta y los últimos resultados.',
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
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (ref.watch(permissionsProvider).canManageTournament(isOwner: true))
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: AppColors.textSecondary),
            onSelected: (_) => runGuarded(context, () async {
              final ok = await confirmDialog(
                context,
                title: 'Eliminar torneo',
                message: '¿Eliminar "${t.name}"? Sus puntos se quitarán del ranking.',
                confirm: 'Eliminar',
                danger: true,
              );
              if (!ok) return;
              final dao = ref.read(tournamentsDaoProvider);
              await dao.softDelete(t.id);
              if (!context.mounted) return;
              showMessage(
                context,
                '"${t.name}" eliminado',
                actionLabel: 'Deshacer',
                onAction: () => dao.restore(t.id),
              );
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

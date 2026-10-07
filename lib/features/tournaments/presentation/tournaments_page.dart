import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import 'providers.dart';

class TournamentsPage extends ConsumerWidget {
  const TournamentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournaments = ref.watch(tournamentsProvider);
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 24, bottom: 8),
                child: Column(
                  children: [
                    GlowLogo(size: 96),
                    SizedBox(height: 10),
                    BrandTitle(fontSize: 24),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SectionLabel('Torneos')),
            ...tournaments.when<List<Widget>>(
              loading: () => [
                const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator())),
              ],
              error: (e, _) => [SliverFillRemaining(child: Center(child: Text('$e')))],
              data: (list) => list.isEmpty
                  ? [
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: Icons.emoji_events_outlined,
                          title: 'Aún no hay torneos',
                          subtitle: 'Crea el primero con "Nuevo torneo".',
                        ),
                      ),
                    ]
                  : [
                      SliverList.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) => _TournamentTile(t: list[i]),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 96)),
                    ],
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/torneos/nuevo'),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo torneo'),
      ),
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
            t.status == TournamentStatus.finished ? Icons.emoji_events : Icons.bolt,
            color: live ? AppColors.neon : AppColors.leaf,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text('$date · $detail',
                    style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
            onSelected: (_) async {
              final ok = await confirmDialog(
                context,
                title: 'Eliminar torneo',
                message: '¿Eliminar "${t.name}"? Sus puntos se quitarán del ranking.',
                confirm: 'Eliminar',
                danger: true,
              );
              if (ok) await ref.read(tournamentsDaoProvider).softDelete(t.id);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Eliminar')),
            ],
          ),
        ],
      ),
    );
  }
}

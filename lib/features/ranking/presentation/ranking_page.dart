import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/daos/ranking_dao.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/utils/season_utils.dart';

final currentSeasonProvider = FutureProvider.autoDispose<Season>((ref) {
  return ref.watch(seasonsDaoProvider).current();
});

final seasonStandingsProvider =
    StreamProvider.autoDispose.family<List<SeasonStandingRow>, String>((ref, seasonId) {
  return ref.watch(rankingDaoProvider).watchSeasonStandings(seasonId);
});

/// Ranking trimestral (versión básica). La Fase 2 añade winrate, partidas,
/// último mazo, exportar a PNG y compartir por WhatsApp.
class RankingPage extends ConsumerWidget {
  const RankingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final season = ref.watch(currentSeasonProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('RANKING')),
      body: AsyncView(
        value: season,
        builder: (s) {
          final rows = ref.watch(seasonStandingsProvider(s.id));
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Temporada ${seasonLabel(s.year, s.quarter)}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        shadows: AppColors.textGlow(blur: 8),
                      ),
                ),
              ),
              Expanded(
                child: AsyncView(
                  value: rows,
                  builder: (list) => list.isEmpty
                      ? const EmptyState(
                          icon: Icons.leaderboard_outlined,
                          title: 'Aún no hay puntos este trimestre',
                          subtitle: 'Los puntos se suman al finalizar cada torneo.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 32),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _RankingTile(rank: i + 1, row: list[i]),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RankingTile extends StatelessWidget {
  const _RankingTile({required this.rank, required this.row});

  final int rank;
  final SeasonStandingRow row;

  @override
  Widget build(BuildContext context) {
    final top3 = rank <= 3;
    return NeonCard(
      glow: rank == 1,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '#$rank',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: top3 ? AppColors.neon : AppColors.textSecondary,
                shadows: rank == 1 ? AppColors.textGlow(blur: 8) : null,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.nickname, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '${row.tournaments} torneo(s) · mejor puesto: ${row.bestPosition}º',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text('${row.points}',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.neon)),
          const SizedBox(width: 4),
          const Text('pts', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

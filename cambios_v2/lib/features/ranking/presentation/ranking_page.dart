import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/utils/season_utils.dart';
import '../domain/ranking_row.dart';
import 'ranking_export.dart';
import 'ranking_table.dart';

final currentSeasonProvider = FutureProvider.autoDispose<Season>((ref) {
  return ref.watch(seasonsDaoProvider).current();
});

final seasonRankingProvider =
    StreamProvider.autoDispose.family<List<RankingRow>, String>((ref, seasonId) {
  return ref.watch(rankingDaoProvider).watchSeasonRanking(seasonId);
});

/// Ranking trimestral en tabla, con exportación a imagen.
class RankingPage extends ConsumerStatefulWidget {
  const RankingPage({super.key});

  @override
  ConsumerState<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends ConsumerState<RankingPage> {
  bool _exporting = false;

  Future<void> _export(Season season, List<RankingRow> rows) async {
    setState(() => _exporting = true);
    try {
      await exportRankingImage(context, season: season, rows: rows);
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo exportar la imagen: $e', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final season = ref.watch(currentSeasonProvider);
    final s = season.value;
    final rows = s == null ? null : ref.watch(seasonRankingProvider(s.id)).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RANKING'),
        actions: [
          if (s != null && rows != null && rows.isNotEmpty)
            IconButton(
              tooltip: 'Exportar imagen',
              onPressed: _exporting ? null : () => _export(s, rows),
              icon: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.ios_share),
            ),
        ],
      ),
      body: AsyncView(
        value: season,
        builder: (s) {
          final ranking = ref.watch(seasonRankingProvider(s.id));
          return AsyncView(
            value: ranking,
            builder: (list) => ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Temporada ${seasonLabel(s.year, s.quarter)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          shadows: AppColors.textGlow(blur: 8),
                        ),
                  ),
                ),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: EmptyState(
                      icon: Icons.leaderboard_outlined,
                      title: 'Aún no hay puntos este trimestre',
                      subtitle: 'Los puntos se suman al finalizar cada torneo.',
                    ),
                  )
                else ...[
                  RankingTable(rows: list),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      'Desempates: puntos → mejor posición → winrate → menos torneos. '
                      'PJ = partidas jugadas (sin BYE). Desliza la tabla para ver todas '
                      'las columnas.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: OutlinedButton.icon(
                      onPressed: _exporting ? null : () => _export(s, list),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('EXPORTAR RANKING COMO IMAGEN'),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

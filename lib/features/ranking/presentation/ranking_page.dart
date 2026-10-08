import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import '../domain/ranking_row.dart';
import 'ranking_export.dart';
import 'ranking_table.dart';
import 'season_picker.dart';

final seasonRankingProvider =
    StreamProvider.autoDispose.family<List<RankingRow>, String>((ref, seasonId) {
  return ref.watch(rankingDaoProvider).watchSeasonRanking(seasonId);
});

/// Ranking trimestral en tabla, con exportación a imágenes.
class RankingPage extends ConsumerStatefulWidget {
  const RankingPage({super.key});

  @override
  ConsumerState<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends ConsumerState<RankingPage> {
  bool _exporting = false;
  String? _seasonId; // null = trimestre actual

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
    final seasons = ref.watch(seasonListProvider);
    final list = seasons.value;
    final s = list == null || list.isEmpty ? null : pickSeason(list, _seasonId);
    final rows = s == null ? null : ref.watch(seasonRankingProvider(s.id)).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RANKING'),
        actions: [
          if (s != null && rows != null && rows.isNotEmpty)
            IconButton(
              tooltip: 'Exportar imágenes',
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
        value: seasons,
        builder: (all) {
          final season = pickSeason(all, _seasonId);
          final ranking = ref.watch(seasonRankingProvider(season.id));
          return AsyncView(
            value: ranking,
            builder: (list) => ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                SeasonPicker(
                  seasons: all,
                  selected: season,
                  onChanged: (v) => setState(() => _seasonId = v.id),
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
                      onPressed: _exporting ? null : () => _export(season, list),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('EXPORTAR RANKING COMO IMAGEN'),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      'Se genera una imagen por cada 12 jugadores para que se lea bien. '
                      'En WhatsApp, envíalas en calidad HD.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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

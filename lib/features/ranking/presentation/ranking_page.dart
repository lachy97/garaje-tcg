import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../app/widgets/sync_widgets.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/utils/season_utils.dart';
import '../domain/ranking_row.dart';
import 'ranking_export.dart';
import 'ranking_table.dart';
import 'season_picker.dart';

final seasonRankingProvider =
    StreamProvider.autoDispose.family<List<RankingRow>, String>((ref, seasonId) {
  return ref.watch(rankingDaoProvider).watchSeasonRanking(seasonId);
});

/// Ranking trimestral en tabla (se comparte como imagen desde la barra).
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
      if (mounted) showMessage(context, 'No se pudo compartir la imagen: $e', error: true);
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
            _exporting
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : ShareButton(tooltip: 'Compartir ranking', onPressed: () => _export(s, rows)),
          // Cerrar la temporada: irreversible y 4 veces al año, en el menú.
          if (s != null &&
              rows != null &&
              rows.isNotEmpty &&
              s.status != SeasonStatus.closed &&
              ref.watch(permissionsProvider).canCreateTournaments)
            PopupMenuButton<String>(
              tooltip: 'Más',
              onSelected: (_) => _closeSeason(context, ref, s),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'close',
                  child: ListTile(
                    leading: Icon(Icons.lock_outline, color: AppColors.loss),
                    title: Text('Cerrar temporada ${seasonLabel(s.year, s.quarter)}'),
                  ),
                ),
              ],
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
            builder: (list) => SyncRefresh(
              child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                SeasonPicker(
                  seasons: all,
                  selected: season,
                  onChanged: (v) => setState(() => _seasonId = v?.id),
                ),
                _SeasonStatusBar(season: season, hasRanking: list.isNotEmpty),
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
                  _MyPlace(rows: list),
                  RankingTable(rows: list),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      'En verde, los 8 primeros (más claro, mejor puesto). '
                      'Desempates: puntos → mejor posición → winrate → menos torneos. '
                      'PJ = partidas jugadas (sin BYE). Desliza la tabla para ver todas '
                      'las columnas.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
            ),
          );
        },
      ),
    );
  }
}

/// Estado de la temporada: cerrada (ranking definitivo) o botón para cerrarla.
class _SeasonStatusBar extends ConsumerWidget {
  const _SeasonStatusBar({required this.season, required this.hasRanking});

  final Season season;
  final bool hasRanking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (season.status == SeasonStatus.closed) {
      final when = season.closedAt == null
          ? ''
          : ' el ${season.closedAt!.day.toString().padLeft(2, '0')}/'
              '${season.closedAt!.month.toString().padLeft(2, '0')}/${season.closedAt!.year}';
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text('Temporada cerrada$when · ranking definitivo',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

Future<void> _closeSeason(BuildContext context, WidgetRef ref, Season season) {
  final label = seasonLabel(season.year, season.quarter);
  return runGuarded(context, () async {
    final ok = await confirmDialog(
      context,
      title: 'Cerrar temporada $label',
      message: 'Se guarda el ranking definitivo de la temporada y sus torneos '
          'quedan bloqueados: no se podrán editar, borrar ni crear torneos con '
          'fechas de este trimestre.\n\nSolo se puede reabrir desde el Modo '
          'administrador.',
      confirm: 'Cerrar temporada',
      danger: true,
    );
    if (!ok) throw const ActionCancelled();
    await ref.read(rankingDaoProvider).closeSeason(season.id);
  }, success: 'Temporada $label cerrada');
}

/// Para el jugador con ficha: su puesto y cuánto le falta para el Top 8 (o
/// para el puesto de arriba si ya está dentro).
class _MyPlace extends ConsumerWidget {
  const _MyPlace({required this.rows});

  final List<RankingRow> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pid = ref.watch(permissionsProvider).playerId;
    if (pid == null) return const SizedBox.shrink();
    final i = rows.indexWhere((r) => r.playerId == pid);
    final String text;
    if (i < 0 || rows[i].points == 0) {
      final eighth = rows.length >= 8 ? rows[7].points : 0;
      text = eighth > 0
          ? 'Aún no tienes puntos esta temporada: el 8º tiene $eighth. Entra al Top de un torneo para sumar.'
          : 'Aún no tienes puntos esta temporada: entra al Top de un torneo para sumar.';
    } else {
      final me = rows[i];
      final place = me.rank > 0 ? me.rank : i + 1;
      if (place == 1) {
        text = 'Vas 1º con ${me.points} pts. ¡A defenderlo!';
      } else if (place <= 8) {
        final up = rows[i - 1];
        final gap = up.points - me.points;
        text = 'Vas $placeº con ${me.points} pts${gap > 0 ? ': te faltan $gap para alcanzar a ${up.nickname}' : ', empatado con ${up.nickname}'}.';
      } else {
        final eighth = rows.length >= 8 ? rows[7].points : 0;
        final gap = eighth - me.points;
        text = 'Vas $placeº con ${me.points} pts${gap > 0 ? ': te faltan $gap para el Top 8' : ': empatado con el 8º'}.';
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: NeonCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.trending_up, color: AppColors.neon),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }
}

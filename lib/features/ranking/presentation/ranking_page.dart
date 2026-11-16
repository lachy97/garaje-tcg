import 'package:drift/drift.dart' show Variable;
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
import '../data/historic_seasons.dart';
import '../domain/ranking_row.dart';
import 'ranking_export.dart';
import 'ranking_table.dart';

final seasonRankingProvider =
    StreamProvider.autoDispose.family<List<RankingRow>, String>((ref, seasonId) {
  return ref.watch(rankingDaoProvider).watchSeasonRanking(seasonId);
});

/// Ranking global: todas las temporadas juntas.
final globalRankingProvider = StreamProvider.autoDispose<List<RankingRow>>((ref) {
  return ref.watch(rankingDaoProvider).watchGlobalRanking();
});

/// Mazos con los que jugó cada jugador en los torneos terminados de una
/// temporada (para filtrar el ranking por mazo: cuenta cualquiera, no solo
/// el último).
final seasonPlayerDecksProvider =
    StreamProvider.autoDispose.family<Map<String, Set<String>>, String>((ref, seasonId) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        'SELECT DISTINCT tp.player_id AS p, d.name AS deck FROM tournament_players tp '
        'JOIN tournaments t ON t.id = tp.tournament_id '
        'JOIN decks d ON d.id = tp.deck_id '
        // kAllSeasons ('*'): todas las temporadas (ranking global).
        "WHERE (? = '*' OR t.season_id = ?) AND t.status = 'finished' AND t.deleted_at IS NULL "
        'AND tp.deleted_at IS NULL',
        variables: [Variable.withString(seasonId), Variable.withString(seasonId)],
        readsFrom: {db.tournamentPlayers, db.tournaments, db.decks},
      )
      .watch()
      .map((rows) {
    final out = <String, Set<String>>{};
    for (final r in rows) {
      (out[r.read<String>('p')] ??= <String>{}).add(r.read<String>('deck'));
    }
    return out;
  });
});

/// Ranking de una temporada (pestaña Ranking de Datos): mi puesto, filtros por
/// jugador y por mazo jugado, y la tabla. Sin temporada: ranking global.
class RankingView extends ConsumerStatefulWidget {
  const RankingView({super.key, required this.season});

  /// null = global (todas las temporadas).
  final Season? season;

  @override
  ConsumerState<RankingView> createState() => _RankingViewState();
}

class _RankingViewState extends ConsumerState<RankingView> {
  /// Filtros: nombre del jugador y mazo con el que jugó en la temporada.
  String _query = '';
  String? _deck;

  @override
  Widget build(BuildContext context) {
    final season = widget.season;
    final ranking = season == null ? ref.watch(globalRankingProvider) : ref.watch(seasonRankingProvider(season.id));
    final decksByPlayer = ref.watch(seasonPlayerDecksProvider(season?.id ?? '*')).value ?? const {};
    return AsyncView(
      value: ranking,
      builder: (list) => SyncRefresh(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (season == null)
              const _GlobalInfo()
            else
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
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                // Buscador y filtro de mazo con el mismo estilo y alto (los
                // dos son campos con borde), uno al lado del otro.
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Jugador',
                        ),
                        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DeckFilter(
                        value: _deck,
                        decks: ({
                          for (final set in decksByPlayer.values) ...set,
                        }.toList()
                          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))),
                        onChanged: (v) => setState(() => _deck = v),
                      ),
                    ),
                  ],
                ),
              ),
              Builder(builder: (context) {
                final shown = [
                  for (final r in list)
                    if ((_query.isEmpty || r.nickname.toLowerCase().contains(_query)) &&
                        (_deck == null || (decksByPlayer[r.playerId]?.contains(_deck) ?? false)))
                      r,
                ];
                return shown.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: EmptyState(icon: Icons.search_off, title: 'Nadie coincide'),
                      )
                    : RankingTable(rows: shown, meId: ref.watch(permissionsProvider).playerId);
              }),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'En verde, los 8 primeros (más claro, mejor puesto); en amarillo, tú. '
                  'Mazo = el último que jugó; el filtro de mazo incluye a todos los que lo '
                  'jugaron en algún torneo de la temporada. '
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
  }
}

/// Compartir el ranking como imagen.
Future<void> shareRanking(BuildContext context, Season season, List<RankingRow> rows) async {
  try {
    await exportRankingImage(context, season: season, rows: rows);
  } catch (e) {
    if (context.mounted) showMessage(context, 'No se pudo compartir la imagen: $e', error: true);
  }
}

/// Qué suma el ranking global.
class _GlobalInfo extends StatelessWidget {
  const _GlobalInfo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        'Ranking global: suma los puntos, partidas y torneos de todas las temporadas. '
        'Mejor posición = la mejor de todas.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
              child: Text(
                  isHistoricSeason(season)
                      ? 'Ranking final importado (antes de la app): sin partidas ni mazos'
                      : 'Temporada cerrada$when · ranking definitivo',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Cerrar la temporada (irreversible: se guarda el ranking definitivo).
Future<void> closeSeason(BuildContext context, WidgetRef ref, Season season) {
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

/// Filtro por mazo del ranking: un campo con borde igual que el buscador.
class _DeckFilter extends StatelessWidget {
  const _DeckFilter({required this.value, required this.decks, required this.onChanged});

  final String? value;
  final List<String> decks;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      // Se reconstruye si el mazo elegido deja de existir.
      key: ValueKey(decks.contains(value) ? value : null),
      initialValue: decks.contains(value) ? value : null,
      isExpanded: true,
      isDense: true,
      borderRadius: BorderRadius.circular(12),
      decoration: const InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.style_outlined),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Todos los mazos', overflow: TextOverflow.ellipsis)),
        for (final d in decks)
          DropdownMenuItem<String?>(value: d, child: Text(d, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }
}

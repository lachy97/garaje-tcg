import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/utils/season_utils.dart';
import '../../ranking/presentation/season_picker.dart';
import '../domain/deck_matchups.dart';
import '../domain/deck_stats.dart';
import 'deck_image.dart';
import 'deck_matrix.dart';
import 'deck_tier_table.dart' show TierBadge;
import 'decks_page.dart' show seasonDecksProvider;

final _deckEntriesProvider = StreamProvider.autoDispose
    .family<List<DeckTournamentEntry>, (String, String)>((ref, key) {
  return ref.watch(rankingDaoProvider).watchDeckEntries(key.$1, key.$2);
});

/// Ficha de un mazo en una temporada: resumen, torneos (con el Power que
/// aportó cada resultado), pilotos y enfrentamientos.
class DeckDetailPage extends ConsumerWidget {
  const DeckDetailPage({super.key, required this.deckId, required this.seasonId});

  final String deckId;
  final String seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(seasonDecksProvider(seasonId));
    final season = (ref.watch(seasonListProvider).value ?? const [])
        .where((s) => s.id == seasonId)
        .firstOrNull;
    return AsyncView(
      value: stats,
      builder: (all) {
        final d = all.where((x) => x.deckId == deckId).firstOrNull;
        if (d == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
                icon: Icons.style_outlined, title: 'Este mazo no jugó en la temporada'),
          );
        }
        final names = {for (final x in all) x.deckId: x.name};
        return Scaffold(
          appBar: AppBar(title: Text(d.name.toUpperCase(), overflow: TextOverflow.ellipsis)),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              _Header(deck: d, season: season == null ? '' : seasonLabel(season.year, season.quarter)),
              const SectionLabel('Torneos'),
              _Entries(seasonId: seasonId, deckId: deckId),
              const SectionLabel('Enfrentamientos'),
              _Matchups(seasonId: seasonId, deckId: deckId, names: names),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.deck, required this.season});

  final DeckSeasonStats deck;
  final String season;

  @override
  Widget build(BuildContext context) {
    String pct(double v) => '${(v * 100).round()} %';
    Widget stat(String label, String value) => Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.neon)),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        );
    return NeonCard(
      child: Column(
        children: [
          Row(
            children: [
              DeckImage(path: deck.imagePath, name: deck.name, width: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deck.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text('Temporada $season · puesto ${deck.rank}',
                        style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              TierBadge(deck.tier, size: 36),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              stat('Power', '${deck.power}'),
              stat('Presencia', pct(deck.presence)),
              stat('Conversión', pct(deck.conversion)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              stat('Inscripciones', '${deck.entries}'),
              stat('Pilotos', '${deck.pilots.length}'),
              stat('Tops', '${deck.topEntries}'),
              stat('Títulos', '${deck.titles}'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Partidas: ${deck.wins}-${deck.losses}-${deck.swissDraws} '
            '(${deck.played == 0 ? '-' : pct(deck.winrate)} de victorias)',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Entries extends ConsumerWidget {
  const _Entries({required this.seasonId, required this.deckId});

  final String seasonId;
  final String deckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = DateFormat('dd/MM/yyyy');
    return AsyncView(
      value: ref.watch(_deckEntriesProvider((seasonId, deckId))),
      builder: (list) {
        if (list.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Sin torneos terminados con este mazo.',
                style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        return Column(
          children: [
            for (final e in list)
              ListTile(
                dense: true,
                onTap: () => context.push('/jugadores/${e.playerId}'),
                leading: SizedBox(
                  width: 40,
                  child: Text(e.finalPosition == null ? '-' : '${e.finalPosition}º',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: e.madeTop ? AppColors.neon : AppColors.textSecondary,
                      )),
                ),
                title: Text(e.playerName, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${e.tournamentName} · ${day.format(e.date)}'),
                trailing: e.power > 0
                    ? Text('+${e.power}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, color: AppColors.neon))
                    : null,
              ),
          ],
        );
      },
    );
  }
}

class _Matchups extends ConsumerWidget {
  const _Matchups({required this.seasonId, required this.deckId, required this.names});

  final String seasonId;
  final String deckId;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(seasonMatchupsProvider(seasonId)),
      builder: (m) {
        final row = m.rowOf(deckId);
        if (row.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Sin partidas registradas.',
                style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        return Column(
          children: [
            for (final (other, rec) in row)
              ListTile(
                dense: true,
                title: Text(other == deckId ? 'Espejo' : names[other] ?? 'Otro mazo'),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: other == deckId ? null : matchupColor(rec),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    other == deckId
                        ? '${rec.played}'
                        : '$rec · ${(rec.winrate * 100).round()} %',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

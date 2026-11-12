import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../tournaments/application/tournament_service.dart';
import '../../tournaments/presentation/providers.dart';
import 'deck_list_editor_page.dart';
import 'top_deck_lists_section.dart';

/// Listas del Top Cut mientras se juega (organizador): se suben antes de
/// terminar y, según "quién ve las listas", llegan a los jugadores al momento,
/// solo el mazo o al terminar.
class TopCutListsPage extends ConsumerWidget {
  const TopCutListsPage({super.key, required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tournament;
    final rounds = ref.watch(roundsProvider(t.id)).value ?? const <Round>[];
    final matches = ref.watch(tournamentMatchesProvider(t.id)).value ?? const <Match>[];
    final standings = ref.watch(standingsProvider(t.id)).value ?? const [];
    final registered = ref.watch(registeredProvider(t.id)).value ?? const [];
    final byId = {for (final r in registered) r.player.id: r};
    final rank = {for (final s in standings) s.playerId: s.rank};

    // Los del Top Cut: quienes juegan la primera ronda del Top.
    final firstTop = rounds.where((r) => r.phase == RoundPhase.topCut).firstOrNull;
    final ids = <String>{
      if (firstTop != null)
        for (final m in matches)
          if (m.roundId == firstTop.id) ...[m.player1Id, if (m.player2Id != null) m.player2Id!],
    };
    final targets = [
      for (final id in ids)
        DeckListTarget(
          tournamentId: t.id,
          tournamentName: t.name,
          date: t.date,
          playerId: id,
          playerName: byId[id]?.player.nickname ?? '?',
          position: rank[id],
          deckName: byId[id]?.deck?.name,
        ),
    ]..sort((a, b) => (a.position ?? 999).compareTo(b.position ?? 999));

    return Scaffold(
      appBar: AppBar(title: const Text('LISTAS DEL TOP CUT')),
      body: targets.isEmpty
          ? const Center(child: Text('El Top Cut aún no ha empezado.'))
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [TopDeckListsSection(tournamentId: t.id, targets: targets)],
            ),
    );
  }
}

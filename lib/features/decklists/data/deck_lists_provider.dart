import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import '../domain/deck_list.dart';

/// Listas de mazos guardadas de un torneo, por jugador.
final tournamentDeckListsProvider =
    StreamProvider.autoDispose.family<Map<String, DeckList>, String>((ref, tournamentId) {
  return ref
      .watch(tournamentsDaoProvider)
      .watchDeckLists(tournamentId)
      .map((list) => {for (final d in list) d.playerId: d});
});

/// Cartas de una lista guardada.
DeckCards cardsOf(DeckList d) => DeckCards(
      main: DeckCards.parseCodes(d.mainDeck),
      extra: DeckCards.parseCodes(d.extraDeck),
      side: DeckCards.parseCodes(d.sideDeck),
    );

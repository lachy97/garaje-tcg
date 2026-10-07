import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/tournaments_dao.dart';
import '../../../core/db/database_provider.dart';

final tournamentsProvider = StreamProvider.autoDispose<List<Tournament>>((ref) {
  return ref.watch(tournamentsDaoProvider).watchAll();
});

final tournamentProvider =
    StreamProvider.autoDispose.family<Tournament?, String>((ref, id) {
  return ref.watch(tournamentsDaoProvider).watchById(id);
});

final registeredProvider =
    StreamProvider.autoDispose.family<List<RegisteredPlayer>, String>((ref, id) {
  return ref.watch(tournamentsDaoProvider).watchRegistered(id);
});

final roundsProvider = StreamProvider.autoDispose.family<List<Round>, String>((ref, id) {
  return ref.watch(tournamentsDaoProvider).watchRounds(id);
});

final roundMatchesProvider =
    StreamProvider.autoDispose.family<List<Match>, String>((ref, roundId) {
  return ref.watch(tournamentsDaoProvider).watchMatchesOfRound(roundId);
});

final tournamentResultsProvider =
    StreamProvider.autoDispose.family<List<SeasonResult>, String>((ref, id) {
  return ref.watch(rankingDaoProvider).watchTournamentResults(id);
});

/// Textos de estado para la UI.
String statusLabel(TournamentStatus s) => switch (s) {
      TournamentStatus.draft => 'Inscripción',
      TournamentStatus.swiss => 'Swiss',
      TournamentStatus.topCut => 'Top Cut',
      TournamentStatus.finished => 'Terminado',
    };

/// Nombre de una ronda: "Ronda 3", "Cuartos", "Semis", "Final"...
String roundLabel(Round r) {
  if (r.phase == RoundPhase.swiss) return 'Ronda ${r.number}';
  return switch (r.bracketSize) {
    2 => 'Final',
    4 => 'Semis',
    8 => 'Cuartos',
    final n? => 'Top $n',
    null => 'Top Cut',
  };
}

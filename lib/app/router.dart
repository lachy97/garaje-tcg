import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/decks/presentation/deck_manage_page.dart';
import '../features/decks/presentation/decks_page.dart';
import '../features/players/presentation/player_profile_page.dart';
import '../features/players/presentation/players_page.dart';
import '../features/ranking/presentation/ranking_page.dart';
import '../features/tournaments/presentation/create_tournament_page.dart';
import '../features/tournaments/presentation/tournament_detail_page.dart';
import '../features/tournaments/presentation/tournaments_page.dart';
import 'theme.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/torneos',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/torneos',
              builder: (_, _) => const TournamentsPage(),
              routes: [
                // Pantallas a pantalla completa (sin barra inferior)
                GoRoute(
                  path: 'nuevo',
                  parentNavigatorKey: _rootKey,
                  builder: (_, _) => const CreateTournamentPage(),
                ),
                GoRoute(
                  path: ':id',
                  parentNavigatorKey: _rootKey,
                  builder: (_, state) =>
                      TournamentDetailPage(tournamentId: state.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/ranking', builder: (_, _) => const RankingPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/mazos',
              builder: (_, _) => const DecksPage(),
              routes: [
                GoRoute(
                  path: 'gestionar',
                  parentNavigatorKey: _rootKey,
                  builder: (_, _) => const DeckManagePage(),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/jugadores',
              builder: (_, _) => const PlayersPage(),
              routes: [
                GoRoute(
                  path: ':id',
                  parentNavigatorKey: _rootKey,
                  builder: (_, state) =>
                      PlayerProfilePage(playerId: state.pathParameters['id']!),
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
});

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.outline, width: 0.6)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) =>
              shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.emoji_events_outlined),
                selectedIcon: Icon(Icons.emoji_events),
                label: 'Torneos'),
            NavigationDestination(
                icon: Icon(Icons.leaderboard_outlined),
                selectedIcon: Icon(Icons.leaderboard),
                label: 'Ranking'),
            NavigationDestination(
                icon: Icon(Icons.style_outlined),
                selectedIcon: Icon(Icons.style),
                label: 'Mazos'),
            NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Jugadores'),
          ],
        ),
      ),
    );
  }
}

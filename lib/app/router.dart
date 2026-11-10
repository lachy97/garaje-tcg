import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/decks/presentation/deck_detail_page.dart';
import '../features/decks/presentation/deck_manage_page.dart';
import '../features/decks/presentation/decks_page.dart';
import '../features/players/presentation/player_profile_page.dart';
import '../features/players/presentation/players_page.dart';
import '../features/license/admin_page.dart';
import '../features/ranking/presentation/ranking_page.dart';
import '../features/settings/settings_page.dart';
import '../features/tournaments/presentation/create_tournament_page.dart';
import '../features/tournaments/presentation/tournament_detail_page.dart';
import '../features/tournaments/presentation/tournaments_page.dart';
import '../core/auth/auth_providers.dart';
import '../core/sync/sync_service.dart';
import 'theme.dart';

/// Navigator raíz (también lo usa el aviso de licencia por vencer).
final rootNavigatorKey = GlobalKey<NavigatorState>();
final _rootKey = rootNavigatorKey;

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/torneos',
    routes: [
      // Fuera del shell: pantallas completas sin barra inferior.
      GoRoute(
        path: '/ajustes',
        builder: (_, _) => const SettingsPage(),
        routes: [
          GoRoute(path: 'admin', builder: (_, _) => const AdminPage()),
        ],
      ),
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
                GoRoute(
                  path: 'ficha/:id',
                  parentNavigatorKey: _rootKey,
                  builder: (_, state) => DeckDetailPage(
                    deckId: state.pathParameters['id']!,
                    seasonId: state.uri.queryParameters['t'] ?? '',
                  ),
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

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permissionsProvider);
    final preview = ref.watch(rolePreviewProvider);
    // Mantiene viva la subida automática de datos al servidor.
    ref.listen(syncControllerProvider, (_, _) {});
    final allPlayers = perms.canSeeAllPlayers;
    return Scaffold(
      body: Column(
        children: [
          // "Ver la app como…" activo: aviso fijo arriba para volver.
          if (preview != null)
            Material(
              color: AppColors.draw.withValues(alpha: 0.18),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility_outlined, size: 18, color: AppColors.draw),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Viendo la app como ${preview.label}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.draw)),
                      ),
                      TextButton(
                        onPressed: () => ref.read(rolePreviewProvider.notifier).set(null),
                        child: const Text('Volver'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: preview == null
                ? shell
                : MediaQuery.removePadding(context: context, removeTop: true, child: shell),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.outline, width: 0.6)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) =>
              shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: [
            const NavigationDestination(
                icon: Icon(Icons.emoji_events_outlined),
                selectedIcon: Icon(Icons.emoji_events),
                label: 'Torneos'),
            const NavigationDestination(
                icon: Icon(Icons.leaderboard_outlined),
                selectedIcon: Icon(Icons.leaderboard),
                label: 'Ranking'),
            const NavigationDestination(
                icon: Icon(Icons.style_outlined),
                selectedIcon: Icon(Icons.style),
                label: 'Mazos'),
            // Sin permiso para ver a todos, la pestaña es la ficha propia.
            NavigationDestination(
                icon: Icon(allPlayers ? Icons.people_outline : Icons.person_outline),
                selectedIcon: Icon(allPlayers ? Icons.people : Icons.person),
                label: allPlayers ? 'Jugadores' : 'Mi ficha'),
          ],
        ),
      ),
    );
  }
}

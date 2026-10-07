import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/app_database.dart';
import 'providers.dart';
import 'tabs/registration_tab.dart';
import 'tabs/rounds_tab.dart';
import 'tabs/standings_tab.dart';

class TournamentDetailPage extends ConsumerWidget {
  const TournamentDetailPage({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournament = ref.watch(tournamentProvider(tournamentId));
    return AsyncView(
      value: tournament,
      builder: (t) {
        if (t == null || t.deletedAt != null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.search_off, title: 'Torneo no encontrado'),
          );
        }
        // Pestaña inicial según la fase: inscripción → rondas → clasificación
        final initial = switch (t.status) {
          TournamentStatus.draft => 0,
          TournamentStatus.swiss || TournamentStatus.topCut => 1,
          TournamentStatus.finished => 2,
        };
        return DefaultTabController(
          length: 3,
          initialIndex: initial,
          child: Scaffold(
            appBar: AppBar(
              title: Text(t.name.toUpperCase(), overflow: TextOverflow.ellipsis),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(84),
                child: Column(
                  children: [
                    _Header(t: t),
                    const TabBar(
                      labelColor: AppColors.neon,
                      unselectedLabelColor: AppColors.textSecondary,
                      indicatorColor: AppColors.neon,
                      dividerColor: Colors.transparent,
                      tabs: [
                        Tab(text: 'Jugadores'),
                        Tab(text: 'Rondas'),
                        Tab(text: 'Clasificación'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            body: TabBarView(
              children: [
                RegistrationTab(tournament: t),
                RoundsTab(tournament: t),
                StandingsTab(tournament: t),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.t});

  final Tournament t;

  @override
  Widget build(BuildContext context) {
    final parts = [
      DateFormat.yMMMd('es').format(t.date),
      '${t.swissRounds} rondas',
      t.topCutSize == 0 ? 'Sin Top' : 'Top ${t.topCutSize}',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.forest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.neon, width: 0.8),
            ),
            child: Text(statusLabel(t.status),
                style: const TextStyle(
                    color: AppColors.neon, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(parts.join(' · '),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

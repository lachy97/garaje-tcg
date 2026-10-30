import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../data/deck_lists_provider.dart';
import 'deck_list_editor_page.dart';
import 'deck_list_page.dart';

/// "Listas del Top 4" en el resumen de un torneo terminado: cada jugador con
/// su estado (lista subida o no). Tocar abre su lista o la pantalla de subirla.
class TopDeckListsSection extends ConsumerWidget {
  const TopDeckListsSection({super.key, required this.tournamentId, required this.targets});

  final String tournamentId;
  final List<DeckListTarget> targets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (targets.isEmpty) return const SizedBox.shrink();
    final saved = ref.watch(tournamentDeckListsProvider(tournamentId)).value ?? const {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel('Listas del Top ${targets.length}'),
        for (final t in targets)
          NeonCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => DeckListPage(target: t))),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text('${t.position ?? '-'}º',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.neon)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.playerName, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(t.deckName ?? 'Sin mazo',
                          style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if (saved.containsKey(t.playerId))
                  const Chip(
                    avatar: Icon(Icons.check, size: 16, color: AppColors.neon),
                    label: Text('Ver lista'),
                  )
                else
                  const Chip(
                    avatar: Icon(Icons.upload, size: 16),
                    label: Text('Subir lista'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

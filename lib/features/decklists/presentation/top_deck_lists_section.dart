import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/sync/sync_service.dart';
import '../../tournaments/presentation/providers.dart';
import '../data/card_images.dart';
import '../data/deck_lists_provider.dart';
import '../domain/card_db.dart';
import 'deck_list_editor_page.dart';
import 'deck_list_export.dart';
import 'deck_list_page.dart';

/// Quién ve las listas (columna `tournaments.list_visibility`).
const _visibilityOptions = [
  ('open', 'Las listas en cuanto se suben'),
  ('archetype', 'Solo el mazo, sin las cartas'),
  ('after', 'Las listas al terminar el torneo'),
];

/// "Listas" del Top Cut en el resumen de un torneo terminado: cada jugador con
/// su estado (lista subida o no). Tocar abre su lista o la pantalla de subirla;
/// "Compartir todas" comparte de una vez las listas subidas (imágenes o .ydk).
class TopDeckListsSection extends ConsumerWidget {
  const TopDeckListsSection({super.key, required this.tournamentId, required this.targets});

  final String tournamentId;
  final List<DeckListTarget> targets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (targets.isEmpty) return const SizedBox.shrink();
    final saved = ref.watch(tournamentDeckListsProvider(tournamentId)).value ?? const {};
    final canEdit = ref.watch(permissionsProvider).canManageTournament(isOwner: true);
    final visibility = ref.watch(tournamentProvider(tournamentId)).value?.listVisibility ?? 'open';
    // Solo se comparten las que ya están subidas.
    final uploaded = [for (final t in targets) if (saved.containsKey(t.playerId)) t];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: SectionLabel('Listas del Top ${targets.length}')),
            if (canEdit)
              PopupMenuButton<String>(
                tooltip: 'Quién ve las listas',
                icon: Icon(Icons.visibility_outlined, color: AppColors.textSecondary),
                initialValue: visibility,
                onSelected: (v) => runGuarded(context, () async {
                  await ref.read(tournamentsDaoProvider).updateSettings(tournamentId, listVisibility: v);
                  await ref.read(syncControllerProvider.notifier).sync();
                }),
                itemBuilder: (_) => [
                  for (final (v, label) in _visibilityOptions)
                    CheckedPopupMenuItem(value: v, checked: v == visibility, child: Text(label)),
                ],
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 8),
              child: TextButton.icon(
                onPressed: uploaded.isEmpty ? null : () => _shareAll(context, ref, uploaded, saved),
                icon: const Icon(Icons.share, size: 18),
                label: Text(uploaded.length == targets.length
                    ? 'Compartir todas'
                    : 'Compartir ${uploaded.length} de ${targets.length}'),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            'Los jugadores ven: ${_visibilityOptions.firstWhere((o) => o.$1 == visibility, orElse: () => _visibilityOptions.first).$2.toLowerCase()}.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
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
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.neon)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.playerName, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(t.deckName ?? 'Sin mazo',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if (saved.containsKey(t.playerId))
                  Chip(
                    avatar: Icon(Icons.check, size: 16, color: AppColors.neon),
                    label: Text('Ver lista'),
                  )
                else if (canEdit)
                  const Chip(
                    avatar: Icon(Icons.upload, size: 16),
                    label: Text('Subir lista'),
                  )
                else
                  const Chip(label: Text('Sin publicar')),
              ],
            ),
          ),
      ],
    );
  }

  /// Todas las listas subidas del Top Cut de una vez: imágenes o .ydk.
  Future<void> _shareAll(
    BuildContext context,
    WidgetRef ref,
    List<DeckListTarget> uploaded,
    Map<String, DeckList> saved,
  ) async {
    final option = await askDeckListShare(context, count: uploaded.length);
    if (option == null || !context.mounted) return;
    final store = ref.read(cardImageStoreProvider);
    CardDb? db;
    if (option != DeckListShare.ydk) {
      try {
        db = await ref.read(cardDbProvider.future);
      } catch (_) {
        db = null; // shareDeckLists avisa de que falta la base de cartas
      }
    }
    if (!context.mounted) return;
    await shareDeckLists(
      context,
      option: option,
      lists: [
        for (final t in uploaded)
          (target: t, cards: cardsOf(saved[t.playerId]!), featured: saved[t.playerId]!.featuredCard),
      ],
      db: db,
      store: store,
    );
  }
}

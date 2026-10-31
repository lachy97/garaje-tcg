import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import '../data/card_images.dart';
import '../data/deck_lists_provider.dart';
import '../domain/card_db.dart';
import '../domain/deck_list.dart';
import 'card_image.dart';
import 'deck_list_editor_page.dart';
import 'deck_list_export.dart';

/// Ver la lista de un jugador: carta principal, Main/Extra/Side. Desde aquí
/// se exporta la imagen, se comparte el .ydk, se edita o se borra. Si aún no
/// tiene lista, ofrece subirla.
class DeckListPage extends ConsumerWidget {
  const DeckListPage({super.key, required this.target});

  final DeckListTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(tournamentDeckListsProvider(target.tournamentId));
    final db = ref.watch(cardDbProvider);
    final saved = lists.value?[target.playerId];
    final cards = saved == null ? null : cardsOf(saved);
    final cardDb = db.value;
    return Scaffold(
      appBar: AppBar(
        title: Text('LISTA · ${target.playerName.toUpperCase()}',
            overflow: TextOverflow.ellipsis),
        actions: [
          if (saved != null && cardDb != null) ...[
            IconButton(
              tooltip: 'Exportar imagen',
              icon: const Icon(Icons.ios_share),
              onPressed: () async {
                final choice = await askDeckListStyle(context);
                if (choice == null || !context.mounted) return;
                await exportDeckListImage(
                  context,
                  style: choice.$1,
                  format: choice.$2,
                  target: target,
                  cards: cards!,
                  featured: saved.featuredCard,
                  secondary: saved.secondaryCard,
                  background: saved.backgroundCard,
                  db: cardDb,
                  store: ref.read(cardImageStoreProvider),
                );
              },
            ),
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'edit' => _edit(context, cards, saved),
                'ydk' => _shareYdk(context, cards!),
                'delete' => _delete(context, ref),
                _ => null,
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Editar lista')),
                PopupMenuItem(value: 'ydk', child: Text('Compartir .ydk')),
                PopupMenuItem(value: 'delete', child: Text('Borrar lista')),
              ],
            ),
          ],
        ],
      ),
      body: AsyncView(
        value: lists,
        builder: (_) {
          if (saved == null || cards == null) {
            return EmptyState(
              icon: Icons.style_outlined,
              title: 'Sin lista todavía',
              subtitle: 'Importa el .ydk del jugador o escribe la lista a mano.',
              action: FilledButton.icon(
                onPressed: () => _edit(context, null, null),
                icon: const Icon(Icons.add),
                label: const Text('Subir lista'),
              ),
            );
          }
          if (cardDb == null) {
            return db.hasError
                ? Center(child: Text('Error al leer la base de cartas: ${db.error}'))
                : const Center(child: CircularProgressIndicator());
          }
          final featured = saved.featuredCard == null ? null : cardDb.byId(saved.featuredCard!);
          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              NeonCard(
                child: Row(
                  children: [
                    if (featured != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CardImage(
                            id: featured.id,
                            name: featured.name,
                            size: CardImageSize.art,
                            width: 110),
                      ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (target.position != null)
                            Text('${target.position}º lugar',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, color: AppColors.neon)),
                          Text(target.playerName,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                          Text(target.deckName ?? 'Sin mazo',
                              style: const TextStyle(color: AppColors.textSecondary)),
                          const SizedBox(height: 6),
                          Text(
                            'Main ${cards.main.length} · Extra ${cards.extra.length} · '
                            'Side ${cards.side.length}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              for (final w in validateDeck(cards, cardDb))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
                  child: Text('⚠ $w',
                      style: const TextStyle(fontSize: 12, color: AppColors.draw)),
                ),
              for (final s in DeckSection.values)
                if (cards.of(s).isNotEmpty) ...[
                  SectionLabel('${s.label} (${cards.of(s).length})'),
                  _Grid(rows: groupedSection(cards, s, cardDb)),
                ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, DeckCards? cards, DeckList? saved) {
    return Navigator.of(context).push(MaterialPageRoute<bool>(
      builder: (_) => DeckListEditorPage(
        target: target,
        initial: cards,
        initialFeatured: saved?.featuredCard,
        initialSecondary: saved?.secondaryCard,
        initialBackground: saved?.backgroundCard,
      ),
    ));
  }

  Future<void> _shareYdk(BuildContext context, DeckCards cards) async {
    try {
      final dir = await getTemporaryDirectory();
      final name = '${target.playerName}_${target.deckName ?? 'mazo'}'
          .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
      final file = File('${dir.path}/$name.ydk');
      await file.writeAsString(cards.toYdk(), flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain', name: '$name.ydk')],
        text: '${target.playerName} · ${target.deckName ?? ''} · ${target.tournamentName}',
      ));
    } catch (e) {
      if (context.mounted) showMessage(context, 'No se pudo compartir: $e', error: true);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(context,
        title: 'Borrar lista',
        message: '¿Borrar la lista de ${target.playerName}?',
        confirm: 'Borrar',
        danger: true);
    if (!ok || !context.mounted) return;
    await runGuarded(context,
        () => ref.read(tournamentsDaoProvider).deleteDeckList(target.tournamentId, target.playerId));
  }
}

/// Cartas agrupadas con su número de copias.
class _Grid extends StatelessWidget {
  const _Grid({required this.rows});

  final List<(YgoCard, int)> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (card, n) in rows)
            Tooltip(
              message: card.name,
              child: Stack(
                children: [
                  CardImage(id: card.id, name: card.name, width: 62),
                  if (n > 1)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.neon),
                        ),
                        child: Text('×$n',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.neon)),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

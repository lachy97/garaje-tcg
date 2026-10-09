import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import '../domain/deck_catalog.dart';
import 'deck_image.dart';
import 'deck_picker.dart';
import 'decks_page.dart' show decksProvider;

/// Gestión de mazos (pantalla secundaria de "Mazos"): la lista de Edison
/// Format viene cargada con sus imágenes; aquí se añaden mazos nuevos (con foto
/// opcional), se cambian imágenes, se corrigen nombres y se fusionan duplicados.
class DeckManagePage extends ConsumerWidget {
  const DeckManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('GESTIONAR MAZOS')),
      body: AsyncView(
        value: decks,
        builder: (raw) => raw.isEmpty
            ? const EmptyState(
                icon: Icons.style_outlined,
                title: 'Aún no hay mazos',
                subtitle: 'Se crean al inscribir jugadores en un torneo, o con el botón +.',
              )
            : ListView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 96),
                itemCount: raw.length,
                itemBuilder: (_, i) => _DeckTile(deck: raw[i], all: raw),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Mazo'),
        onPressed: () => addDeckFlow(context, ref),
      ),
    );
  }
}

class _DeckTile extends ConsumerWidget {
  const _DeckTile({required this.deck, required this.all});

  final Deck deck;
  final List<Deck> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NeonCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          DeckImage(path: deck.imagePath, name: deck.name, width: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deck.name, style: Theme.of(context).textTheme.titleMedium),
                Text(deckCategoryOf(deck).label,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
            onSelected: (v) => switch (v) {
              'rename' => _rename(context, ref),
              'image' => _changeImage(context, ref),
              'noimage' => _removeImage(context, ref),
              _ => _merge(context, ref),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Renombrar')),
              const PopupMenuItem(value: 'image', child: Text('Cambiar imagen')),
              if (deck.imagePath != null)
                const PopupMenuItem(value: 'noimage', child: Text('Quitar imagen')),
              const PopupMenuItem(value: 'merge', child: Text('Fusionar con otro mazo')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _changeImage(BuildContext context, WidgetRef ref) async {
    final photo = await pickDeckPhoto();
    if (photo == null || !context.mounted) return;
    await runGuarded(context,
        () => saveDeckPhoto(ref.read(decksDaoProvider), deck.id, photo),
        success: 'Imagen actualizada');
  }

  Future<void> _removeImage(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Quitar imagen',
      message: '"${deck.name}" se mostrará sin imagen (con su nombre).',
      confirm: 'Quitar',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    await ref.read(decksDaoProvider).setImage(deck.id, null);
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await promptText(context,
        title: 'Renombrar mazo', label: 'Nombre', initial: deck.name);
    if (name == null || name.isEmpty || !context.mounted) return;
    await runGuarded(context, () => ref.read(decksDaoProvider).rename(deck.id, name));
  }

  Future<void> _merge(BuildContext context, WidgetRef ref) async {
    final others = all.where((d) => d.id != deck.id).toList();
    if (others.isEmpty) {
      showMessage(context, 'No hay otro mazo con el que fusionar.');
      return;
    }
    final target = await showDialog<Deck>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Fusionar "${deck.name}" en…'),
        children: [
          for (final d in others)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d),
              child: Text(d.name, style: const TextStyle(fontSize: 16)),
            ),
        ],
      ),
    );
    if (target == null || !context.mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Confirmar fusión',
      message: 'Todas las partidas de "${deck.name}" pasarán a "${target.name}" '
          'y "${deck.name}" desaparecerá.',
      confirm: 'Fusionar',
    );
    if (!ok || !context.mounted) return;
    await runGuarded(
      context,
      () => ref.read(decksDaoProvider).merge(fromId: deck.id, intoId: target.id),
      success: 'Mazos fusionados',
    );
  }
}

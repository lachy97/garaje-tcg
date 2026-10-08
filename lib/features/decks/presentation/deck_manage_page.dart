import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import 'decks_page.dart' show decksProvider;

/// Gestión de mazos (pantalla secundaria de "Mazos"). Se crean solos al
/// inscribir a un jugador con un mazo nuevo; aquí se corrigen nombres y se
/// fusionan duplicados para que la tier list no los cuente por separado.
class DeckManagePage extends ConsumerWidget {
  const DeckManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('GESTIONAR MAZOS')),
      body: AsyncView(
        value: decks,
        builder: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.style_outlined,
                title: 'Aún no hay mazos',
                subtitle: 'Se crean al inscribir jugadores en un torneo, o con el botón +.',
              )
            : ListView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 96),
                itemCount: list.length,
                itemBuilder: (_, i) => _DeckTile(deck: list[i], all: list),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Mazo'),
        onPressed: () async {
          final name = await promptText(context,
              title: 'Nuevo mazo', label: 'Nombre del mazo', confirm: 'Crear');
          if (name == null || name.isEmpty || !context.mounted) return;
          await runGuarded(context, () => ref.read(decksDaoProvider).findOrCreate(name));
        },
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
          const Icon(Icons.style, color: AppColors.leaf),
          const SizedBox(width: 12),
          Expanded(
            child: Text(deck.name, style: Theme.of(context).textTheme.titleMedium),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
            onSelected: (v) => v == 'rename' ? _rename(context, ref) : _merge(context, ref),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Renombrar')),
              PopupMenuItem(value: 'merge', child: Text('Fusionar con otro mazo')),
            ],
          ),
        ],
      ),
    );
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

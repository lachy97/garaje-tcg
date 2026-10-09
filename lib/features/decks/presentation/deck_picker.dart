import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/daos/decks_dao.dart';
import '../../../core/db/database_provider.dart';
import '../domain/deck_catalog.dart';
import 'deck_image.dart';
import 'decks_page.dart' show decksProvider;

/// Categoría de un mazo de la BD (los que no están en el catálogo: "Añadidos").
DeckCategory deckCategoryOf(Deck d) =>
    kDeckCatalogByName[d.normalizedName]?.category ?? DeckCategory.custom;

/// Orden: catálogo (competitivos, rogue, casual, como en edisonformat.net) y
/// después los añadidos por nombre.
List<Deck> sortDecks(List<Deck> decks) {
  final order = {for (var i = 0; i < kDeckCatalog.length; i++) kDeckCatalog[i].name.toLowerCase(): i};
  return [...decks]..sort((a, b) {
      final ia = order[a.normalizedName] ?? 1 << 20;
      final ib = order[b.normalizedName] ?? 1 << 20;
      return ia != ib ? ia.compareTo(ib) : a.normalizedName.compareTo(b.normalizedName);
    });
}

/// Abre la lista de mazos con imagen para elegir uno. Devuelve el nombre del
/// mazo elegido (o creado) o null si se cancela.
Future<String?> showDeckPicker(BuildContext context, {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _DeckPicker(current: current),
    ),
  );
}

class _DeckPicker extends ConsumerStatefulWidget {
  const _DeckPicker({this.current});

  final String? current;

  @override
  ConsumerState<_DeckPicker> createState() => _DeckPickerState();
}

class _DeckPickerState extends ConsumerState<_DeckPicker> {
  String _query = '';
  DeckCategory? _category; // null = todos

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(decksProvider).value ?? const <Deck>[];
    final q = _query.trim().toLowerCase();
    final list = all
        .where((d) => _category == null || deckCategoryOf(d) == _category)
        .where((d) => q.isEmpty || d.normalizedName.contains(q))
        .toList();
    final current = widget.current?.toLowerCase();

    return Column(
      children: [
        const Text('Elegir mazo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar mazo',
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final c in [null, ...DeckCategory.values])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(c?.label ?? 'Todos'),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: () async {
              final name = await showNewDeckDialog(context, ref, initialName: _query.trim());
              if (name != null && context.mounted) Navigator.pop(context, name);
            },
            icon: const Icon(Icons.add),
            label: const Text('Añadir un mazo que no está en la lista'),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: list.isEmpty
              ? const Center(
                  child: Text('Ningún mazo coincide',
                      style: TextStyle(color: AppColors.textSecondary)))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 120,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.52,
                  ),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final d = list[i];
                    final selected = d.normalizedName == current;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => Navigator.pop(context, d.name),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected ? AppColors.neon : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: LayoutBuilder(
                          builder: (_, c) => Column(
                            children: [
                              DeckImage(path: d.imagePath, name: d.name, width: c.maxWidth),
                              const SizedBox(height: 4),
                              Text(
                                d.name,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.15,
                                  fontWeight: FontWeight.w700,
                                  color: selected ? AppColors.neon : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ───────────────────── Mazos nuevos e imágenes ─────────────────────

/// Elige una foto de la galería (reducida) para un mazo. null si se cancela.
Future<XFile?> pickDeckPhoto() =>
    ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 500, imageQuality: 85);

/// Copia la foto a la carpeta de la app y la asigna al mazo.
Future<void> saveDeckPhoto(DecksDao dao, String deckId, XFile photo) async {
  final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/deck_images');
  if (!await dir.exists()) await dir.create(recursive: true);
  final dot = photo.path.lastIndexOf('.');
  final ext = dot > 0 ? photo.path.substring(dot) : '.jpg';
  // Nombre nuevo cada vez: así la imagen se refresca aunque Flutter la tenga en caché.
  final file = File('${dir.path}/${deckId}_${DateTime.now().millisecondsSinceEpoch}$ext');
  await file.writeAsBytes(await photo.readAsBytes(), flush: true);
  await dao.setImage(deckId, file.path);
}

/// Diálogo para añadir un mazo que no está en el catálogo, con foto opcional.
/// Devuelve el nombre del mazo creado (o el existente si ya estaba).
Future<String?> showNewDeckDialog(BuildContext context, WidgetRef ref,
    {String initialName = ''}) {
  final name = TextEditingController(text: initialName);
  XFile? photo;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Nuevo mazo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre del mazo'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: photo == null
                      ? DeckImage(path: null, name: name.text, width: 56)
                      : Image.file(File(photo!.path),
                          width: 56, height: 56 / kDeckImageAspect, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final p = await pickDeckPhoto();
                      if (p != null) setState(() => photo = p);
                    },
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(photo == null ? 'Elegir imagen (opcional)' : 'Cambiar imagen'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final n = cleanDeckName(name.text);
              if (n.isEmpty) return;
              final dao = ref.read(decksDaoProvider);
              final deck = await dao.findOrCreate(n);
              if (photo != null) await saveDeckPhoto(dao, deck.id, photo!);
              if (ctx.mounted) Navigator.pop(ctx, deck.name);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}

/// Atajo para pantallas que solo necesitan mostrar un mensaje tras guardar.
Future<void> addDeckFlow(BuildContext context, WidgetRef ref) async {
  final n = await showNewDeckDialog(context, ref);
  if (n != null && context.mounted) showMessage(context, 'Mazo "$n" guardado');
}

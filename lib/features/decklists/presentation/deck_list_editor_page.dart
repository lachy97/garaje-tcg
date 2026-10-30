import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../core/db/database_provider.dart';
import '../data/card_images.dart';
import '../domain/card_db.dart';
import '../domain/deck_list.dart';
import 'card_image.dart';

/// Datos del jugador cuya lista se edita o se ve.
class DeckListTarget {
  const DeckListTarget({
    required this.tournamentId,
    required this.tournamentName,
    required this.date,
    required this.playerId,
    required this.playerName,
    this.position,
    this.deckName,
  });

  final String tournamentId;
  final String tournamentName;
  final DateTime date;
  final String playerId;
  final String playerName;
  final int? position;
  final String? deckName;
}

/// Cargar o corregir la lista de un jugador: importar un .ydk o añadir las
/// cartas a mano con el buscador. Se toca la estrella para elegir la carta
/// principal. Los avisos (40–60 cartas, banlist…) no impiden guardar.
class DeckListEditorPage extends ConsumerStatefulWidget {
  const DeckListEditorPage({
    super.key,
    required this.target,
    this.initial,
    this.initialFeatured,
    this.initialBackground,
    this.initialSecondary,
  });

  final DeckListTarget target;
  final DeckCards? initial;
  final int? initialFeatured;
  final int? initialBackground;
  final int? initialSecondary;

  @override
  ConsumerState<DeckListEditorPage> createState() => _DeckListEditorPageState();
}

class _DeckListEditorPageState extends ConsumerState<DeckListEditorPage> {
  late DeckCards _cards = widget.initial?.copy() ?? DeckCards();
  late int? _featured = widget.initialFeatured;
  late int? _background = widget.initialBackground;
  late int? _secondary = widget.initialSecondary;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(cardDbProvider);
    final t = widget.target;
    return Scaffold(
      appBar: AppBar(
        title: Text('LISTA · ${t.playerName.toUpperCase()}', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Importar .ydk',
            icon: const Icon(Icons.upload_file),
            onPressed: db.value == null ? null : () => _importYdk(db.value!),
          ),
        ],
      ),
      body: AsyncView(
        value: db,
        builder: (cardDb) {
          if (cardDb.isEmpty) {
            return const EmptyState(
              icon: Icons.style_outlined,
              title: 'Falta la base de cartas',
              subtitle: 'Esta versión de la app aún no trae las cartas de Edison '
                  '(ver Ajustes → Cartas).',
            );
          }
          final warnings = validateDeck(_cards, cardDb);
          if (_featured == null && !_cards.isEmpty) {
            warnings.add('Toca la estrella de la carta que saldrá en grande.');
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _Header(target: t),
                    if (!_cards.isEmpty) ...[
                      const SectionLabel('Imágenes para exportar'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            _ArtSlot(
                              label: 'Principal',
                              card: _featured == null ? null : cardDb.byId(_featured!),
                              onTap: () => _pickArt(cardDb, 'Imagen principal', _featured,
                                  (id) => _featured = id),
                            ),
                            _ArtSlot(
                              label: 'Secundaria',
                              card: _secondary == null ? null : cardDb.byId(_secondary!),
                              onTap: () => _pickArt(cardDb, 'Imagen secundaria', _secondary,
                                  (id) => _secondary = id),
                            ),
                            _ArtSlot(
                              label: 'Fondo',
                              card: _background == null ? null : cardDb.byId(_background!),
                              onTap: () => _pickArt(cardDb, 'Imagen de fondo', _background,
                                  (id) => _background = id),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
                        child: Text(
                          'La principal sale en grande en los dos modelos. La secundaria y '
                          'el fondo, en el modelo Clásico.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                    if (_cards.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Importa un archivo .ydk (icono de arriba) o añade las cartas '
                          'una a una con "Añadir carta".',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    if (warnings.isNotEmpty && !_cards.isEmpty)
                      NeonCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final w in warnings)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text('⚠ $w',
                                    style: const TextStyle(fontSize: 13, color: AppColors.draw)),
                              ),
                          ],
                        ),
                      ),
                    for (final s in DeckSection.values) ..._section(s, cardDb),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _search(cardDb),
                          icon: const Icon(Icons.add),
                          label: const Text('Añadir carta'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving || _cards.isEmpty ? null : _save,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Guardar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _section(DeckSection s, CardDb db) {
    final rows = groupedSection(_cards, s, db);
    if (rows.isEmpty && s != DeckSection.main) return const [];
    return [
      SectionLabel('${s.label} (${_cards.of(s).length})'),
      for (final (card, n) in rows)
        _CardRow(
          card: card,
          count: n,
          featured: _featured == card.id,
          onFeatured: () => setState(() => _featured = card.id),
          onAdd: () => setState(() => _cards.add(s, card.id)),
          onRemove: () => setState(() {
            _cards.remove(s, card.id);
            if (_featured == card.id && _cards.total(card.id) == 0) _featured = null;
          }),
          onMove: () => _move(card, s),
        ),
    ];
  }

  /// Elige una carta de la lista para una de las imágenes de la exportación.
  Future<void> _pickArt(
      CardDb db, String title, int? current, void Function(int? id) assign) async {
    final ids = {..._cards.main, ..._cards.extra, ..._cards.side};
    final cards = [for (final id in ids) if (db.byId(id) case final c?) c]
      ..sort((a, b) => a.name.compareTo(b.name));
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                      child: Text(title,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                  if (current != null)
                    TextButton(onPressed: () => Navigator.pop(ctx, -1), child: const Text('Quitar')),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 120, mainAxisSpacing: 10, crossAxisSpacing: 10),
                itemCount: cards.length,
                itemBuilder: (_, i) {
                  final c = cards[i];
                  return InkWell(
                    onTap: () => Navigator.pop(ctx, c.id),
                    child: Column(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: c.id == current ? AppColors.neon : Colors.transparent,
                                    width: 3),
                              ),
                              child: CardImage(
                                  id: c.id, name: c.name, size: CardImageSize.art, width: 90),
                            ),
                          ),
                        ),
                        Text(c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => assign(picked == -1 ? null : picked));
  }

  /// Pasa una copia a otra sección (p. ej. del Main al Side).
  Future<void> _move(YgoCard card, DeckSection from) async {
    final to = await showModalBottomSheet<DeckSection>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Mover una copia de ${card.name} a…',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final s in DeckSection.values)
              if (s != from)
                ListTile(title: Text(s.label), onTap: () => Navigator.pop(ctx, s)),
          ],
        ),
      ),
    );
    if (to == null) return;
    setState(() {
      if (_cards.remove(from, card.id)) _cards.add(to, card.id);
    });
  }

  Future<void> _importYdk(CardDb db) async {
    if (db.isEmpty) return;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Elegir lista (.ydk)',
      type: FileType.any,
      withData: true,
    );
    final bytes = result?.files.singleOrNull?.bytes;
    if (bytes == null || !mounted) return;
    final text = utf8.decode(bytes, allowMalformed: true);
    final parsed = parseYdk(text, db);
    if (parsed.cards.isEmpty) {
      showMessage(context, 'El archivo no tiene cartas reconocibles (¿es un .ydk?).',
          error: true);
      return;
    }
    if (!_cards.isEmpty) {
      final ok = await confirmDialog(context,
          title: 'Reemplazar lista',
          message: 'Se cambia la lista actual por la del archivo.',
          confirm: 'Reemplazar');
      if (!ok || !mounted) return;
    }
    setState(() {
      _cards = parsed.cards;
      if (_featured != null && _cards.total(_featured!) == 0) _featured = null;
    });
    final total = parsed.cards.main.length + parsed.cards.extra.length + parsed.cards.side.length;
    showMessage(
      context,
      parsed.unknown.isEmpty
          ? '$total cartas importadas.'
          : '$total cartas importadas. ${parsed.unknown.length} no son de Edison o no se '
              'reconocen y se quitaron.',
      error: parsed.unknown.isNotEmpty,
    );
  }

  Future<void> _search(CardDb db) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _CardSearch(
          db: db,
          countOf: (id) => _cards.total(id),
          onPick: (card, section) => setState(() {
            final s = card.isExtra && section == DeckSection.main ? DeckSection.extra : section;
            _cards.add(s, card.id);
          }),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final t = widget.target;
    int? inDeck(int? id) => id != null && _cards.total(id) > 0 ? id : null;
    final featured = inDeck(_featured);
    final ok = await runGuarded(
      context,
      () => ref.read(tournamentsDaoProvider).saveDeckList(
            tournamentId: t.tournamentId,
            playerId: t.playerId,
            main: DeckCards.joinCodes(_cards.main),
            extra: DeckCards.joinCodes(_cards.extra),
            side: DeckCards.joinCodes(_cards.side),
            featuredCard: featured,
            backgroundCard: inDeck(_background),
            secondaryCard: inDeck(_secondary),
          ),
      success: 'Lista guardada',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context, true);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.target});

  final DeckListTarget target;

  @override
  Widget build(BuildContext context) {
    final t = target;
    return NeonCard(
      child: Row(
        children: [
          if (t.position != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text('${t.position}º',
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.neon)),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.playerName,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text('${t.deckName ?? 'Sin mazo'} · ${t.tournamentName}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hueco de una imagen de la exportación (ilustración de la carta elegida).
class _ArtSlot extends StatelessWidget {
  const _ArtSlot({required this.label, required this.card, required this.onTap});

  final String label;
  final YgoCard? card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: card == null
                      ? Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh,
                            border: Border.all(color: AppColors.outline),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.add_photo_alternate_outlined,
                              color: AppColors.textSecondary),
                        )
                      : LayoutBuilder(
                          builder: (_, c) => CardImage(
                              id: card!.id,
                              name: card!.name,
                              size: CardImageSize.art,
                              width: c.maxWidth),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Text(card?.name ?? 'Elegir',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.card,
    required this.count,
    required this.featured,
    required this.onFeatured,
    required this.onAdd,
    required this.onRemove,
    required this.onMove,
  });

  final YgoCard card;
  final int count;
  final bool featured;
  final VoidCallback onFeatured;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onLongPress: onMove,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            CardImage(id: card.id, name: card.name, width: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Text(card.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: 'Carta principal',
              icon: Icon(featured ? Icons.star : Icons.star_border,
                  color: featured ? AppColors.neon : AppColors.textSecondary),
              onPressed: onFeatured,
            ),
            IconButton(
                tooltip: 'Quitar una', icon: const Icon(Icons.remove), onPressed: onRemove),
            SizedBox(
              width: 22,
              child: Text('$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.neon)),
            ),
            IconButton(tooltip: 'Añadir una', icon: const Icon(Icons.add), onPressed: onAdd),
          ],
        ),
      ),
    );
  }
}

/// Buscador de cartas (nombre en inglés). Cada toque añade una copia a la
/// sección elegida; las cartas del Extra Deck van solas al Extra.
class _CardSearch extends StatefulWidget {
  const _CardSearch({required this.db, required this.countOf, required this.onPick});

  final CardDb db;
  final int Function(int id) countOf;
  final void Function(YgoCard card, DeckSection section) onPick;

  @override
  State<_CardSearch> createState() => _CardSearchState();
}

class _CardSearchState extends State<_CardSearch> {
  String _query = '';
  DeckSection _section = DeckSection.main;

  @override
  Widget build(BuildContext context) {
    final results = widget.db.search(_query, limit: 40);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Nombre en inglés (p. ej. "gale whirlwind")',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<DeckSection>(
              segments: const [
                ButtonSegment(value: DeckSection.main, label: Text('Main / Extra')),
                ButtonSegment(value: DeckSection.side, label: Text('Side')),
              ],
              selected: {_section},
              onSelectionChanged: (s) => setState(() => _section = s.first),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (_, i) {
                final c = results[i];
                final n = widget.countOf(c.id);
                return ListTile(
                  leading: CardImage(id: c.id, name: c.name, width: 34),
                  title: Text(c.name),
                  subtitle: Text([
                    _frameLabel(c.frame),
                    if (c.limit == 0) 'Prohibida' else if (c.limit < 3) 'Límite ${c.limit}',
                  ].join(' · ')),
                  trailing: n == 0
                      ? const Icon(Icons.add_circle_outline)
                      : Text('×$n',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, color: AppColors.neon)),
                  onTap: () => setState(() => widget.onPick(c, _section)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _frameLabel(String frame) => switch (frame) {
      'normal' => 'Monstruo normal',
      'effect' => 'Monstruo de efecto',
      'ritual' => 'Monstruo ritual',
      'fusion' => 'Fusión',
      'synchro' => 'Sincronía',
      'spell' => 'Mágica',
      'trap' => 'Trampa',
      _ => frame,
    };

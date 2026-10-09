import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../app/export/export_models.dart';
import '../../../app/export/export_sheet.dart';
import '../../../app/widgets/brand.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/season_utils.dart';
import '../domain/deck_stats.dart';
import '../domain/tier_style.dart';
import 'deck_image.dart';
import 'deck_tier_table.dart' show deckPdfTable;

/// Colores del diseño (fondo oscuro como la tier list de referencia).
const _kBoardBg = Color(0xFF111111);
const _kRowLine = Color(0xFF262626);
const _kRowLineWidth = 2.0;

/// Medidas de una tier list: etiqueta, imágenes y separación.
class TierBoardMetrics {
  const TierBoardMetrics({
    required this.labelWidth,
    required this.tile,
    required this.perRow,
    required this.gap,
    required this.labelFont,
    required this.radius,
  });

  final double labelWidth;
  final double tile;
  final int perRow;
  final double gap;
  final double labelFont;
  final double radius;

  double get contentWidth => perRow * tile + (perRow + 1) * gap;
  double get width => labelWidth + contentWidth;

  int lines(int count) => count == 0 ? 1 : (count / perRow).ceil();

  double rowHeight(int count) {
    final n = lines(count);
    return n * tile + (n + 1) * gap;
  }

  double height(List<DeckSeasonStats> decks) {
    var h = 0.0;
    for (final t in DeckTier.values) {
      h += rowHeight(decks.where((d) => d.tier == t).length);
    }
    return h + (DeckTier.values.length - 1) * _kRowLineWidth;
  }

  /// Medidas para la imagen exportada (10 mazos por línea).
  static const exported = TierBoardMetrics(
    labelWidth: 180,
    tile: 95,
    perRow: 10,
    gap: 3,
    labelFont: 26,
    radius: 14,
  );

  /// Medidas para la pantalla: llena el ancho disponible con imágenes de ~60.
  factory TierBoardMetrics.forWidth(double width) {
    const label = 84.0;
    const gap = 3.0;
    var perRow = ((width - label) / 62).floor();
    if (perRow < 4) perRow = 4;
    final tile = (width - label - (perRow + 1) * gap) / perRow;
    return TierBoardMetrics(
      labelWidth: label,
      tile: tile,
      perRow: perRow,
      gap: gap,
      labelFont: 17,
      radius: 10,
    );
  }
}

/// Tier list: una fila por tier con su etiqueta de color (editable) a la
/// izquierda y las imágenes de los mazos, en orden de puesto, a la derecha.
class TierBoard extends StatelessWidget {
  const TierBoard({
    super.key,
    required this.decks,
    required this.styles,
    required this.metrics,
    this.onEditTier,
  });

  final List<DeckSeasonStats> decks;
  final Map<DeckTier, TierStyle> styles;
  final TierBoardMetrics metrics;

  /// Si no es null, tocar la etiqueta de un tier permite editarla.
  final void Function(DeckTier tier)? onEditTier;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Container(
      width: m.width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _kBoardBg,
        borderRadius: BorderRadius.circular(m.radius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, tier) in DeckTier.values.indexed) ...[
            if (i > 0) Container(height: _kRowLineWidth, color: _kRowLine),
            _row(tier),
          ],
        ],
      ),
    );
  }

  Widget _row(DeckTier tier) {
    final m = metrics;
    final list = [for (final d in decks) if (d.tier == tier) d];
    final style = tierStyleOf(styles, tier);
    final label = Container(
      width: m.labelWidth,
      color: style.color,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: m.labelWidth * 0.06),
      child: Text(
        style.label,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: m.labelFont,
          height: 1.2,
          fontWeight: FontWeight.w500,
          color: style.textColor,
        ),
      ),
    );
    return SizedBox(
      height: m.rowHeight(list.length),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onEditTier == null)
            label
          else
            Material(
              color: style.color,
              child: InkWell(onTap: () => onEditTier!(tier), child: label),
            ),
          SizedBox(
            width: m.contentWidth,
            child: Padding(
              padding: EdgeInsets.all(m.gap),
              child: Wrap(
                spacing: m.gap,
                runSpacing: m.gap,
                children: [for (final d in list) DeckTile(deck: d, size: m.tile)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Imagen cuadrada de un mazo con el nombre encima (blanco con contorno).
class DeckTile extends StatelessWidget {
  const DeckTile({super.key, required this.deck, required this.size});

  final DeckSeasonStats deck;
  final double size;

  /// Tamaño de letra (para una imagen de 100) para que la palabra más larga quepa.
  static double _fontFor(String name) {
    final longest = name
        .split(RegExp(r'[\s-]+'))
        .fold<int>(1, (m, w) => w.length > m ? w.length : m);
    final byWord = 92 / (longest * 0.62);
    final base = name.length > 18 ? 15.0 : 17.0;
    return byWord < base ? byWord : base;
  }

  @override
  Widget build(BuildContext context) {
    final provider = deckImageProvider(deck.imagePath);
    final scale = size / 100;
    final font = _fontFor(deck.name) * scale;
    TextStyle style(Paint? stroke) => TextStyle(
          fontSize: font,
          height: 1.05,
          fontWeight: FontWeight.w800,
          foreground: stroke,
          color: stroke == null ? Colors.white : null,
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(3 * scale),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (provider != null)
              Image(image: provider, fit: BoxFit.cover, filterQuality: FilterQuality.high)
            else
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3A3A3A), Color(0xFF151515)],
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(4 * scale),
              child: Center(
                child: Stack(
                  children: [
                    // Contorno negro + relleno blanco: se lee sobre cualquier imagen.
                    Text(deck.name,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: style(Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = 3.2 * scale
                          ..strokeJoin = StrokeJoin.round
                          ..color = Colors.black)),
                    Text(deck.name,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: style(null)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tier list de la pantalla de mazos (ocupa el ancho; etiquetas editables).
class TierBoardView extends ConsumerWidget {
  const TierBoardView({super.key, required this.decks});

  final List<DeckSeasonStats> decks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final styles = ref.watch(tierStylesProvider);
    return LayoutBuilder(
      builder: (context, c) => TierBoard(
        decks: decks,
        styles: styles,
        metrics: TierBoardMetrics.forWidth(c.maxWidth),
        onEditTier: (t) => showTierStyleDialog(context, ref, t),
      ),
    );
  }
}

// ───────────────────── Editar etiqueta (texto y color) ─────────────────────

Color? _parseHex(String s) {
  var h = s.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Future<void> showTierStyleDialog(BuildContext context, WidgetRef ref, DeckTier tier) {
  final current = tierStyleOf(ref.read(tierStylesProvider), tier);
  final text = TextEditingController(text: current.label);
  final hex = TextEditingController(text: _hex(current.color));
  var color = current.color;
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final preview = TierStyle(text.text.trim().isEmpty ? tier.label : text.text.trim(), color);
        return AlertDialog(
          title: Text(tier == DeckTier.rogue
              ? 'Etiqueta de Rogue/Local'
              : 'Etiqueta del tier ${tier.label}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Vista previa
                Container(
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: preview.color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(preview.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: preview.textColor)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: text,
                  maxLength: 24,
                  decoration: const InputDecoration(labelText: 'Texto'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in kTierPalette)
                      GestureDetector(
                        onTap: () => setState(() {
                          color = c;
                          hex.text = _hex(c);
                        }),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: c.toARGB32() == color.toARGB32()
                                  ? Colors.white
                                  : Colors.black26,
                              width: c.toARGB32() == color.toARGB32() ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hex,
                  decoration: const InputDecoration(
                    labelText: 'Color (código, p. ej. #D66A69)',
                    isDense: true,
                  ),
                  onChanged: (v) {
                    final c = _parseHex(v);
                    if (c != null) setState(() => color = c);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                ref.read(tierStylesProvider.notifier).reset(tier);
                Navigator.pop(ctx);
              },
              child: const Text('Restablecer'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                ref.read(tierStylesProvider.notifier).set(tier, preview);
                Navigator.pop(ctx);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    ),
  );
}

// ───────────────────── Imagen exportada ─────────────────────

const _kPosterPadding = 40.0;
const _kPosterBg = 'assets/export/tierlist_bg.jpg';

/// Alto aproximado de la cabecera y el pie del póster.
const _kPosterChrome = 40 + 150 + 30 + 70.0;

/// Póster de la tier list: fondo oscuro con textura, título grande
/// "»» TIER LIST", la marca y la temporada, y el tablero.
class TierListPoster extends StatelessWidget {
  const TierListPoster({
    super.key,
    required this.decks,
    required this.styles,
    required this.season,
    required this.date,
  });

  final List<DeckSeasonStats> decks;
  final Map<DeckTier, TierStyle> styles;
  final String season;
  final String date;

  static double get width => TierBoardMetrics.exported.width + 2 * _kPosterPadding;

  @override
  Widget build(BuildContext context) {
    const title = Color(0xFFCFCFCF);
    const muted = Color(0xFF8E8E8E);
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: Color(0xFF0B0B0D),
        image: DecorationImage(image: AssetImage(_kPosterBg), fit: BoxFit.cover),
      ),
      padding: const EdgeInsets.fromLTRB(_kPosterPadding, 36, _kPosterPadding, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const CustomPaint(size: Size(118, 74), painter: _ChevronsPainter(title)),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TIER LIST',
                      style: TextStyle(
                        fontSize: 108,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                        color: title,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'GARAGE TCG · TEMPORADA $season',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              Image.asset(BrandAssets.logo,
                  width: 120, height: 120, filterQuality: FilterQuality.high),
            ],
          ),
          const SizedBox(height: 30),
          TierBoard(decks: decks, styles: styles, metrics: TierBoardMetrics.exported),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '${decks.length} mazos · Tier según el Power (puntos por resultados en el '
                  'Top) respecto al mejor mazo · En cada fila, ordenados por puesto.',
                  style: const TextStyle(fontSize: 14, color: muted),
                ),
              ),
              const SizedBox(width: 16),
              Text('Actualizado $date', style: const TextStyle(fontSize: 14, color: muted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tres flechas "»»»" gruesas, como en el título de la referencia.
class _ChevronsPainter extends CustomPainter {
  const _ChevronsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.2
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter;
    final h = size.height;
    final step = size.width / 3.3;
    final w = h * 0.42;
    for (var i = 0; i < 3; i++) {
      final x = i * step + paint.strokeWidth / 2;
      canvas.drawPath(
        Path()
          ..moveTo(x, h * 0.12)
          ..lineTo(x + w, h / 2)
          ..lineTo(x, h * 0.88),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChevronsPainter old) => old.color != color;
}

/// Exporta la tier list como UNA imagen con el diseño del póster (sin la tabla).
Future<void> exportDeckTierImages(
  BuildContext context, {
  required Season season,
  required List<DeckSeasonStats> decks,
  required Map<DeckTier, TierStyle> styles,
}) {
  final label = seasonLabel(season.year, season.quarter);
  final date = DateFormat('dd/MM/yyyy HH:mm', 'es').format(DateTime.now());
  return runExport<DeckSeasonStats>(
    context,
    ExportSpec(
      heading: 'TIER LIST DE MAZOS · $label',
      items: decks,
      page: TierListPoster(decks: decks, styles: styles, season: label, date: date),
      contentWidth: TierListPoster.width,
      summaryHeightEstimate: _kPosterChrome + TierBoardMetrics.exported.height(decks),
      pdfTable: () => deckPdfTable(decks),
      legend: '',
      fileBase: 'tierlist_garage_tcg_${season.year}_T${season.quarter}',
      shareText: 'Tier list de mazos Garage TCG · Temporada $label',
      preload: [
        const AssetImage(_kPosterBg),
        for (final d in decks)
          if (deckImageProvider(d.imagePath) case final p?) p,
      ],
    ),
  );
}

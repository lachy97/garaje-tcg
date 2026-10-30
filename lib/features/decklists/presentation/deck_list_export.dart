import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/export/export_models.dart';
import '../../../app/export/export_sheet.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../data/card_images.dart';
import '../domain/card_db.dart';
import '../domain/deck_list.dart';
import 'deck_list_editor_page.dart' show DeckListTarget;

// ───────────────────────── Color de fondo ─────────────────────────

/// Color medio de una imagen (muestreando píxeles).
Future<Color?> averageColor(File file) async {
  try {
    final codec = await ui.instantiateImageCodec(await file.readAsBytes(), targetWidth: 64);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    codec.dispose();
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    if (data == null) return null;
    var r = 0, g = 0, b = 0, n = 0;
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4 * 3) {
      r += data.getUint8(i);
      g += data.getUint8(i + 1);
      b += data.getUint8(i + 2);
      n++;
    }
    if (n == 0) return null;
    return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
  } catch (_) {
    return null;
  }
}

/// Fondo que contrasta con la ilustración: el tono opuesto al dominante, y
/// oscuro si la ilustración es clara (o claro si es oscura).
Color contrastBackground(Color dominant) {
  final hsl = HSLColor.fromColor(dominant);
  final light = dominant.computeLuminance() > 0.35;
  return HSLColor.fromAHSL(
    1,
    (hsl.hue + 180) % 360,
    math.min(math.max(hsl.saturation, 0.35), 0.75),
    light ? 0.13 : 0.78,
  ).toColor();
}

/// Texto legible sobre [bg].
Color textOn(Color bg) => bg.computeLuminance() > 0.4 ? const Color(0xFF0B0B0D) : Colors.white;

// ───────────────────────── Exportar ─────────────────────────

/// Exporta la lista como una imagen: datos del jugador, Main/Extra/Side en
/// cuadrícula (una imagen por copia) y la carta principal en grande.
Future<void> exportDeckListImage(
  BuildContext context, {
  required DeckListTarget target,
  required DeckCards cards,
  required int? featured,
  required CardDb db,
  required CardImageStore store,
}) async {
  if (_exporting) return;
  _exporting = true;
  try {
    await _export(context,
        target: target, cards: cards, featured: featured, db: db, store: store);
  } finally {
    _exporting = false;
  }
}

/// Evita lanzar dos exportaciones a la vez (doble toque).
bool _exporting = false;

Future<void> _export(
  BuildContext context, {
  required DeckListTarget target,
  required DeckCards cards,
  required int? featured,
  required CardDb db,
  required CardImageStore store,
}) async {
  showMessage(context, 'Preparando la imagen…');
  // 1) Imágenes de todas las cartas (se descargan las que falten).
  final ids = {...cards.main, ...cards.extra, ...cards.side};
  final small = <int, File>{};
  var missing = 0;
  await Future.wait([
    for (final id in ids)
      store.get(id, CardImageSize.small).then((f) {
        if (f == null) {
          missing++;
        } else {
          small[id] = f;
        }
      }),
  ]);
  final featuredId = featured ?? _fallbackFeatured(cards, db);
  final art = featuredId == null ? null : await store.get(featuredId, CardImageSize.art);
  final dominant = art == null ? null : await averageColor(art);
  final bg = contrastBackground(dominant ?? AppColors.forest);
  if (!context.mounted) return;
  if (missing > 0) {
    showMessage(context, '$missing carta(s) sin imagen (sin conexión): salen con su nombre.',
        error: true);
  }

  final poster = DeckListPoster(
    target: target,
    cards: cards,
    db: db,
    small: small,
    featured: featuredId == null ? null : db.byId(featuredId),
    art: art,
    background: bg,
  );
  await runExport<int>(
    context,
    ExportSpec(
      heading: 'LISTA · ${target.playerName}',
      items: const [],
      page: poster,
      contentWidth: DeckListPoster.width,
      summaryHeightEstimate: poster.estimatedHeight,
      legend: '',
      fileBase: 'lista_${_fileSafe(target.playerName)}_${_fileSafe(target.tournamentName)}',
      shareText: '${target.position == null ? '' : '${target.position}º · '}'
          '${target.playerName} · ${target.deckName ?? ''} · ${target.tournamentName}',
      preload: [
        for (final f in small.values) FileImage(f),
        if (art != null) FileImage(art),
      ],
    ),
  );
}

int? _fallbackFeatured(DeckCards cards, CardDb db) {
  for (final id in cards.main) {
    if (db.byId(id)?.group == CardGroup.monster) return id;
  }
  return cards.main.firstOrNull ?? cards.extra.firstOrNull;
}

String _fileSafe(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');

// ───────────────────────── Póster ─────────────────────────

/// Imagen de la lista: a la izquierda la cabecera y las tres secciones en
/// cuadrícula (10 cartas por fila); a la derecha la carta principal sobre un
/// fondo que contrasta con ella y borde verde neón.
class DeckListPoster extends StatelessWidget {
  const DeckListPoster({
    super.key,
    required this.target,
    required this.cards,
    required this.db,
    required this.small,
    required this.featured,
    required this.art,
    required this.background,
  });

  final DeckListTarget target;
  final DeckCards cards;
  final CardDb db;
  final Map<int, File> small;
  final YgoCard? featured;
  final File? art;
  final Color background;

  static const width = 1600.0;
  static const _pad = 40.0;
  static const _cols = 10;
  static const _gap = 6.0;
  static const _cardW = 86.0;
  static const _cardH = _cardW * 246 / 168;
  static const _leftW = _cols * _cardW + (_cols - 1) * _gap;
  static const _border = 2.0;
  // El borde del Container también resta ancho (Container suma su grosor al padding).
  static const _rightW = width - 2 * _pad - 2 * _border - _leftW - 40;

  double get estimatedHeight {
    var h = _pad * 2 + 170 + 60;
    for (final s in DeckSection.values) {
      final n = cards.of(s).length;
      if (n == 0) continue;
      h += 46 + (n / _cols).ceil() * (_cardH + _gap);
    }
    return math.max(h, _pad * 2 + 170 + _rightW + 140);
  }

  @override
  Widget build(BuildContext context) {
    final t = target;
    final date = DateFormat('dd/MM/yyyy').format(t.date);
    final onBg = textOn(background);
    return Container(
      width: width,
      padding: const EdgeInsets.all(_pad),
      decoration: const BoxDecoration(
        color: Color(0xFF050807),
        border: Border.fromBorderSide(BorderSide(color: AppColors.moss, width: _border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _leftW,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(BrandAssets.logo,
                        width: 110, height: 110, filterQuality: FilterQuality.high),
                    const SizedBox(width: 22),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [
                              if (t.position != null) '${t.position}º LUGAR',
                              t.tournamentName.toUpperCase(),
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              color: AppColors.neonBright,
                              shadows: AppColors.textGlow(blur: 6),
                            ),
                          ),
                          Text(t.playerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 52, height: 1.1, fontWeight: FontWeight.w900)),
                          Text('${t.deckName ?? 'Sin mazo'} · $date',
                              style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.neon)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                for (final s in DeckSection.values)
                  if (cards.of(s).isNotEmpty) ..._section(s),
              ],
            ),
          ),
          const SizedBox(width: 40),
          SizedBox(
            width: _rightW,
            child: Column(
              children: [
                const SizedBox(height: 150),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.neon, width: 4),
                    boxShadow: AppColors.glow(strength: 0.8),
                  ),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox.square(
                          dimension: _rightW - 52,
                          child: art == null
                              ? Container(color: Colors.black26)
                              : Image.file(art!, fit: BoxFit.cover,
                                  filterQuality: FilterQuality.high),
                        ),
                      ),
                      if (featured != null) ...[
                        const SizedBox(height: 16),
                        Text(featured!.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 28, fontWeight: FontWeight.w900, color: onBg)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text('GARAGE TCG · EDISON FORMAT',
                    style: TextStyle(
                        fontSize: 16,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _section(DeckSection s) {
    // Una imagen por copia, en el orden de la lista agrupada.
    final ordered = [
      for (final (card, n) in groupedSection(cards, s, db))
        for (var i = 0; i < n; i++) card,
    ];
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 6),
        child: Text('${s.label.toUpperCase()} · ${ordered.length}',
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: AppColors.neon)),
      ),
      Wrap(
        spacing: _gap,
        runSpacing: _gap,
        children: [for (final c in ordered) _card(c)],
      ),
      const SizedBox(height: 18),
    ];
  }

  Widget _card(YgoCard c) {
    final f = small[c.id];
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: _cardW,
        height: _cardH,
        child: f != null
            ? Image.file(f, fit: BoxFit.cover, filterQuality: FilterQuality.medium)
            : Container(
                color: AppColors.surfaceHigh,
                padding: const EdgeInsets.all(4),
                alignment: Alignment.center,
                child: Text(c.name,
                    textAlign: TextAlign.center,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.textPrimary)),
              ),
      ),
    );
  }
}

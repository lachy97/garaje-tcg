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

/// Fondo acorde con la ilustración: su mismo tono, oscuro y algo saturado
/// (el texto va en blanco encima).
Color harmonyBackground(Color dominant) {
  final hsl = HSLColor.fromColor(dominant);
  return HSLColor.fromAHSL(
    1,
    hsl.hue,
    math.min(math.max(hsl.saturation, 0.3), 0.65),
    0.17,
  ).toColor();
}

/// Texto legible sobre [bg].
Color textOn(Color bg) => bg.computeLuminance() > 0.4 ? const Color(0xFF0B0B0D) : Colors.white;

// ───────────────────────── Exportar ─────────────────────────

/// Modelos de la imagen exportada.
enum DeckListStyle {
  /// Como los carteles de torneos de Edison: ilustración de fondo, dos
  /// imágenes a la izquierda y la lista en paneles (vertical, 1080 px).
  classic('Clásico', 'Ilustración de fondo y dos imágenes a la izquierda (vertical)'),

  /// Fondo del color que contrasta con la carta principal y su ilustración
  /// en grande (horizontal, 1600 px).
  contrast('Contraste', 'Fondo que contrasta con la carta principal (horizontal)');

  const DeckListStyle(this.label, this.description);
  final String label;
  final String description;
}

/// Pregunta qué modelo exportar.
Future<DeckListStyle?> askDeckListStyle(BuildContext context) =>
    showModalBottomSheet<DeckListStyle>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in DeckListStyle.values)
              ListTile(
                leading: Icon(s == DeckListStyle.classic
                    ? Icons.crop_portrait
                    : Icons.crop_landscape),
                title: Text('Modelo ${s.label}'),
                subtitle: Text(s.description),
                onTap: () => Navigator.pop(ctx, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

/// Todo lo que necesitan los dos modelos (imágenes ya en el teléfono).
class DeckListArt {
  const DeckListArt({
    required this.target,
    required this.cards,
    required this.db,
    required this.small,
    this.featured,
    this.featuredArt,
    this.secondaryArt,
    this.backgroundArt,
    required this.contrast,
    required this.tone,
  });

  final DeckListTarget target;
  final DeckCards cards;
  final CardDb db;
  final Map<int, File> small;
  final YgoCard? featured;
  final File? featuredArt;
  final File? secondaryArt;
  final File? backgroundArt;

  /// Color que contrasta con la ilustración principal.
  final Color contrast;

  /// Color acorde con la ilustración principal (mismo tono, oscuro).
  final Color tone;

  String get positionLabel => switch (target.position) {
        null => '',
        1 => 'CAMPEÓN',
        final p => '$pº LUGAR',
      };
}

/// Evita lanzar dos exportaciones a la vez (doble toque).
bool _exporting = false;

/// Exporta la lista como imagen en el modelo elegido.
Future<void> exportDeckListImage(
  BuildContext context, {
  required DeckListStyle style,
  required DeckListTarget target,
  required DeckCards cards,
  required CardDb db,
  required CardImageStore store,
  int? featured,
  int? secondary,
  int? background,
}) async {
  if (_exporting) return;
  _exporting = true;
  try {
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
    // 2) Ilustraciones: principal, secundaria y fondo (con valores por defecto).
    final mainId = featured ?? _fallbackFeatured(cards, db);
    final secondId = secondary ?? _fallbackSecondary(cards, db, mainId);
    final bgId = background ?? mainId;
    Future<File?> art(int? id) =>
        id == null ? Future.value() : store.get(id, CardImageSize.art);
    final featuredArt = await art(mainId);
    final secondaryArt = await art(secondId);
    final backgroundArt = await art(bgId);
    final dominant = featuredArt == null ? null : await averageColor(featuredArt);
    if (!context.mounted) return;
    if (missing > 0) {
      showMessage(context, '$missing carta(s) sin imagen (sin conexión): salen con su nombre.',
          error: true);
    }

    final data = DeckListArt(
      target: target,
      cards: cards,
      db: db,
      small: small,
      featured: mainId == null ? null : db.byId(mainId),
      featuredArt: featuredArt,
      secondaryArt: secondaryArt,
      backgroundArt: backgroundArt,
      contrast: contrastBackground(dominant ?? AppColors.forest),
      tone: harmonyBackground(dominant ?? AppColors.forest),
    );
    final (Widget page, double width, double height) = switch (style) {
      DeckListStyle.classic =>
        (ClassicDeckListPoster(data: data), ClassicDeckListPoster.width,
            ClassicDeckListPoster.estimateHeight(cards, db)),
      DeckListStyle.contrast =>
        (ContrastDeckListPoster(data: data), ContrastDeckListPoster.width,
            ContrastDeckListPoster.estimateHeight(cards)),
    };
    await runExport<int>(
      context,
      ExportSpec(
        heading: 'LISTA · ${target.playerName}',
        items: const [],
        page: page,
        contentWidth: width,
        summaryHeightEstimate: height,
        legend: '',
        fileBase: 'lista_${style.name}_${_fileSafe(target.playerName)}_'
            '${_fileSafe(target.tournamentName)}',
        shareText: '${target.position == null ? '' : '${target.position}º · '}'
            '${target.playerName} · ${target.deckName ?? ''} · ${target.tournamentName}',
        preload: [
          for (final f in small.values) FileImage(f),
          for (final f in [featuredArt, secondaryArt, backgroundArt])
            if (f != null) FileImage(f),
        ],
      ),
    );
  } finally {
    _exporting = false;
  }
}

int? _fallbackFeatured(DeckCards cards, CardDb db) {
  for (final id in cards.main) {
    if (db.byId(id)?.group == CardGroup.monster) return id;
  }
  return cards.main.firstOrNull ?? cards.extra.firstOrNull;
}

int? _fallbackSecondary(DeckCards cards, CardDb db, int? exclude) {
  for (final id in [...cards.extra, ...cards.main]) {
    if (id != exclude && db.byId(id)?.group != CardGroup.spell &&
        db.byId(id)?.group != CardGroup.trap) {
      return id;
    }
  }
  return null;
}

String _fileSafe(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');

// ───────────────────────── Piezas comunes ─────────────────────────

const _cardRatio = 246 / 168;

/// Desvanece [child] hacia transparente por los lados indicados (fracción
/// del ancho o alto que ocupa el degradado), para que una ilustración se funda
/// con el fondo sin marco.
class EdgeFade extends StatelessWidget {
  const EdgeFade({
    super.key,
    required this.child,
    this.left = 0,
    this.right = 0,
    this.top = 0,
    this.bottom = 0,
  });

  final Widget child;
  final double left;
  final double right;
  final double top;
  final double bottom;

  static Widget _mask(Widget child, Alignment from, Alignment to, double f) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => LinearGradient(
          begin: from,
          end: to,
          colors: const [Colors.transparent, Colors.white],
          stops: [0, f],
        ).createShader(rect),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    var w = child;
    if (left > 0) w = _mask(w, Alignment.centerLeft, Alignment.centerRight, left);
    if (right > 0) w = _mask(w, Alignment.centerRight, Alignment.centerLeft, right);
    if (top > 0) w = _mask(w, Alignment.topCenter, Alignment.bottomCenter, top);
    if (bottom > 0) w = _mask(w, Alignment.bottomCenter, Alignment.topCenter, bottom);
    return w;
  }
}

/// Ilustración que llena su espacio (recortada, sin deformar).
Widget _artFill(File? file) => file == null
    ? const SizedBox.expand()
    : Image.file(file, fit: BoxFit.cover, filterQuality: FilterQuality.high);

/// Imagen pequeña de una carta (o su nombre si no se pudo descargar).
class _CardTile extends StatelessWidget {
  const _CardTile({required this.card, required this.file, required this.width});

  final YgoCard card;
  final File? file;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * _cardRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.04),
        child: file != null
            ? Image.file(file!, fit: BoxFit.cover, filterQuality: FilterQuality.medium)
            : Container(
                color: AppColors.surfaceHigh,
                padding: const EdgeInsets.all(3),
                alignment: Alignment.center,
                child: Text(card.name,
                    textAlign: TextAlign.center,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: width * 0.13, color: AppColors.textPrimary)),
              ),
      ),
    );
  }
}

/// Una carta por copia, en el orden de la lista agrupada.
List<YgoCard> _everyCopy(DeckCards cards, DeckSection s, CardDb db) => [
      for (final (card, n) in groupedSection(cards, s, db))
        for (var i = 0; i < n; i++) card,
    ];

// ───────────────────────── Modelo Clásico ─────────────────────────

/// Como los carteles de los torneos de Edison (vertical, 1080 px):
/// - columna izquierda: imagen 1 (arriba) e imagen 2 (abajo), cada una
///   llenando su mitad y fundiéndose hacia la derecha;
/// - a la derecha, la ilustración de fondo (más desenfocada) y encima el
///   título, puesto, jugador, mazo y la lista en paneles (una imagen por copia).
class ClassicDeckListPoster extends StatelessWidget {
  const ClassicDeckListPoster({super.key, required this.data});

  final DeckListArt data;

  static const width = 1080.0;
  static const minHeight = 1350.0;

  /// Ancho de la columna de imágenes de la izquierda.
  static const _leftCol = 340.0;
  static const _padL = 22.0;
  static const _padR = 28.0;
  static const _panelPad = 10.0;
  static const _panelBorder = 2.0;

  /// Ancho útil dentro de un panel (descontando relleno y borde).
  static const _inner =
      width - _leftCol - _padL - _padR - 2 * _panelPad - 2 * _panelBorder - 1;
  static const _gap = 5.0;

  /// Columnas por fila: 10 en el Main (hasta 6 filas); Side y Extra en una o
  /// dos filas de hasta 15.
  static int _cols(DeckSection s, int n) =>
      s == DeckSection.main ? 10 : math.min(15, math.max(10, n));

  static double _cardW(DeckSection s, int n) {
    final cols = _cols(s, n);
    return (_inner - (cols - 1) * _gap) / cols;
  }

  static double estimateHeight(DeckCards cards, CardDb db) {
    var h = 30.0 + 150 + 200;
    for (final s in DeckSection.values) {
      final n = cards.of(s).length;
      if (n == 0) continue;
      h += 44 + (n / _cols(s, n)).ceil() * (_cardW(s, n) * _cardRatio + _gap) + 2 * _panelPad;
    }
    return math.max(h + 160, minHeight);
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final t = d.target;
    const gold = Color(0xFFE9C46A);
    const white = Colors.white;
    final shadow = [const Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2))];
    TextStyle style(double size, {Color color = white, FontWeight w = FontWeight.w900}) =>
        TextStyle(fontSize: size, color: color, fontWeight: w, shadows: shadow, height: 1.05);
    final base = Color.lerp(d.tone, Colors.black, 0.35)!;

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(text, style: style(22, w: FontWeight.w800)),
        );
    Widget panel(DeckSection s, Color color) {
      final copies = _everyCopy(d.cards, s, d.db);
      final w = _cardW(s, copies.length);
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(_panelPad),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color, width: _panelBorder),
        ),
        child: Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final c in copies) _CardTile(card: c, file: d.small[c.id], width: w),
          ],
        ),
      );
    }

    const sections = [
      (DeckSection.main, 'MAIN', Color(0xFF8E5BD6)),
      (DeckSection.side, 'SIDE', Color(0xFF2EA6A6)),
      (DeckSection.extra, 'EXTRA', Color(0xFFD08A3A)),
    ];

    return Container(
      width: width,
      color: base,
      child: Stack(
        children: [
          // Fondo (zona derecha): ilustración elegida, bien difuminada, que
          // se funde por la izquierda con las imágenes de la columna.
          Positioned(
            left: _leftCol - 60,
            top: 0,
            right: 0,
            bottom: 0,
            child: EdgeFade(
              left: 0.12,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ImageFiltered(
                    imageFilter:
                        ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9, tileMode: ui.TileMode.clamp),
                    child: _artFill(d.backgroundArt),
                  ),
                  ColoredBox(color: Colors.black.withValues(alpha: 0.38)),
                ],
              ),
            ),
          ),
          // Columna izquierda: imagen 1 arriba e imagen 2 abajo.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _leftCol,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: EdgeFade(right: 0.18, bottom: 0.06, child: _artFill(d.featuredArt)),
                ),
                Expanded(
                  child: EdgeFade(right: 0.18, top: 0.06, child: _artFill(d.secondaryArt)),
                ),
              ],
            ),
          ),
          // Contenido (zona derecha).
          Padding(
            padding: const EdgeInsets.fromLTRB(_leftCol + _padL, 28, _padR, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: minHeight - 56),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('GARAGE TCG',
                          textAlign: TextAlign.center,
                          style: style(60).copyWith(letterSpacing: 3)),
                      Text(
                        '${t.tournamentName.toUpperCase()} · '
                        '${DateFormat('dd/MM/yy').format(t.date)}',
                        textAlign: TextAlign.center,
                        style: style(24, w: FontWeight.w700),
                      ),
                      const SizedBox(height: 18),
                      if (d.positionLabel.isNotEmpty)
                        Text(d.positionLabel, style: style(50, color: gold)),
                      const SizedBox(height: 4),
                      Text(t.playerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: style(40, w: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text('MAZO', style: style(18, w: FontWeight.w700)),
                      Text(t.deckName ?? 'Sin mazo', style: style(50)),
                      for (final (s, name, color) in sections)
                        if (d.cards.of(s).isNotEmpty) ...[
                          label('$name: ${d.cards.of(s).length}'),
                          panel(s, color),
                        ],
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('LUGAR', style: style(18, w: FontWeight.w700)),
                              Text('Garage TCG', style: style(28, w: FontWeight.w800)),
                              Text('Edison Format', style: style(18, w: FontWeight.w600)),
                            ],
                          ),
                        ),
                        Image.asset(BrandAssets.logo,
                            width: 110, height: 110, filterQuality: FilterQuality.high),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Modelo Contraste ─────────────────────────

/// Horizontal (1600 px): a la izquierda la lista sobre un fondo del color de
/// la ilustración principal (mismo tono, oscuro); a la derecha la ilustración
/// principal ocupando todo el alto, sin marco, fundiéndose por la izquierda.
class ContrastDeckListPoster extends StatelessWidget {
  const ContrastDeckListPoster({super.key, required this.data});

  final DeckListArt data;

  static const width = 1600.0;
  static const _pad = 40.0;
  static const _cols = 10;
  static const _gap = 6.0;
  static const _cardW = 86.0;
  static const _leftW = _cols * _cardW + (_cols - 1) * _gap;

  /// La ilustración empieza aquí (se funde por su borde izquierdo).
  static const _artLeft = _pad + _leftW - 40;
  static const minHeight = 900.0;

  static double estimateHeight(DeckCards cards) {
    var h = _pad * 2 + 170 + 40;
    for (final s in DeckSection.values) {
      final n = cards.of(s).length;
      if (n == 0) continue;
      h += 46 + (n / _cols).ceil() * (_cardW * _cardRatio + _gap) + 18;
    }
    return math.max(h, minHeight);
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final t = d.target;
    const text = Colors.white;
    const accent = AppColors.neon;
    final muted = Colors.white.withValues(alpha: 0.75);
    final shadow = [const Shadow(color: Colors.black87, blurRadius: 10)];

    List<Widget> section(DeckSection s) {
      final copies = _everyCopy(d.cards, s, d.db);
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 6),
          child: Text('${s.label.toUpperCase()} · ${copies.length}',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2, color: accent)),
        ),
        Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final c in copies) _CardTile(card: c, file: d.small[c.id], width: _cardW),
          ],
        ),
        const SizedBox(height: 18),
      ];
    }

    return Container(
      width: width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(d.tone, Colors.white, 0.08)!,
            d.tone,
            Color.lerp(d.tone, Colors.black, 0.45)!,
          ],
        ),
      ),
      child: Stack(
        children: [
          // Ilustración principal: todo el alto de la zona derecha.
          Positioned(
            left: _artLeft,
            top: 0,
            right: 0,
            bottom: 0,
            child: EdgeFade(left: 0.22, child: _artFill(d.featuredArt)),
          ),
          if (d.featured != null)
            Positioned(
              left: _artLeft + 120,
              right: _pad,
              bottom: 60,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(d.featured!.name,
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w900, color: text, shadows: shadow)),
              ),
            ),
          Positioned(
            right: _pad,
            bottom: 24,
            child: Text('GARAGE TCG · EDISON FORMAT',
                style: TextStyle(
                    fontSize: 16,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w800,
                    color: muted,
                    shadows: shadow)),
          ),
          Padding(
            padding: const EdgeInsets.all(_pad),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: minHeight - 2 * _pad),
              child: SizedBox(
                width: _leftW,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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
                                  if (d.positionLabel.isNotEmpty) d.positionLabel,
                                  t.tournamentName.toUpperCase(),
                                ].join(' · '),
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                    color: accent),
                              ),
                              Text(t.playerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 56,
                                      height: 1.1,
                                      fontWeight: FontWeight.w900,
                                      color: text)),
                              Text(
                                  '${t.deckName ?? 'Sin mazo'} · '
                                  '${DateFormat('dd/MM/yyyy').format(t.date)}',
                                  style: TextStyle(
                                      fontSize: 24, fontWeight: FontWeight.w700, color: muted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    for (final s in DeckSection.values)
                      if (d.cards.of(s).isNotEmpty) ...section(s),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

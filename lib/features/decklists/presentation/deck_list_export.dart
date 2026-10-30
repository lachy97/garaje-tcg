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

/// Ilustración que se funde con el fondo por los bordes (sin marco).
class FadedArt extends StatelessWidget {
  const FadedArt({super.key, required this.file, required this.size, this.radial = true});

  final File? file;
  final double size;

  /// true: se desvanece en círculo; false: solo hacia la izquierda y abajo.
  final bool radial;

  @override
  Widget build(BuildContext context) {
    if (file == null) return SizedBox.square(dimension: size);
    final image = Image.file(file!,
        width: size, height: size, fit: BoxFit.cover, filterQuality: FilterQuality.high);
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => radial
          ? const RadialGradient(
              // radius 0.5 = mitad del lado: transparente justo en el borde
              // (con más radio los bordes salían cortados, ~80 % opacos).
              radius: 0.5,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0, 0.65, 1],
            ).createShader(rect)
          : const LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0, 0.7, 1],
            ).createShader(rect),
      child: radial
          ? image
          : ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0, 0.72, 1],
              ).createShader(rect),
              child: image,
            ),
    );
  }
}

/// Imagen pequeña de una carta (o su nombre si no se pudo descargar), con el
/// número de copias arriba a la izquierda si [count] no es null.
class _CardTile extends StatelessWidget {
  const _CardTile({required this.card, required this.file, required this.width, this.count});

  final YgoCard card;
  final File? file;
  final double width;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final h = width * _cardRatio;
    return SizedBox(
      width: width,
      height: h,
      child: Stack(
        children: [
          Positioned.fill(
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
                          style: TextStyle(
                              fontSize: width * 0.13, color: AppColors.textPrimary)),
                    ),
            ),
          ),
          if (count != null)
            Positioned(
              left: 2,
              top: 2,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: width * 0.07),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
                ),
                child: Text('$count',
                    style: TextStyle(
                        fontSize: width * 0.2,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        height: 1.2)),
              ),
            ),
        ],
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

/// Como los carteles de los torneos de Edison: ilustración de fondo, la
/// principal y la secundaria a la izquierda fundiéndose con el fondo, y a la
/// derecha puesto, jugador, mazo y la lista en paneles (Main con el número de
/// copias de cada carta; Side y Extra una imagen por copia).
class ClassicDeckListPoster extends StatelessWidget {
  const ClassicDeckListPoster({super.key, required this.data});

  final DeckListArt data;

  static const width = 1080.0;
  static const _left = 330.0;
  static const _right = 34.0;
  static const _panelPad = 10.0;
  static const _panelBorder = 2.0;

  /// Alto mínimo: la imagen secundaria llega hasta y = 1140.
  static const _minHeight = 1350.0;

  /// Ancho útil dentro de un panel (descontando relleno y borde).
  static const _inner = width - _left - _right - 2 * _panelPad - 2 * _panelBorder - 1;
  static const _mainCols = 10;
  static const _gap = 6.0;
  static const _mainCard = (_inner - (_mainCols - 1) * _gap) / _mainCols;

  static double _rowCard(int n) {
    final cols = math.min(15, math.max(10, n));
    return (_inner - (cols - 1) * 4) / cols;
  }

  static double estimateHeight(DeckCards cards, CardDb db) {
    final mainRows = (groupedSection(cards, DeckSection.main, db).length / _mainCols).ceil();
    var h = 40 + 80 + 230 + 40 + mainRows * (_mainCard * _cardRatio + _gap) + 2 * _panelPad;
    for (final s in [DeckSection.side, DeckSection.extra]) {
      final n = cards.of(s).length;
      if (n == 0) continue;
      final cols = math.min(15, math.max(10, n));
      h += 40 + (n / cols).ceil() * (_rowCard(n) * _cardRatio + 4) + 2 * _panelPad + 14;
    }
    return math.max(h + 170, _minHeight);
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
    final main = groupedSection(d.cards, DeckSection.main, d.db);

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(text, style: style(22, w: FontWeight.w800)),
        );
    Widget panel(Color color, Widget child) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(_panelPad),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color, width: _panelBorder),
          ),
          child: child,
        );
    Widget row(DeckSection s, Color color) {
      final copies = _everyCopy(d.cards, s, d.db);
      final w = _rowCard(copies.length);
      return panel(
        color,
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final c in copies) _CardTile(card: c, file: d.small[c.id], width: w),
          ],
        ),
      );
    }

    return SizedBox(
      width: width,
      child: Stack(
        children: [
          // Fondo: ilustración elegida, desenfocada y oscurecida un poco.
          Positioned.fill(
            child: d.backgroundArt == null
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [d.contrast, Color.lerp(d.contrast, Colors.black, 0.6)!],
                      ),
                    ),
                  )
                : ImageFiltered(
                    imageFilter:
                        ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4, tileMode: ui.TileMode.clamp),
                    child: Image.file(d.backgroundArt!,
                        fit: BoxFit.cover, filterQuality: FilterQuality.medium),
                  ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.25),
                    Colors.black.withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
          ),
          // Imágenes de la izquierda.
          Positioned(left: -90, top: 70, child: FadedArt(file: d.featuredArt, size: 560)),
          Positioned(left: -70, top: 640, child: FadedArt(file: d.secondaryArt, size: 500)),
          // Contenido (alto mínimo: la imagen secundaria no queda cortada).
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 30, _right, 30),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _minHeight - 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('GARAGE TCG',
                          textAlign: TextAlign.center,
                          style: style(64).copyWith(letterSpacing: 3)),
                      Text(t.tournamentName.toUpperCase(),
                          textAlign: TextAlign.center, style: style(26, w: FontWeight.w700)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(DateFormat('dd/MM/yy').format(t.date),
                            style: style(20, w: FontWeight.w700)),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: _left - 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (d.positionLabel.isNotEmpty)
                              Text(d.positionLabel, style: style(50, color: gold)),
                            const SizedBox(height: 6),
                            Text(t.playerName, style: style(40, w: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text('MAZO', style: style(18, w: FontWeight.w700)),
                            Text(t.deckName ?? 'Sin mazo', style: style(52)),
                            label('MAIN: ${d.cards.main.length}'),
                            panel(
                              const Color(0xFF8E5BD6),
                              Wrap(
                                spacing: _gap,
                                runSpacing: _gap,
                                children: [
                                  for (final (c, n) in main)
                                    _CardTile(
                                        card: c, file: d.small[c.id], width: _mainCard, count: n),
                                ],
                              ),
                            ),
                            if (d.cards.side.isNotEmpty) ...[
                              label('SIDE: ${d.cards.side.length}'),
                              row(DeckSection.side, const Color(0xFF2EA6A6)),
                            ],
                            if (d.cards.extra.isNotEmpty) ...[
                              label('EXTRA: ${d.cards.extra.length}'),
                              row(DeckSection.extra, const Color(0xFFD08A3A)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: _left - 28, top: 24),
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

/// Fondo con el color que contrasta con la carta principal (degradado, no
/// negro), la lista a la izquierda (una imagen por copia) y la ilustración
/// principal grande a la derecha, sin marco, fundiéndose con el fondo.
class ContrastDeckListPoster extends StatelessWidget {
  const ContrastDeckListPoster({super.key, required this.data});

  final DeckListArt data;

  static const width = 1600.0;
  static const _pad = 40.0;
  static const _cols = 10;
  static const _gap = 6.0;
  static const _cardW = 86.0;
  static const _leftW = _cols * _cardW + (_cols - 1) * _gap;
  static const _art = 820.0;

  static double estimateHeight(DeckCards cards) {
    var h = _pad * 2 + 170 + 40;
    for (final s in DeckSection.values) {
      final n = cards.of(s).length;
      if (n == 0) continue;
      h += 46 + (n / _cols).ceil() * (_cardW * _cardRatio + _gap) + 18;
    }
    return math.max(h, _art + 120);
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final t = d.target;
    final darkBg = d.contrast.computeLuminance() < 0.4;
    final text = darkBg ? Colors.white : const Color(0xFF0B0B0D);
    final accent = darkBg ? AppColors.neon : const Color(0xFF0E3B22);
    final muted = text.withValues(alpha: 0.7);

    List<Widget> section(DeckSection s) {
      final copies = _everyCopy(d.cards, s, d.db);
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 6),
          child: Text('${s.label.toUpperCase()} · ${copies.length}',
              style: TextStyle(
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
            Color.lerp(d.contrast, Colors.black, darkBg ? 0.25 : 0.0)!,
            d.contrast,
            Color.lerp(d.contrast, darkBg ? Colors.black : Colors.white, 0.35)!,
          ],
        ),
        border: Border.all(color: AppColors.neon, width: 3),
      ),
      child: Stack(
        children: [
          // Ilustración principal, grande y sin marco.
          Positioned(
            right: -20,
            top: 0,
            child: FadedArt(file: d.featuredArt, size: _art, radial: false),
          ),
          if (d.featured != null)
            Positioned(
              left: _pad + _leftW + 40,
              right: _pad,
              top: _art - 70,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(d.featured!.name,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: text,
                      shadows: [
                        Shadow(color: darkBg ? Colors.black : Colors.white54, blurRadius: 8),
                      ],
                    )),
              ),
            ),
          Positioned(
            right: _pad,
            bottom: 26,
            child: Text('GARAGE TCG · EDISON FORMAT',
                style: TextStyle(
                    fontSize: 16, letterSpacing: 3, fontWeight: FontWeight.w800, color: muted)),
          ),
          Padding(
            padding: const EdgeInsets.all(_pad),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _art + 40 - 2 * _pad),
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
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                    color: accent),
                              ),
                              Text(t.playerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
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

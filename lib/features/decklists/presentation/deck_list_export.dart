import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/export/export_models.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../app/widgets/common.dart';
import '../../../app/widgets/table_export.dart';
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

/// Proporción de la imagen exportada.
enum DeckListFormat {
  /// Horizontal de 1600 px; el alto depende de la lista.
  natural('Actual'),

  /// 16:9 (1920 × 1080): las cartas se ajustan para que quepa toda la lista.
  wide('16:9');

  const DeckListFormat(this.label);
  final String label;
}

/// Qué compartir de una lista: la imagen (en uno de los dos formatos) o el
/// archivo .ydk.
enum DeckListShare {
  natural,
  wide,
  ydk;

  DeckListFormat get format => this == wide ? DeckListFormat.wide : DeckListFormat.natural;
}

/// Menú de compartir de una o varias listas: imagen Actual, imagen 16:9 o .ydk.
Future<DeckListShare?> askDeckListShare(BuildContext context, {int count = 1}) =>
    showModalBottomSheet<DeckListShare>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (count > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Compartir las $count listas',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ListTile(
              leading: const Icon(Icons.crop_landscape),
              title: Text(count > 1 ? 'Imágenes · Actual' : 'Imagen · Actual'),
              subtitle: const Text('1600 px de ancho, el alto según la lista'),
              onTap: () => Navigator.pop(ctx, DeckListShare.natural),
            ),
            ListTile(
              leading: const Icon(Icons.crop_16_9),
              title: Text(count > 1 ? 'Imágenes · 16:9' : 'Imagen · 16:9'),
              subtitle: const Text('1920 × 1080, las cartas se ajustan para que quepa todo'),
              onTap: () => Navigator.pop(ctx, DeckListShare.wide),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(count > 1 ? 'Archivos .ydk' : 'Archivo .ydk'),
              subtitle: const Text('Para importar la lista en el simulador'),
              onTap: () => Navigator.pop(ctx, DeckListShare.ydk),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

/// Una lista para compartir: de quién es, sus cartas y la carta principal.
typedef DeckListEntry = ({DeckListTarget target, DeckCards cards, int? featured});

/// Todo lo que necesita la imagen (archivos ya en el teléfono).
class DeckListArt {
  const DeckListArt({
    required this.target,
    required this.cards,
    required this.db,
    required this.small,
    this.featured,
    this.featuredArt,
    required this.tone,
  });

  final DeckListTarget target;
  final DeckCards cards;
  final CardDb db;
  final Map<int, File> small;
  final YgoCard? featured;
  final File? featuredArt;

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

String _shareText(DeckListTarget t) => '${t.position == null ? '' : '${t.position}º · '}'
    '${t.playerName} · ${t.deckName ?? ''} · ${t.tournamentName}';

/// Comparte una o varias listas según [option]: imágenes (todas juntas en el
/// mismo menú de compartir) o archivos .ydk.
Future<void> shareDeckLists(
  BuildContext context, {
  required DeckListShare option,
  required List<DeckListEntry> lists,
  required CardDb? db,
  required CardImageStore store,
}) async {
  if (lists.isEmpty || _exporting) return;
  _exporting = true;
  try {
    if (option == DeckListShare.ydk) {
      await _shareYdk(lists);
      return;
    }
    if (db == null) {
      showMessage(context, 'La base de cartas aún no está lista.', error: true);
      return;
    }
    final wide = option == DeckListShare.wide;
    final files = <File>[];
    var missing = 0;
    for (var i = 0; i < lists.length; i++) {
      if (!context.mounted) return;
      showMessage(
          context,
          lists.length == 1
              ? 'Preparando la imagen…'
              : 'Preparando imagen ${i + 1} de ${lists.length}…');
      final (spec, faltan) = await _deckListSpec(lists[i], db: db, store: store, wide: wide);
      missing += faltan;
      if (!context.mounted) return;
      final file = await renderExportImage(context, spec);
      if (file != null) files.add(file);
    }
    if (!context.mounted || files.isEmpty) return;
    if (missing > 0) {
      showMessage(context, '$missing carta(s) sin imagen (sin conexión): salen con su nombre.',
          error: true);
    }
    await SharePlus.instance.share(ShareParams(
      files: [
        for (final f in files)
          XFile(f.path, mimeType: 'image/png', name: f.uri.pathSegments.last),
      ],
      text: lists.length == 1
          ? _shareText(lists.first.target)
          : 'Listas del Top ${lists.length} · ${lists.first.target.tournamentName}',
    ));
  } catch (e) {
    if (context.mounted) showMessage(context, 'No se pudo compartir: $e', error: true);
  } finally {
    _exporting = false;
  }
}

Future<void> _shareYdk(List<DeckListEntry> lists) async {
  final dir = await getTemporaryDirectory();
  final files = <XFile>[];
  for (final l in lists) {
    final t = l.target;
    final name = '${t.position == null ? '' : '${t.position}_'}'
            '${t.playerName}_${t.deckName ?? 'mazo'}'
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
    final file = File('${dir.path}/$name.ydk');
    await file.writeAsString(l.cards.toYdk(), flush: true);
    files.add(XFile(file.path, mimeType: 'text/plain', name: '$name.ydk'));
  }
  await SharePlus.instance.share(ShareParams(
    files: files,
    text: lists.length == 1
        ? _shareText(lists.first.target)
        : 'Listas del Top ${lists.length} · ${lists.first.target.tournamentName}',
  ));
}

/// Prepara la imagen de una lista (descarga las cartas que falten).
/// Devuelve la especificación y cuántas cartas quedaron sin imagen.
Future<(ExportSpec<int>, int)> _deckListSpec(
  DeckListEntry entry, {
  required CardDb db,
  required CardImageStore store,
  required bool wide,
}) async {
  final (:target, :cards, :featured) = entry;
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
  // 2) Ilustración principal y su color.
  final mainId = featured ?? _fallbackFeatured(cards, db);
  final featuredArt = mainId == null ? null : await store.get(mainId, CardImageSize.art);
  final dominant = featuredArt == null ? null : await averageColor(featuredArt);

  final data = DeckListArt(
    target: target,
    cards: cards,
    db: db,
    small: small,
    featured: mainId == null ? null : db.byId(mainId),
    featuredArt: featuredArt,
    tone: harmonyBackground(dominant ?? AppColors.forest),
  );
  final poster = DeckListPoster(data: data, wide: wide);
  final position = target.position == null ? '' : '${target.position}_';
  return (
    ExportSpec<int>(
      heading: 'LISTA · ${target.playerName}',
      items: const [],
      page: poster,
      contentWidth: poster.width,
      summaryHeightEstimate: poster.estimatedHeight,
      legend: '',
      fileBase: 'lista${wide ? '_16x9' : ''}_$position${_fileSafe(target.playerName)}_'
          '${_fileSafe(target.tournamentName)}',
      shareText: _shareText(target),
      preload: [
        for (final f in small.values) FileImage(f),
        if (featuredArt != null) FileImage(featuredArt),
      ],
    ),
    missing,
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

/// Bandera de Cuba (5 franjas, triángulo rojo y estrella blanca).
class CubaFlag extends StatelessWidget {
  const CubaFlag({super.key, this.height = 24});

  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height * 0.08),
        child: CustomPaint(size: Size(height * 2, height), painter: const _CubaFlagPainter()),
      );
}

class _CubaFlagPainter extends CustomPainter {
  const _CubaFlagPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const blue = Color(0xFF002A8F);
    const red = Color(0xFFCF142B);
    final w = size.width, h = size.height, stripe = h / 5;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    for (final i in [0, 2, 4]) {
      canvas.drawRect(Rect.fromLTWH(0, i * stripe, w, stripe), Paint()..color = blue);
    }
    final tri = h * math.sqrt(3) / 2; // triángulo equilátero
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(tri, h / 2)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = red,
    );
    // Estrella de 5 puntas en el centro del triángulo.
    final c = Offset(tri / 3, h / 2);
    final r = h * 0.17, ri = r * 0.4;
    final star = Path();
    for (var k = 0; k < 10; k++) {
      final rad = k.isEven ? r : ri;
      final a = -math.pi / 2 + k * math.pi / 5;
      final p = c + Offset(math.cos(a) * rad, math.sin(a) * rad);
      if (k == 0) {
        star.moveTo(p.dx, p.dy);
      } else {
        star.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(star..close(), Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ───────────────────────── Fórmulas de tamaño ─────────────────────────

/// Ancho de carta más grande con el que todas las secciones caben en
/// [width] × [height] (cada sección suma [perSection] de título y márgenes).
/// Las cartas de cada fila se colocan con [gap] de separación.
double fitCardWidth({
  required List<int> counts,
  required double width,
  required double height,
  required double gap,
  required double perSection,
  double maxWidth = 140,
}) {
  double used(double cw) {
    final cols = math.max(1, ((width + gap) / (cw + gap)).floor());
    var t = 0.0;
    for (final n in counts) {
      if (n == 0) continue;
      t += perSection + (n / cols).ceil() * (cw * _cardRatio + gap);
    }
    return t;
  }

  var lo = 12.0, hi = maxWidth;
  if (used(hi) <= height) return hi;
  for (var i = 0; i < 40; i++) {
    final mid = (lo + hi) / 2;
    if (used(mid) <= height) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo.floorToDouble();
}

// ───────────────────────── Imagen de la lista ─────────────────────────

/// Imagen de la lista (diseño único):
/// - fondo en degradado del mismo tono que la ilustración principal;
/// - a la derecha, la ilustración principal ocupando todo el alto, sin marco,
///   fundiéndose por la izquierda; abajo "GARAGE TCG · EDISON FORMAT · CUBA"
///   con la bandera;
/// - a la izquierda, como los carteles de Edison: GARAGE TCG, torneo y fecha,
///   puesto en dorado, jugador, "MAZO" y el mazo; MAIN (panel morado, 10 por
///   fila), SIDE (turquesa) y EXTRA (naranja), una imagen por copia.
/// [wide]: 1920 × 1080 fijo (cartas ajustadas); si no, 1600 de ancho y alto
/// según la lista.
class DeckListPoster extends StatelessWidget {
  const DeckListPoster({super.key, required this.data, this.wide = false});

  final DeckListArt data;
  final bool wide;

  double get width => wide ? 1920 : 1600;
  double get _artW => wide ? 720 : 660;
  double get _pad => wide ? 30 : 40;

  /// Ancho de la zona de la lista.
  double get _listW => width - _artW - _pad;

  static const _panelPad = 10.0;
  static const _panelBorder = 2.0;
  static const _labelH = 38.0;
  static const _mainGap = 6.0;
  static const _rowGap = 4.0;
  double get _header => wide ? 250 : 300;

  /// Ancho útil dentro de un panel.
  double get _inner => _listW - 2 * _panelPad - 2 * _panelBorder - 2;

  static const _sections = [
    (DeckSection.main, 'MAIN', Color(0xFF8E5BD6)),
    (DeckSection.side, 'SIDE', Color(0xFF2EA6A6)),
    (DeckSection.extra, 'EXTRA', Color(0xFFD08A3A)),
  ];

  int _count(DeckSection s) => data.cards.of(s).length;

  /// Side y Extra: una fila de hasta 15 (si hay más, siguen en otra).
  double get _rowCard {
    final n = math.max(_count(DeckSection.side), _count(DeckSection.extra));
    final cols = math.min(15, math.max(10, n));
    return (_inner - (cols - 1) * _rowGap) / cols;
  }

  int _rows(int n, double cw, double gap) {
    // + 1e-9: (inner+gap)/(cw+gap) puede dar 12.999… cuando cw sale de dividir
    // el ancho exacto entre 13 columnas.
    final cols = math.max(1, ((_inner + gap) / (cw + gap) + 1e-9).floor());
    return (n / cols).ceil();
  }

  double _panelH(int n, double cw, double gap) => n == 0
      ? 0
      : _labelH +
          2 * _panelPad +
          2 * _panelBorder +
          _rows(n, cw, gap) * (cw * _cardRatio + gap) -
          gap;

  /// Main: 10 por fila; en 16:9, lo que quepa en el alto que queda.
  double get _mainCard {
    final ten = (_inner - 9 * _mainGap) / 10;
    if (!wide) return ten;
    final rest = 1080 -
        2 * _pad -
        _header -
        _panelH(_count(DeckSection.side), _rowCard, _rowGap) -
        _panelH(_count(DeckSection.extra), _rowCard, _rowGap) -
        12;
    return math.min(
      ten,
      fitCardWidth(
        counts: [_count(DeckSection.main)],
        width: _inner,
        height: rest,
        gap: _mainGap,
        perSection: _labelH + 2 * _panelPad + 2 * _panelBorder,
        maxWidth: ten,
      ),
    );
  }

  double get estimatedHeight {
    if (wide) return 1080;
    final h = 2 * _pad +
        _header +
        _panelH(_count(DeckSection.main), _mainCard, _mainGap) +
        _panelH(_count(DeckSection.side), _rowCard, _rowGap) +
        _panelH(_count(DeckSection.extra), _rowCard, _rowGap) +
        60;
    return math.max(h, 1000);
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final t = d.target;
    const gold = Color(0xFFE9C46A);
    const white = Colors.white;
    final shadow = [const Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2))];
    final k = wide ? 0.85 : 1.0; // letra algo menor en 16:9
    TextStyle style(double size, {Color color = white, FontWeight w = FontWeight.w900}) =>
        TextStyle(
            fontSize: size * k, color: color, fontWeight: w, shadows: shadow, height: 1.05);
    final mainCard = _mainCard, rowCard = _rowCard;

    Widget panel(DeckSection s, String name, Color color) {
      final isMain = s == DeckSection.main;
      final cw = isMain ? mainCard : rowCard;
      final gap = isMain ? _mainGap : _rowGap;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _labelH,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('$name: ${_count(s)}', style: style(24, w: FontWeight.w800)),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(_panelPad),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color, width: _panelBorder),
            ),
            child: Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final c in _everyCopy(d.cards, s, d.db))
                  _CardTile(card: c, file: d.small[c.id], width: cw),
              ],
            ),
          ),
        ],
      );
    }

    final header = SizedBox(
      height: _header,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(
            children: [
              Image.asset(BrandAssets.logo,
                  width: 84 * k, height: 84 * k, filterQuality: FilterQuality.high),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('GARAGE TCG', style: style(56).copyWith(letterSpacing: 3)),
                    Text(
                      '${t.tournamentName.toUpperCase()} · '
                      '${DateFormat('dd/MM/yy').format(t.date)}',
                      style: style(22, w: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14 * k),
          if (d.positionLabel.isNotEmpty) Text(d.positionLabel, style: style(46, color: gold)),
          Text(t.playerName,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: style(38, w: FontWeight.w800)),
          Text('MAZO', style: style(16, w: FontWeight.w700)),
          Text(t.deckName ?? 'Sin mazo',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: style(48)),
        ],
      ),
    );

    final content = Padding(
      padding: EdgeInsets.fromLTRB(_pad, _pad, 0, _pad),
      child: SizedBox(
        width: _listW,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            header,
            for (final (s, name, color) in _sections)
              if (_count(s) > 0) panel(s, name, color),
          ],
        ),
      ),
    );

    return Container(
      width: width,
      height: wide ? 1080 : null,
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
          // Ilustración principal: todo el alto del lado derecho.
          Positioned(
            left: width - _artW - 70,
            top: 0,
            right: 0,
            bottom: 0,
            child: EdgeFade(left: 0.2, child: _artFill(d.featuredArt)),
          ),
          // Comunidad, formato y país.
          Positioned(
            right: _pad,
            bottom: _pad - 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('GARAGE TCG · EDISON FORMAT · CUBA',
                    style: style(22, w: FontWeight.w900).copyWith(letterSpacing: 1.5)),
                const SizedBox(width: 12),
                DecoratedBox(
                  decoration: const BoxDecoration(
                    boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 8)],
                  ),
                  child: CubaFlag(height: 24 * k),
                ),
              ],
            ),
          ),
          if (wide)
            Positioned.fill(child: Align(alignment: Alignment.topLeft, child: content))
          else
            ConstrainedBox(constraints: const BoxConstraints(minHeight: 1000), child: content),
        ],
      ),
    );
  }
}

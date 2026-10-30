import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/neon_table.dart';
import '../../../decks/presentation/deck_image.dart';
import '../../domain/tournament_report.dart';

/// Imagen del sector "Otros" (mazos con un solo jugador).
const kOthersImage = 'assets/export/otros.webp';

/// Colores de respaldo del gráfico, para mazos sin imagen.
const kMetaPalette = <Color>[
  Color(0xFF4C8DF6), Color(0xFFA78BFA), Color(0xFFF5A35C), Color(0xFFE8D44D),
  Color(0xFF4FD1C5), Color(0xFFE0607E), Color(0xFF8CF04C), Color(0xFF60A5FA),
  Color(0xFFF472B6), Color(0xFF34D399), Color(0xFFFB923C), Color(0xFFC084FC),
  Color(0xFFFACC15), Color(0xFF38BDF8), Color(0xFFF87171), Color(0xFFA3E635),
];
const kMetaOther = Color(0xFF7A8580);
const kMetaNoDeck = Color(0xFF3A4A40);

/// Color de respaldo de cada sector (clave null = sin mazo).
Map<String?, Color> metaColors(List<DeckShare> meta) {
  final out = <String?, Color>{};
  var i = 0;
  for (final d in meta) {
    if (d.isOthers) continue;
    if (d.name == null) {
      out[null] = kMetaNoDeck;
    } else {
      out[d.name] = i < kMetaPalette.length ? kMetaPalette[i] : kMetaOther;
      i++;
    }
  }
  return out;
}

String deckLabel(String? name) => name ?? 'Sin mazo';

/// Ruta de la imagen de un sector: la del mazo, o la de "Otros".
String? chartImagePath(DeckShare d) => d.isOthers ? kOthersImage : d.imagePath;

// ───────────────────────── Imágenes del gráfico ─────────────────────────

/// Imágenes ya decodificadas para pintar el gráfico, por ruta.
typedef ChartImages = Map<String, ui.Image>;

Future<ui.Image?> _resolve(ImageProvider provider) {
  final done = Completer<ui.Image?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!done.isCompleted) {
        done.complete(info.image.clone());
      }
      info.dispose();
      stream.removeListener(listener);
    },
    onError: (_, _) {
      if (!done.isCompleted) done.complete(null);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  // Tiempo límite: se completa con null y se quita el listener, para que una
  // imagen que llegue tarde no se clone (y quede sin liberar).
  final timer = Timer(const Duration(seconds: 6), () {
    if (!done.isCompleted) done.complete(null);
    stream.removeListener(listener);
  });
  return done.future.whenComplete(timer.cancel);
}

/// Carga las imágenes de los sectores. Hay que liberarlas con
/// [disposeChartImages] cuando ya no se usen.
Future<ChartImages> loadChartImages(List<DeckShare> chart) async {
  final out = <String, ui.Image>{};
  for (final d in chart) {
    final path = chartImagePath(d);
    if (path == null || out.containsKey(path)) continue;
    final provider = path == kOthersImage ? const AssetImage(kOthersImage) : deckImageProvider(path);
    if (provider == null) continue;
    final img = await _resolve(provider);
    if (img != null) out[path] = img;
  }
  return out;
}

void disposeChartImages(ChartImages images) {
  for (final i in images.values) {
    i.dispose();
  }
}

// ───────────────────────── Gráfico de dona ─────────────────────────

/// Dona del metagame: cada sector se rellena con la imagen de su mazo (los
/// mazos de un solo jugador van juntos en "Otros"), con su % encima si cabe y
/// los jugadores en el centro. Sin animación, para poder exportarla.
class MetaDonut extends StatelessWidget {
  const MetaDonut({
    super.key,
    required this.chart,
    required this.images,
    required this.size,
    this.centerSubtitle = 'JUGADORES',
  });

  final List<DeckShare> chart;
  final ChartImages images;
  final double size;
  final String centerSubtitle;

  @override
  Widget build(BuildContext context) {
    final total = chart.isEmpty ? 0 : chart.first.total;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _DonutPainter(
          chart: chart,
          images: images,
          colors: metaColors(chart),
          center: '$total',
          subtitle: centerSubtitle,
        ),
      ),
    );
  }
}

/// [MetaDonut] que carga él mismo las imágenes (para la pantalla).
class MetaDonutView extends StatefulWidget {
  const MetaDonutView({super.key, required this.chart, required this.size});

  final List<DeckShare> chart;
  final double size;

  @override
  State<MetaDonutView> createState() => _MetaDonutViewState();
}

class _MetaDonutViewState extends State<MetaDonutView> {
  ChartImages _images = const {};
  String _loadedKey = '';
  int _generation = 0;

  String _keyOf(List<DeckShare> chart) => chart.map(chartImagePath).join('|');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MetaDonutView old) {
    super.didUpdateWidget(old);
    if (_keyOf(widget.chart) != _loadedKey) _load();
  }

  Future<void> _load() async {
    final gen = ++_generation;
    final key = _keyOf(widget.chart);
    final images = await loadChartImages(widget.chart);
    if (!mounted || gen != _generation) {
      disposeChartImages(images);
      return;
    }
    final old = _images;
    setState(() {
      _images = images;
      _loadedKey = key;
    });
    disposeChartImages(old);
  }

  @override
  void dispose() {
    _generation++;
    disposeChartImages(_images);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MetaDonut(chart: widget.chart, images: _images, size: widget.size);
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.chart,
    required this.images,
    required this.colors,
    required this.center,
    required this.subtitle,
  });

  final List<DeckShare> chart;
  final ChartImages images;
  final Map<String?, Color> colors;
  final String center;
  final String subtitle;

  static Path _ring(Offset c, double inner, double outer, double start, double sweep) {
    if (sweep >= 2 * math.pi - 1e-6) {
      return Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: c, radius: outer))
        ..addOval(Rect.fromCircle(center: c, radius: inner));
    }
    return Path()
      ..arcTo(Rect.fromCircle(center: c, radius: outer), start, sweep, true)
      ..arcTo(Rect.fromCircle(center: c, radius: inner), start + sweep, -sweep, false)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    final outer = s / 2;
    final thickness = s * 0.26;
    final inner = outer - thickness;
    final separator = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(s * 0.006, 1.5)
      ..color = const Color(0xFF0B0B0D);
    var start = -math.pi / 2;

    // 1) Sectores con su imagen (o color si el mazo no tiene imagen).
    final labels = <(DeckShare, double)>[];
    for (final d in chart) {
      final sweep = d.fraction * 2 * math.pi;
      if (sweep <= 0) continue;
      final path = _ring(c, inner, outer, start, sweep);
      final img = images[chartImagePath(d) ?? ''];
      if (img != null) {
        canvas.save();
        canvas.clipPath(path);
        canvas.drawPath(path, Paint()..color = const Color(0xFF15261A));
        paintImage(
          canvas: canvas,
          rect: path.getBounds(),
          image: img,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        );
        canvas.restore();
      } else {
        canvas.drawPath(
            path, Paint()..color = d.isOthers ? kMetaOther : colors[d.name] ?? kMetaOther);
      }
      if (chart.length > 1) canvas.drawPath(path, separator);
      labels.add((d, start + sweep / 2));
      start += sweep;
    }

    // 2) Etiquetas (% y "OTROS") sobre fondo oscuro para que se lean.
    final mid = (inner + outer) / 2;
    for (final (d, angle) in labels) {
      if (d.fraction < 0.04 && !d.isOthers) continue;
      final pos = c + Offset(math.cos(angle), math.sin(angle)) * mid;
      _pill(canvas, pos, s,
          top: d.isOthers ? 'OTROS' : null, main: sharePct(d.fraction).replaceAll(' ', ''));
    }

    // 3) Centro.
    _text(canvas, center, c - Offset(0, s * 0.035),
        fontSize: s * 0.13, color: AppColors.textPrimary, weight: FontWeight.w900);
    _text(canvas, subtitle, c + Offset(0, s * 0.06),
        fontSize: s * 0.038,
        color: AppColors.textSecondary,
        weight: FontWeight.w700,
        letterSpacing: s * 0.004);
  }

  TextPainter _layout(String text, double fontSize, Color color, FontWeight weight,
          {double letterSpacing = 0}) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: fontSize,
            fontWeight: weight,
            color: color,
            letterSpacing: letterSpacing,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();

  void _pill(Canvas canvas, Offset center, double s, {String? top, required String main}) {
    final a = top == null ? null : _layout(top, s * 0.03, AppColors.neonBright, FontWeight.w800);
    final b = _layout(main, s * 0.045, Colors.white, FontWeight.w900);
    final w = math.max(a?.width ?? 0, b.width) + s * 0.03;
    final h = (a?.height ?? 0) + b.height + s * 0.012;
    final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: w, height: h), Radius.circular(s * 0.02));
    canvas.drawRRect(rect, Paint()..color = Colors.black.withValues(alpha: 0.72));
    var y = center.dy - h / 2 + s * 0.006;
    if (a != null) {
      a.paint(canvas, Offset(center.dx - a.width / 2, y));
      y += a.height;
    }
    b.paint(canvas, Offset(center.dx - b.width / 2, y));
  }

  void _text(Canvas canvas, String text, Offset center,
      {required double fontSize,
      required Color color,
      required FontWeight weight,
      double letterSpacing = 0}) {
    final tp = _layout(text, fontSize, color, weight, letterSpacing: letterSpacing);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.chart != chart || old.images != images || old.center != center;
}

// ───────────────────────── Leyenda ─────────────────────────

/// Fila de la leyenda: imagen del mazo, nombre, jugadores y %.
class MetaLegendRow extends StatelessWidget {
  const MetaLegendRow({
    super.key,
    required this.share,
    this.fontSize = 14,
    this.indent = 0,
    this.label,
  });

  final DeckShare share;
  final double fontSize;
  final double indent;

  /// Texto en lugar del nombre del mazo (p. ej. "OTROS").
  final String? label;

  @override
  Widget build(BuildContext context) {
    final strong = indent == 0;
    return Padding(
      padding: EdgeInsets.only(left: indent, top: fontSize * 0.2, bottom: fontSize * 0.2),
      child: Row(
        children: [
          DeckImage(
            path: chartImagePath(share),
            name: label ?? deckLabel(share.name),
            width: fontSize * (strong ? 1.9 : 1.5),
          ),
          SizedBox(width: fontSize * 0.6),
          Expanded(
            child: Text(label ?? deckLabel(share.name),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: strong ? fontSize : fontSize * 0.92,
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                  color: strong ? AppColors.textPrimary : AppColors.textSecondary,
                )),
          ),
          Text('${share.players}',
              style: TextStyle(
                  fontSize: fontSize, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
          SizedBox(
            width: fontSize * 4.2,
            child: Text(sharePct(share.fraction),
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: fontSize, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

/// Filas de la leyenda en el orden del gráfico: cada mazo con 2 o más
/// jugadores y, al final, "OTROS" con los nombres de los mazos que lo forman.
List<Widget> metaLegendRows(TournamentReport report, {double fontSize = 14}) => [
      for (final d in report.chart) ...[
        if (d.isOthers)
          MetaLegendRow(share: d, fontSize: fontSize, label: 'OTROS')
        else
          MetaLegendRow(share: d, fontSize: fontSize),
        for (final m in d.members)
          MetaLegendRow(share: m, fontSize: fontSize, indent: fontSize * 1.2),
      ],
    ];

/// Etiqueta del mazo: su imagen pequeña y el nombre.
class DeckChip extends StatelessWidget {
  const DeckChip({super.key, required this.name, this.imagePath, this.fontSize = 12});

  final String? name;
  final String? imagePath;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = name == null ? AppColors.textSecondary : AppColors.textPrimary;
    return Container(
      padding: EdgeInsets.fromLTRB(
          fontSize * 0.2, fontSize * 0.2, fontSize * 0.7, fontSize * 0.2),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(fontSize * 2),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DeckImage(path: imagePath, name: deckLabel(name), width: fontSize * 1.6),
          SizedBox(width: fontSize * 0.4),
          Flexible(
            child: Text(deckLabel(name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: c)),
          ),
        ],
      ),
    );
  }
}

/// Línea "Metagame": los 3 mazos más jugados con su % y "+N" del resto.
class MetaHeadline extends StatelessWidget {
  const MetaHeadline({super.key, required this.meta, this.fontSize = 13});

  final List<DeckShare> meta;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final named = meta.where((d) => d.name != null).toList();
    final top = named.take(3).toList();
    final rest = named.length - top.length;
    return Wrap(
      spacing: fontSize,
      runSpacing: fontSize * 0.4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Metagame',
            style: TextStyle(fontSize: fontSize * 1.15, fontWeight: FontWeight.w900)),
        for (final d in top)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DeckImage(path: d.imagePath, name: deckLabel(d.name), width: fontSize * 1.5),
              SizedBox(width: fontSize * 0.35),
              Flexible(
                child: Text('${d.name} ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: fontSize)),
              ),
              Text(sharePct(d.fraction).replaceAll(' ', ''),
                  style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900)),
            ],
          ),
        if (rest > 0)
          Text('+$rest',
              style: TextStyle(fontSize: fontSize, color: AppColors.textSecondary)),
      ],
    );
  }
}

// ───────────────────────── Tabla de participantes ─────────────────────────

/// Tabla "Participantes" (pantalla y exportación): #, jugador, récord,
/// % de victorias y mazo. Los del Top Cut con la franja verde.
class ParticipantsTable extends StatelessWidget {
  const ParticipantsTable({
    super.key,
    required this.lines,
    this.width,
    this.fontSize = 14,
    this.rowPadding = 8,
    this.onTapPlayer,
  });

  final List<ParticipantLine> lines;

  /// Ancho fijo (exportación). null = el de la pantalla.
  final double? width;
  final double fontSize;
  final double rowPadding;
  final void Function(String playerId)? onTapPlayer;

  @override
  Widget build(BuildContext context) {
    // Exportación: el mazo en su columna. En pantalla: debajo del nombre.
    final big = width != null;
    Widget chip(ParticipantLine p) =>
        DeckChip(name: p.deck, imagePath: p.deckImage, fontSize: fontSize - 3);
    Widget name(ParticipantLine p) => Text(p.dropped ? '${p.name} (drop)' : p.name,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w800, color: p.madeTop ? AppColors.neon : null));
    return NeonTable(
      fixedWidth: width,
      fontSize: fontSize,
      rowPadding: rowPadding,
      headerColor: big ? AppColors.neon : AppColors.textSecondary,
      columns: [
        NeonColumn('#', width: big ? 44 : 30, align: TextAlign.start),
        NeonColumn(big ? 'Jugador' : 'Jugador · mazo',
            width: big ? 220 : 150, align: TextAlign.start, flex: true),
        NeonColumn('Récord', width: big ? 92 : 60),
        NeonColumn('Win %', width: big ? 80 : 52),
        if (big) const NeonColumn('Mazo', width: 230, align: TextAlign.start),
      ],
      rows: [
        for (final p in lines)
          NeonTableRow(
            accent: p.madeTop ? AppColors.neon : null,
            dim: p.dropped && !p.madeTop,
            onTap: onTapPlayer == null ? null : () => onTapPlayer!(p.playerId),
            cells: [
              Text(p.position == null ? '-' : '${p.position}',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              if (big)
                name(p)
              else
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [name(p), const SizedBox(height: 3), chip(p)],
                ),
              Text(p.record, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(p.played == 0 ? '-' : '${(p.winRate * 100).round()}%'),
              if (big) Align(alignment: Alignment.centerLeft, child: chip(p)),
            ],
          ),
      ],
    );
  }
}

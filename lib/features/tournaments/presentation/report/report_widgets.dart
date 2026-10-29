import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../app/widgets/neon_table.dart';
import '../../domain/tournament_report.dart';

/// Colores del metagame (vivos, se leen sobre fondo oscuro). El mazo más
/// jugado lleva el primero; a partir del 17º todos van en gris ("otros").
const kMetaPalette = <Color>[
  Color(0xFF4C8DF6), Color(0xFFA78BFA), Color(0xFFF5A35C), Color(0xFFE8D44D),
  Color(0xFF4FD1C5), Color(0xFFE0607E), Color(0xFF8CF04C), Color(0xFF60A5FA),
  Color(0xFFF472B6), Color(0xFF34D399), Color(0xFFFB923C), Color(0xFFC084FC),
  Color(0xFFFACC15), Color(0xFF38BDF8), Color(0xFFF87171), Color(0xFFA3E635),
];
const kMetaOther = Color(0xFF7A8580);
const kMetaNoDeck = Color(0xFF3A4A40);

/// Color de cada mazo del metagame (clave null = sin mazo).
Map<String?, Color> metaColors(List<DeckShare> meta) {
  final out = <String?, Color>{};
  var i = 0;
  for (final d in meta) {
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

// ───────────────────────── Gráfico de dona ─────────────────────────

/// Gráfico de dona del metagame: un sector por mazo, con su % dentro si cabe
/// y el número de jugadores en el centro. Sin animación (se puede exportar).
class MetaDonut extends StatelessWidget {
  const MetaDonut({
    super.key,
    required this.meta,
    required this.colors,
    required this.size,
    this.centerTitle,
    this.centerSubtitle = 'JUGADORES',
  });

  final List<DeckShare> meta;
  final Map<String?, Color> colors;
  final double size;
  final String? centerTitle;
  final String centerSubtitle;

  @override
  Widget build(BuildContext context) {
    final total = meta.isEmpty ? 0 : meta.first.total;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _DonutPainter(
          meta: meta,
          colors: colors,
          center: centerTitle ?? '$total',
          subtitle: centerSubtitle,
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.meta,
    required this.colors,
    required this.center,
    required this.subtitle,
  });

  final List<DeckShare> meta;
  final Map<String?, Color> colors;
  final String center;
  final String subtitle;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    final thickness = s * 0.2;
    final radius = s / 2 - thickness / 2;
    final rect = Rect.fromCircle(center: c, radius: radius);
    final gap = meta.length > 1 ? 0.012 : 0.0;
    var start = -math.pi / 2;

    for (final d in meta) {
      final sweep = d.fraction * 2 * math.pi;
      if (sweep <= 0) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = colors[d.name] ?? kMetaOther;
      final drawn = math.max(sweep - gap, 0.002);
      canvas.drawArc(rect, start + (sweep - drawn) / 2, drawn, false, paint);
      // % dentro del sector, si cabe.
      if (d.fraction >= 0.04) {
        final mid = start + sweep / 2;
        final pos = c + Offset(math.cos(mid), math.sin(mid)) * radius;
        _text(canvas, sharePct(d.fraction).replaceAll(' ', ''), pos,
            fontSize: s * 0.045, color: Colors.black, weight: FontWeight.w900);
      }
      start += sweep;
    }

    _text(canvas, center, c - Offset(0, s * 0.035),
        fontSize: s * 0.13, color: AppColors.textPrimary, weight: FontWeight.w900);
    _text(canvas, subtitle, c + Offset(0, s * 0.06),
        fontSize: s * 0.038, color: AppColors.textSecondary, weight: FontWeight.w700,
        letterSpacing: s * 0.004);
  }

  void _text(Canvas canvas, String text, Offset center,
      {required double fontSize,
      required Color color,
      required FontWeight weight,
      double letterSpacing = 0}) {
    final tp = TextPainter(
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
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.meta != meta || old.colors != colors || old.center != center;
}

// ───────────────────────── Leyenda y etiquetas ─────────────────────────

/// Fila de la leyenda: color, mazo, jugadores y %.
class MetaLegendRow extends StatelessWidget {
  const MetaLegendRow({super.key, required this.share, required this.color, this.fontSize = 14});

  final DeckShare share;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: fontSize * 0.25),
      child: Row(
        children: [
          Container(
            width: fontSize * 0.9,
            height: fontSize * 0.9,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
          SizedBox(width: fontSize * 0.6),
          Expanded(
            child: Text(deckLabel(share.name),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700)),
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

/// Etiqueta del mazo (borde y texto del color del mazo), como en TopDeck.
class DeckChip extends StatelessWidget {
  const DeckChip({super.key, required this.name, required this.color, this.fontSize = 12});

  final String? name;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = name == null ? AppColors.textSecondary : color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.7, vertical: fontSize * 0.25),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(fontSize * 2),
        border: Border.all(color: c.withValues(alpha: 0.8)),
      ),
      child: Text(deckLabel(name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: c)),
    );
  }
}

/// Barra "Metagame": los 3 mazos más jugados con su % y "+N" del resto.
class MetaHeadline extends StatelessWidget {
  const MetaHeadline({super.key, required this.meta, required this.colors, this.fontSize = 13});

  final List<DeckShare> meta;
  final Map<String?, Color> colors;
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
              Container(
                  width: fontSize * 0.6,
                  height: fontSize * 0.6,
                  decoration: BoxDecoration(
                      color: colors[d.name], borderRadius: BorderRadius.circular(2))),
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
/// % de victorias y mazo. Los del Top Cut con la franja de color.
class ParticipantsTable extends StatelessWidget {
  const ParticipantsTable({
    super.key,
    required this.lines,
    required this.colors,
    this.width,
    this.fontSize = 14,
    this.rowPadding = 8,
    this.onTapPlayer,
  });

  final List<ParticipantLine> lines;
  final Map<String?, Color> colors;

  /// Ancho fijo (exportación). null = el de la pantalla.
  final double? width;
  final double fontSize;
  final double rowPadding;
  final void Function(String playerId)? onTapPlayer;

  @override
  Widget build(BuildContext context) {
    // Exportación: el mazo en su columna. En pantalla: debajo del nombre.
    final big = width != null;
    Widget chip(ParticipantLine p) => DeckChip(
          name: p.deck,
          color: colors[p.deck] ?? kMetaOther,
          fontSize: fontSize - 3,
        );
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

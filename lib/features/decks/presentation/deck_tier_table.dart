import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/neon_table.dart';
import '../../../app/export/export_models.dart';
import '../../../app/export/export_sheet.dart';
import '../../../app/widgets/table_export.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/season_utils.dart';
import '../domain/deck_stats.dart';
import 'deck_image.dart';

Color tierColor(DeckTier t) => switch (t) {
      DeckTier.s => AppColors.neon,
      DeckTier.a => AppColors.leaf,
      DeckTier.b => AppColors.draw,
      DeckTier.c => AppColors.textSecondary,
    };

/// Cuadrado con la letra del tier.
class TierBadge extends StatelessWidget {
  const TierBadge(this.tier, {super.key, this.size = 26});

  final DeckTier tier;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = tierColor(tier);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: tier == DeckTier.s ? AppColors.glow(strength: 0.6) : null,
      ),
      child: Text(
        tier.label,
        style: TextStyle(
          fontSize: size * 0.62,
          fontWeight: FontWeight.w900,
          color: Colors.black,
          height: 1,
        ),
      ),
    );
  }
}

/// Tier list visual: una fila por tier con los mazos que la forman.
class TierSummary extends StatelessWidget {
  const TierSummary({super.key, required this.decks, this.forExport = false});

  final List<DeckSeasonStats> decks;
  final bool forExport;

  @override
  Widget build(BuildContext context) {
    final font = forExport ? 18.0 : 14.0;
    return Padding(
      padding: EdgeInsets.all(forExport ? 16 : 12),
      child: Column(
        children: [
          for (final tier in DeckTier.values)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: tierColor(tier).withValues(alpha: 0.6)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: forExport ? 64 : 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tierColor(tier),
                        borderRadius:
                            const BorderRadius.horizontal(left: Radius.circular(9)),
                      ),
                      child: Text(tier.label,
                          style: TextStyle(
                              fontSize: forExport ? 34 : 26,
                              fontWeight: FontWeight.w900,
                              color: Colors.black)),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: _tierDecks(tier, font),
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

  Widget _tierDecks(DeckTier tier, double font) {
    final list = decks.where((d) => d.tier == tier).toList();
    if (list.isEmpty) {
      return Text('—',
          style: TextStyle(fontSize: font, color: AppColors.textDisabled));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // La imagen de cada mazo con su puesto (en lugar del nombre).
        for (final d in list)
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: tier == DeckTier.s ? AppColors.glow(strength: 0.4) : null,
                ),
                child: DeckImage(
                    path: d.imagePath,
                    name: d.name,
                    width: forExport ? 80 : 58,
                    borderColor: tierColor(tier)),
              ),
              Positioned(
                left: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: tierColor(tier),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${d.rank}',
                      style: TextStyle(
                          fontSize: forExport ? 14 : 11,
                          fontWeight: FontWeight.w900,
                          color: Colors.black)),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Tabla de mazos de la temporada (pantalla e imágenes exportadas).
class DeckTierTable extends StatelessWidget {
  const DeckTierTable({super.key, required this.decks, this.fixedWidth, this.forExport = false});

  final List<DeckSeasonStats> decks;
  final double? fixedWidth;
  final bool forExport;

  static const columns = [
    NeonColumn('#', width: 32, align: TextAlign.start),
    NeonColumn('Tier', width: 44),
    NeonColumn('Mazo', width: 140, align: TextAlign.start, flex: true),
    NeonColumn('Score', width: 60),
    NeonColumn('Uso', width: 42),
    NeonColumn('Jug.', width: 42),
    NeonColumn('PJ', width: 38),
    NeonColumn('V', width: 34),
    NeonColumn('D', width: 34),
    NeonColumn('E', width: 34),
    NeonColumn('WR%', width: 52),
    NeonColumn('Top', width: 40),
    NeonColumn('V Top', width: 50),
    NeonColumn('Tít.', width: 40),
    NeonColumn('Mejor', width: 50),
  ];

  /// Suman 722 + 24 ≤ 750 (ancho útil de la imagen).
  static const exportColumns = [
    NeonColumn('#', width: 30, align: TextAlign.start),
    NeonColumn('Tier', width: 44),
    NeonColumn('Mazo', width: 130, align: TextAlign.start, flex: true),
    NeonColumn('Score', width: 58),
    NeonColumn('Uso', width: 42),
    NeonColumn('Jug', width: 40),
    NeonColumn('PJ', width: 40),
    NeonColumn('V', width: 36),
    NeonColumn('D', width: 36),
    NeonColumn('E', width: 34),
    NeonColumn('WR%', width: 54),
    NeonColumn('Top', width: 42),
    NeonColumn('VTop', width: 48),
    NeonColumn('Tít', width: 36),
    NeonColumn('Mejor', width: 52),
  ];

  @override
  Widget build(BuildContext context) {
    final secondary = forExport ? AppColors.textPrimary : AppColors.textSecondary;
    return NeonTable(
      fixedWidth: fixedWidth,
      columns: forExport ? exportColumns : columns,
      fontSize: forExport ? kExportFontSize : 14,
      rowPadding: forExport ? kExportRowPadding : 8,
      headerColor: forExport ? AppColors.neon : AppColors.textSecondary,
      rows: [
        for (final d in decks)
          NeonTableRow(
            highlight: d.tier == DeckTier.s,
            cells: [
              Text('${d.rank}',
                  style: TextStyle(fontWeight: FontWeight.w900, color: secondary)),
              TierBadge(d.tier, size: forExport ? 28 : 24),
              Row(
                children: [
                  DeckImage(path: d.imagePath, name: d.name, width: forExport ? 28 : 24),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(d.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: d.tier == DeckTier.s ? AppColors.neon : null,
                        )),
                  ),
                ],
              ),
              Text(d.score.toStringAsFixed(1),
                  style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.neon)),
              Text('${d.entries}'),
              Text('${d.pilots.length}'),
              Text('${d.played}'),
              Text('${d.wins}', style: const TextStyle(color: AppColors.win)),
              Text('${d.losses}', style: const TextStyle(color: AppColors.loss)),
              Text('${d.swissDraws}', style: const TextStyle(color: AppColors.draw)),
              Text(d.played == 0 ? '—' : '${(d.winrate * 100).toStringAsFixed(0)}%'),
              Text('${d.topEntries}'),
              Text('${d.topWins}'),
              Text('${d.titles}',
                  style: TextStyle(
                      fontWeight: d.titles > 0 ? FontWeight.w900 : null,
                      color: d.titles > 0 ? AppColors.neon : null)),
              Text(d.bestPosition == null ? '—' : '${d.bestPosition}º'),
            ],
          ),
      ],
    );
  }
}

const deckLegend = 'Uso = veces inscrito · Jug = jugadores distintos · PJ/V/D/E partidas '
    '(Swiss + Top) · Top = entradas al Top Cut · VTop = victorias en el Top · '
    'Tít = torneos ganados · Score = PP × (0.5 + WRp)';

// ───────────────────── Tier list exportada (estilo "tier maker") ─────────────────────

/// Color de la etiqueta de cada fila en la imagen exportada.
Color tierBoardColor(DeckTier t) => switch (t) {
      DeckTier.s => const Color(0xFFFF7F7F),
      DeckTier.a => const Color(0xFFFFBF7F),
      DeckTier.b => const Color(0xFFFFDF7F),
      DeckTier.c => const Color(0xFFBFFF7F),
    };

/// Lado de cada imagen de mazo, mazos por línea y ancho de la etiqueta.
const kBoardTile = 100.0;
const kBoardPerRow = 10;
const kBoardLabelWidth = 130.0;
const _kBoardLine = 1.0;

/// Ancho total del tablero: etiqueta + separador + imágenes + bordes.
const kBoardWidth = kBoardLabelWidth + kBoardPerRow * kBoardTile + 2 * _kBoardLine;

/// Líneas de imágenes que ocupa un tier (mínimo 1, aunque esté vacío).
int _boardLines(List<DeckSeasonStats> decks, DeckTier t) {
  final n = decks.where((d) => d.tier == t).length;
  return n == 0 ? 1 : (n / kBoardPerRow).ceil();
}

/// Alto del tablero para [decks] (para calcular la resolución de la imagen).
double tierBoardHeight(List<DeckSeasonStats> decks) {
  var h = 2 * _kBoardLine;
  for (final t in DeckTier.values) {
    h += _boardLines(decks, t) * kBoardTile + _kBoardLine;
  }
  return h;
}

/// Tier list como en las imágenes clásicas de "tier list": una fila por tier
/// con su etiqueta de color a la izquierda y las imágenes cuadradas de los
/// mazos (con el nombre encima) a la derecha, en orden de puesto.
class TierBoard extends StatelessWidget {
  const TierBoard({super.key, required this.decks});

  final List<DeckSeasonStats> decks;

  @override
  Widget build(BuildContext context) {
    const line = BorderSide(color: Colors.black, width: _kBoardLine);
    return Container(
      width: kBoardWidth,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A17),
        border: Border.all(color: Colors.black, width: _kBoardLine),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, tier) in DeckTier.values.indexed)
            Container(
              decoration: BoxDecoration(
                border: i == DeckTier.values.length - 1 ? null : const Border(bottom: line),
              ),
              child: SizedBox(
                height: _boardLines(decks, tier) * kBoardTile,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: kBoardLabelWidth,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tierBoardColor(tier),
                        border: const Border(right: line),
                      ),
                      child: Text(
                        'Tier ${tier.label}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF222222),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: kBoardPerRow * kBoardTile,
                      child: Wrap(
                        children: [
                          for (final d in decks)
                            if (d.tier == tier) _BoardTile(d),
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

class _BoardTile extends StatelessWidget {
  const _BoardTile(this.deck);

  final DeckSeasonStats deck;

  /// Tamaño de letra para que la palabra más larga quepa en el ancho.
  static double _fontFor(String name) {
    final longest = name
        .split(RegExp(r'[\s-]+'))
        .fold<int>(1, (m, w) => w.length > m ? w.length : m);
    final byWord = (kBoardTile - 8) / (longest * 0.62);
    final base = name.length > 18 ? 15.0 : 17.0;
    return byWord < base ? byWord : base;
  }

  @override
  Widget build(BuildContext context) {
    final provider = deckImageProvider(deck.imagePath);
    final font = _fontFor(deck.name);
    TextStyle style(Paint? stroke) => TextStyle(
          fontSize: font,
          height: 1.05,
          fontWeight: FontWeight.w800,
          foreground: stroke,
          color: stroke == null ? Colors.white : null,
        );
    final text = deck.name;
    return SizedBox(
      width: kBoardTile,
      height: kBoardTile,
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
                  colors: [Color(0xFF2E4A2E), Color(0xFF101810)],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(4),
            child: Center(
              child: Stack(
                children: [
                  // Contorno negro + relleno blanco: se lee sobre cualquier imagen.
                  Text(text,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: style(Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 3.2
                        ..strokeJoin = StrokeJoin.round
                        ..color = Colors.black)),
                  Text(text,
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
    );
  }
}

/// Exporta la tier list como UNA imagen al estilo "tier list" clásico
/// (filas de colores con las imágenes de los mazos), sin la tabla.
Future<void> exportDeckTierImages(
  BuildContext context, {
  required Season season,
  required List<DeckSeasonStats> decks,
}) {
  final label = seasonLabel(season.year, season.quarter);
  return runExport<DeckSeasonStats>(
    context,
    ExportSpec(
      heading: 'TIER LIST DE MAZOS · $label',
      items: decks,
      summary: TierBoard(decks: decks),
      contentWidth: kBoardWidth,
      summaryHeightEstimate: tierBoardHeight(decks),
      pdfTable: () => deckPdfTable(decks),
      legend: '${decks.length} mazos · Tier según el Score de la temporada respecto al '
          'mejor mazo: S ≥ 70 % · A ≥ 45 % · B ≥ 20 % · C resto. '
          'En cada fila, ordenados por puesto.',
      fileBase: 'tierlist_garage_tcg_${season.year}_T${season.quarter}',
      shareText: 'Tier list de mazos Garage TCG · Temporada $label',
      preload: [
        for (final d in decks)
          if (deckImageProvider(d.imagePath) case final p?) p,
      ],
    ),
  );
}

ExportTableData deckPdfTable(List<DeckSeasonStats> decks) {
  final neon = AppColors.neon.toARGB32();
  final black = Colors.black.toARGB32();
  return ExportTableData(
    columns: const [
      ExportColumnData('#', 2.6, align: ExportAlign.start),
      ExportColumnData('Tier', 3.2),
      ExportColumnData('Mazo', 13, align: ExportAlign.start),
      ExportColumnData('Score', 4.6),
      ExportColumnData('Uso', 3.4),
      ExportColumnData('Jug', 3.4),
      ExportColumnData('PJ', 3.2),
      ExportColumnData('V', 3),
      ExportColumnData('D', 3),
      ExportColumnData('E', 3),
      ExportColumnData('WR%', 4.2),
      ExportColumnData('Top', 3.4),
      ExportColumnData('VTop', 3.8),
      ExportColumnData('Tít', 3),
      ExportColumnData('Mejor', 4.2),
    ],
    rows: [
      for (final d in decks)
        ExportRowData(
          highlight: d.tier == DeckTier.s,
          [
            ExportCellData('${d.rank}', bold: true),
            ExportCellData(d.tier.label,
                bold: true, color: black, background: tierColor(d.tier).toARGB32()),
            ExportCellData(d.name, bold: true, color: d.tier == DeckTier.s ? neon : null),
            ExportCellData(d.score.toStringAsFixed(1), bold: true, color: neon),
            ExportCellData('${d.entries}'),
            ExportCellData('${d.pilots.length}'),
            ExportCellData('${d.played}'),
            ExportCellData('${d.wins}', color: AppColors.win.toARGB32()),
            ExportCellData('${d.losses}', color: AppColors.loss.toARGB32()),
            ExportCellData('${d.swissDraws}', color: AppColors.draw.toARGB32()),
            ExportCellData(d.played == 0 ? '-' : '${(d.winrate * 100).toStringAsFixed(0)}%'),
            ExportCellData('${d.topEntries}'),
            ExportCellData('${d.topWins}'),
            ExportCellData('${d.titles}', bold: d.titles > 0, color: d.titles > 0 ? neon : null),
            ExportCellData(d.bestPosition == null ? '-' : '${d.bestPosition}º'),
          ],
        ),
    ],
  );
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/brand.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/season_utils.dart';
import '../domain/ranking_row.dart';
import 'ranking_table.dart';

/// Ancho lógico de la imagen exportada (×2 de densidad = 1600 px).
const _exportWidth = 800.0;

/// Genera un PNG con la tabla COMPLETA del ranking (sin importar cuántas filas
/// tenga) y abre el menú de compartir de Android (WhatsApp, Galería, etc.).
Future<void> exportRankingImage(
  BuildContext context, {
  required Season season,
  required List<RankingRow> rows,
}) async {
  final label = seasonLabel(season.year, season.quarter);

  // El logo debe estar decodificado antes de "fotografiar" el widget.
  await precacheImage(const AssetImage(BrandAssets.logo), context);
  if (!context.mounted) return;

  final bytes = await ScreenshotController().captureFromLongWidget(
    Theme(
      data: AppTheme.dark,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          color: AppColors.background,
          child: _RankingExportView(seasonLabel: label, rows: rows),
        ),
      ),
    ),
    context: context,
    pixelRatio: 2,
    delay: const Duration(milliseconds: 150),
    constraints: const BoxConstraints(maxWidth: _exportWidth, minWidth: _exportWidth),
  );

  final dir = await getTemporaryDirectory();
  final file = File(
      '${dir.path}/ranking_garaje_tcg_${season.year}_T${season.quarter}.png');
  await file.writeAsBytes(bytes, flush: true);

  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'image/png')],
    text: 'Ranking Garaje TCG · Temporada $label',
  ));
}

/// Diseño de la imagen: cabecera con logo, tabla completa y pie.
class _RankingExportView extends StatelessWidget {
  const _RankingExportView({required this.seasonLabel, required this.rows});

  final String seasonLabel;
  final List<RankingRow> rows;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd/MM/yyyy HH:mm', 'es').format(DateTime.now());
    return Container(
      width: _exportWidth,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border.fromBorderSide(BorderSide(color: AppColors.moss, width: 2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Image.asset(BrandAssets.logo, width: 84, height: 84),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandTitle(fontSize: 30),
                    const SizedBox(height: 4),
                    Text(
                      'RANKING · TEMPORADA $seasonLabel',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: AppColors.textPrimary,
                        shadows: AppColors.textGlow(blur: 6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: RankingTable(rows: rows, fixedWidth: _exportWidth - 48 - 2),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${rows.length} jugadores · PJ partidas jugadas · WR% victorias/partidas · '
                  'Torn. torneos · Mejor posición alcanzada',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(width: 12),
              Text('Actualizado $date',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

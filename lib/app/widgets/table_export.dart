import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../theme.dart';
import 'brand.dart';

/// Ancho lógico de las imágenes exportadas.
const kExportWidth = 800.0;

/// Densidad de la captura: 800 × 2.4 = 1920 px de ancho.
const kExportPixelRatio = 2.4;

/// Filas por imagen. Con 12 filas cada imagen mide ~1920×2000 px: WhatsApp
/// apenas la reduce y el texto se lee nítido. Una sola imagen larga con
/// todas las filas se reduce muchísimo al enviarla y se vuelve ilegible.
const kExportRowsPerPage = 12;

/// Estilo de tabla para exportar: letra más grande y colores más claros.
const kExportFontSize = 17.0;
const kExportRowPadding = 10.0;

/// Exporta una tabla como una o varias imágenes PNG (paginadas) y abre el menú
/// de compartir (WhatsApp, Galería…).
///
/// [tableBuilder] recibe las filas de cada página y el ancho disponible.
/// [summary], si se da, sale como primera imagen (p. ej. la tier list).
Future<void> exportPagedTable<T>(
  BuildContext context, {
  required String heading,
  required List<T> items,
  required Widget Function(List<T> pageItems, double width) tableBuilder,
  required String legend,
  required String fileBase,
  required String shareText,
  int rowsPerPage = kExportRowsPerPage,
  Widget? summary,
}) async {
  // El logo debe estar decodificado antes de "fotografiar" el widget.
  await precacheImage(const AssetImage(BrandAssets.logo), context);
  if (!context.mounted) return;

  final pages = <List<T>>[
    for (var i = 0; i < items.length; i += rowsPerPage)
      items.sublist(i, (i + rowsPerPage).clamp(0, items.length)),
  ];
  if (pages.isEmpty) pages.add(<T>[]);
  final contents = <Widget>[
    if (summary != null) summary,
    for (final p in pages) tableBuilder(p, kExportWidth - 48 - 2),
  ];

  final date = DateFormat('dd/MM/yyyy HH:mm', 'es').format(DateTime.now());
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final files = <XFile>[];
  final controller = ScreenshotController();

  for (var i = 0; i < contents.length; i++) {
    if (!context.mounted) return;
    final bytes = await controller.captureFromLongWidget(
      Theme(
        data: AppTheme.dark,
        child: Directionality(
          textDirection: TextDirection.ltr,
          // Sin escalado de texto del sistema: la imagen sale igual en todos los móviles.
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.noScaling),
            child: Material(
              color: AppColors.background,
              child: _ExportPage(
                heading: heading,
                page: i + 1,
                pageCount: contents.length,
                legend: legend,
                date: date,
                table: contents[i],
              ),
            ),
          ),
        ),
      ),
      context: context,
      pixelRatio: kExportPixelRatio,
      delay: const Duration(milliseconds: 120),
      constraints: const BoxConstraints(minWidth: kExportWidth, maxWidth: kExportWidth),
    );
    final suffix = contents.length == 1 ? '' : '_${i + 1}de${contents.length}';
    final file = File('${dir.path}/${fileBase}_$stamp$suffix.png');
    await file.writeAsBytes(bytes, flush: true);
    files.add(XFile(file.path, mimeType: 'image/png'));
  }

  await SharePlus.instance.share(ShareParams(files: files, text: shareText));
}

class _ExportPage extends StatelessWidget {
  const _ExportPage({
    required this.heading,
    required this.page,
    required this.pageCount,
    required this.legend,
    required this.date,
    required this.table,
  });

  final String heading;
  final int page;
  final int pageCount;
  final String legend;
  final String date;
  final Widget table;

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 13, color: AppColors.textPrimary);
    return Container(
      width: kExportWidth,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
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
              Image.asset(BrandAssets.logo,
                  width: 80, height: 80, filterQuality: FilterQuality.high),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandTitle(fontSize: 30),
                    const SizedBox(height: 4),
                    Text(
                      heading,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: AppColors.neonBright,
                        shadows: AppColors.textGlow(blur: 6),
                      ),
                    ),
                  ],
                ),
              ),
              if (pageCount > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.neon),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$page / $pageCount',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.neon)),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: table,
          ),
          const SizedBox(height: 12),
          Text(legend, style: small),
          const SizedBox(height: 4),
          Text('Actualizado $date',
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

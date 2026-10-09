import 'dart:io';
import 'dart:math' show sqrt;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../export/export_models.dart';
import '../theme.dart';
import 'brand.dart';

/// Ancho lógico de una columna de tabla en las imágenes exportadas.
const kExportWidth = 800.0;

/// Ancho útil de la tabla dentro de la imagen (márgenes de 24 y borde de 2).
const kExportContentWidth = kExportWidth - 48 - 2;

/// Estilo de tabla para exportar: letra más grande y colores más claros.
const kExportFontSize = 17.0;
const kExportRowPadding = 10.0;

/// Alto aproximado de cabecera (logo y título) + leyenda + márgenes.
const _kChromeHeight = 240.0;

/// Lado largo objetivo: un poco por debajo de 4096 px (máximo de WhatsApp HD)
/// por si el alto real supera la estimación; así WhatsApp no la vuelve a reducir.
const _kTargetLongSide = 3900.0;

/// Límite duro del lado largo: por encima de ~8000 px algunos móviles no
/// pueden crear la imagen (límite de textura de la GPU).
const _kMaxLongSide = 8000.0;

/// Densidad mínima para que el texto de tablas muy largas siga legible.
const _kMinPixelRatio = 1.5;

/// Calcula la densidad (pixelRatio) de la imagen. La tabla va SIEMPRE completa
/// en una sola columna, de arriba abajo.
double _pixelRatioFor(double width, double height) {
  final longSide = width > height ? width : height;
  var ratio = _kTargetLongSide / longSide;
  if (ratio < _kMinPixelRatio) ratio = _kMinPixelRatio;
  if (ratio > 3) ratio = 3;
  final byGpu = _kMaxLongSide / longSide;
  if (byGpu < ratio) ratio = byGpu;
  // Límite de memoria: ~24 millones de píxeles.
  final byMemory = sqrt(24e6 / (width * height));
  if (byMemory < ratio) ratio = byMemory;
  return ratio;
}

/// Exporta en una sola imagen PNG (bloque [ExportSpec.summary] y, si se pide,
/// la tabla COMPLETA en una sola columna) y la comparte como foto, ajustada al
/// máximo de WhatsApp HD.
Future<void> exportSingleImage<T>(BuildContext context, ExportSpec<T> spec) async {
  await precacheImage(const AssetImage(BrandAssets.logo), context);
  for (final img in spec.preload) {
    if (!context.mounted) return;
    await precacheImage(img, context, onError: (_, _) {});
  }
  if (!context.mounted) return;

  final contentWidth = spec.contentWidth ?? kExportContentWidth;
  final width = contentWidth + 48 + 4;
  final table = spec.tableBuilder;
  final height = _kChromeHeight +
      spec.summaryHeightEstimate +
      (table == null ? 0 : (spec.items.length + 1) * spec.rowHeightEstimate);

  final content = Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (spec.summary != null) spec.summary!,
      if (spec.summary != null && table != null) const SizedBox(height: 16),
      if (table != null) _TableFrame(child: table(spec.items, contentWidth)),
    ],
  );

  final bytes = await _capture(context, spec, content,
      width: width, pixelRatio: _pixelRatioFor(width, height));
  final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
  final name = '${spec.fileBase}_$stamp.png';
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'image/png', name: name)],
    text: spec.shareText,
  ));
}

Future<Uint8List> _capture<T>(
  BuildContext context,
  ExportSpec<T> spec,
  Widget content, {
  required double width,
  required double pixelRatio,
}) {
  final date = DateFormat('dd/MM/yyyy HH:mm', 'es').format(DateTime.now());
  return ScreenshotController().captureFromLongWidget(
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
              width: width,
              heading: spec.heading,
              legend: spec.legend,
              date: date,
              table: content,
            ),
          ),
        ),
      ),
    ),
    context: context,
    pixelRatio: pixelRatio,
    delay: const Duration(milliseconds: 120),
    constraints: BoxConstraints(minWidth: width, maxWidth: width),
  );
}

class _ExportPage extends StatelessWidget {
  const _ExportPage({
    required this.width,
    required this.heading,
    required this.legend,
    required this.date,
    required this.table,
  });

  final double width;
  final String heading;
  final String legend;
  final String date;
  final Widget table;

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 13, color: AppColors.textPrimary);
    return Container(
      width: width,
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
            ],
          ),
          const SizedBox(height: 18),
          table,
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

class _TableFrame extends StatelessWidget {
  const _TableFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

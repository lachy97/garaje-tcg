import 'dart:io';
import 'dart:math' show sqrt;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Separación entre columnas cuando la tabla se reparte en varias.
const _kColumnGap = 16.0;

/// Alto aproximado de cabecera (logo y título) + leyenda + márgenes.
const _kChromeHeight = 240.0;

/// Cómo se va a compartir la imagen.
enum ImageExportMode {
  /// Como ARCHIVO (documento): WhatsApp no la toca. Máxima resolución.
  file,

  /// Como FOTO: se ve directamente en el chat. Se ajusta a 4096 px por el lado
  /// largo, el máximo de WhatsApp en calidad HD.
  hdPhoto,
}

/// Distribución elegida para la imagen: columnas de tabla y densidad.
class _Layout {
  const _Layout(this.columns, this.width, this.pixelRatio);

  final int columns;
  final double width;
  final double pixelRatio;
}

/// Reparte las filas en 1, 2 o 3 columnas para que la imagen quede lo más
/// "cuadrada" posible (así se aprovecha mejor el límite de píxeles y el texto
/// sale más grande) y calcula la densidad.
_Layout _layoutFor(ExportSpec<Object?> spec, ImageExportMode mode) {
  final maxLongSide = mode == ImageExportMode.file ? 6000.0 : 4096.0;
  // Límite de memoria: ~24 millones de píxeles.
  const maxPixels = 24e6;
  final n = spec.items.length;
  _Layout? best;
  for (var c = 1; c <= 3; c++) {
    if (c > 1 && n <= 12 * (c - 1)) break; // tablas cortas: una sola columna
    final rowsPerColumn = (n / c).ceil();
    final width = c * kExportContentWidth + (c - 1) * _kColumnGap + 48 + 4;
    final height = _kChromeHeight +
        spec.summaryHeightEstimate +
        (rowsPerColumn + 1) * spec.rowHeightEstimate;
    final longSide = width > height ? width : height;
    var ratio = maxLongSide / longSide;
    final byMemory = sqrt(maxPixels / (width * height));
    if (byMemory < ratio) ratio = byMemory;
    if (ratio > 3) ratio = 3;
    if (best == null || ratio > best.pixelRatio + 0.05) {
      best = _Layout(c, width, ratio);
    }
  }
  return best!;
}

/// Exporta TODA la tabla en una sola imagen PNG y la comparte.
///
/// - [ImageExportMode.file]: se comparte como documento mediante un
///   FileProvider propio que anuncia el archivo como genérico; WhatsApp no la
///   comprime y al abrirla se puede hacer zoom.
/// - [ImageExportMode.hdPhoto]: se comparte como foto, ya ajustada al máximo
///   de WhatsApp HD (4096 px), con la tabla repartida en columnas si es larga.
Future<void> exportSingleImage<T>(
    BuildContext context, ExportSpec<T> spec, ImageExportMode mode) async {
  await precacheImage(const AssetImage(BrandAssets.logo), context);
  for (final img in spec.preload) {
    if (!context.mounted) return;
    await precacheImage(img, context, onError: (_, _) {});
  }
  if (!context.mounted) return;

  final layout = _layoutFor(spec, mode);
  final perColumn = (spec.items.length / layout.columns).ceil();
  final chunks = <List<T>>[
    for (var i = 0; i < spec.items.length; i += perColumn)
      spec.items.sublist(i, (i + perColumn).clamp(0, spec.items.length)),
  ];
  if (chunks.isEmpty) chunks.add(<T>[]);

  final content = Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (spec.summary != null) ...[
        spec.summary!,
        const SizedBox(height: 16),
      ],
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < chunks.length; i++) ...[
            if (i > 0) const SizedBox(width: _kColumnGap),
            SizedBox(
              width: kExportContentWidth,
              child: _TableFrame(child: spec.tableBuilder(chunks[i], kExportContentWidth)),
            ),
          ],
        ],
      ),
    ],
  );

  final bytes = await _capture(context, spec, content,
      width: layout.width, pixelRatio: layout.pixelRatio);
  final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
  final name = '${spec.fileBase}_$stamp.png';

  if (mode == ImageExportMode.file && Platform.isAndroid) {
    // Carpeta que comparte DocumentShareProvider (res/xml/document_share_paths.xml).
    final dir = Directory('${(await getTemporaryDirectory()).path}/share_docs');
    if (await dir.exists()) await dir.delete(recursive: true); // borra las anteriores
    await dir.create(recursive: true);
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    try {
      await _channel.invokeMethod<void>('shareAsDocument', {
        'path': file.path,
        'text': spec.shareText,
      });
      return;
    } on PlatformException {
      // Si falla, se comparte de la forma normal.
    }
  }

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'image/png', name: name)],
    text: spec.shareText,
  ));
}

const _channel = MethodChannel('garage_tcg/share');

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

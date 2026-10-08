import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../export/export_models.dart';
import '../theme.dart';
import 'brand.dart';

/// Ancho lógico de las imágenes exportadas.
const kExportWidth = 800.0;

/// Ancho útil de la tabla dentro de la imagen (márgenes de 24 y borde de 2).
const kExportContentWidth = kExportWidth - 48 - 2;

/// Densidad de la captura: 800 × 2.4 = 1920 px de ancho.
const kExportPixelRatio = 2.4;

/// Filas por imagen. Con 12 filas cada imagen mide ~1920×2000 px: WhatsApp
/// apenas la reduce y el texto se lee nítido. Una sola imagen larga con
/// todas las filas se reduce muchísimo al enviarla y se vuelve ilegible.
const kExportRowsPerPage = 12;

/// Estilo de tabla para exportar: letra más grande y colores más claros.
const kExportFontSize = 17.0;
const kExportRowPadding = 10.0;

/// Máximo de píxeles de alto de la imagen única. Muchos móviles no pueden
/// crear imágenes más altas (límite de la GPU); si la tabla es muy larga se
/// baja la densidad en vez de cortar.
const _kMaxSinglePixels = 8000.0;

/// Exporta en varias imágenes PNG (12 filas cada una) y abre el menú de
/// compartir. Se ven directamente en el chat de WhatsApp.
Future<void> exportPagedImages<T>(BuildContext context, ExportSpec<T> spec,
    {int rowsPerPage = kExportRowsPerPage}) async {
  await precacheImage(const AssetImage(BrandAssets.logo), context);
  if (!context.mounted) return;

  final items = spec.items;
  final pages = <List<T>>[
    for (var i = 0; i < items.length; i += rowsPerPage)
      items.sublist(i, (i + rowsPerPage).clamp(0, items.length)),
  ];
  if (pages.isEmpty) pages.add(<T>[]);
  final contents = <Widget>[
    if (spec.summary != null) spec.summary!,
    for (final p in pages) spec.tableBuilder(p, kExportContentWidth),
  ];

  final files = <XFile>[];
  for (var i = 0; i < contents.length; i++) {
    if (!context.mounted) return;
    final bytes = await _capture(
      context,
      spec,
      contents[i],
      page: i + 1,
      pageCount: contents.length,
      pixelRatio: kExportPixelRatio,
    );
    final suffix = contents.length == 1 ? '' : '_${i + 1}de${contents.length}';
    files.add(await _saveTemp(bytes, '${spec.fileBase}$suffix.png', 'image/png'));
  }
  await SharePlus.instance.share(ShareParams(files: files, text: spec.shareText));
}

/// Exporta TODO en una sola imagen de alta resolución.
///
/// WhatsApp decide por la extensión del archivo: un .png SIEMPRE lo manda como
/// foto y lo comprime, aunque se comparta como tipo genérico. Por eso la
/// imagen se entrega dentro de un PDF de una sola página del tamaño exacto de
/// la imagen: WhatsApp lo envía como documento, sin tocarlo, y al abrirlo se
/// ve la imagen completa y nítida al hacer zoom.
Future<void> exportSingleImage<T>(BuildContext context, ExportSpec<T> spec) async {
  await precacheImage(const AssetImage(BrandAssets.logo), context);
  if (!context.mounted) return;

  // Densidad según el alto estimado: hasta 3× (2400 px de ancho) en tablas
  // normales, menos en las muy largas para no pasar el límite del móvil.
  final estimated = 220 +
      spec.summaryHeightEstimate +
      (spec.items.length + 1) * spec.rowHeightEstimate;
  final ratio = (_kMaxSinglePixels / estimated).clamp(1.2, 3.0);

  final content = Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (spec.summary != null) ...[
        spec.summary!,
        const SizedBox(height: 16),
      ],
      _TableFrame(child: spec.tableBuilder(spec.items, kExportContentWidth)),
    ],
  );
  final bytes = await _capture(context, spec, content,
      page: 1, pageCount: 1, pixelRatio: ratio, framed: false);
  final pdf = await _imageAsPdf(bytes, ratio, spec.heading);
  final file = await _saveTemp(pdf, '${spec.fileBase}_HD.pdf', 'application/pdf');
  await SharePlus.instance.share(ShareParams(
    files: [file],
    text: '${spec.shareText}\n(Imagen en alta calidad: ábrela y haz zoom)',
  ));
}

/// PDF de una página con la imagen a tamaño completo, sin márgenes.
/// El PNG se decodifica con el decodificador nativo del teléfono (rápido) y se
/// guarda sin pérdida en el PDF.
Future<Uint8List> _imageAsPdf(Uint8List png, double pixelRatio, String title) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final w = image.width, h = image.height;
  image.dispose();
  codec.dispose();
  final doc = pw.Document(title: title, author: 'Garage TCG', creator: 'Garage TCG')
    ..addPage(pw.Page(
      pageFormat: PdfPageFormat(w / pixelRatio, h / pixelRatio),
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Image(
        pw.RawImage(bytes: rgba!.buffer.asUint8List(), width: w, height: h),
        fit: pw.BoxFit.fill,
      ),
    ));
  return doc.save();
}

Future<Uint8List> _capture<T>(
  BuildContext context,
  ExportSpec<T> spec,
  Widget content, {
  required int page,
  required int pageCount,
  required double pixelRatio,
  bool framed = true,
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
              heading: spec.heading,
              page: page,
              pageCount: pageCount,
              legend: spec.legend,
              date: date,
              table: content,
              framed: framed,
            ),
          ),
        ),
      ),
    ),
    context: context,
    pixelRatio: pixelRatio,
    delay: const Duration(milliseconds: 120),
    constraints: const BoxConstraints(minWidth: kExportWidth, maxWidth: kExportWidth),
  );
}

/// Guarda en la carpeta temporal con un nombre único y devuelve el archivo
/// listo para compartir.
Future<XFile> _saveTemp(Uint8List bytes, String name, String mime) async {
  final dir = await getTemporaryDirectory();
  final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
  final dot = name.lastIndexOf('.');
  final fileName = '${name.substring(0, dot)}_$stamp${name.substring(dot)}';
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return XFile(file.path, mimeType: mime, name: fileName);
}

class _ExportPage extends StatelessWidget {
  const _ExportPage({
    required this.heading,
    required this.page,
    required this.pageCount,
    required this.legend,
    required this.date,
    required this.table,
    this.framed = true,
  });

  /// Tabla dentro de un recuadro. En la imagen única con tier list el
  /// contenido ya trae sus propios recuadros.
  final bool framed;
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
          if (framed) _TableFrame(child: table) else table,
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

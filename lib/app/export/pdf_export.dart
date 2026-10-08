import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' show DateFormat;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../theme.dart';
import '../widgets/brand.dart';
import 'export_models.dart';

PdfColor _c(int argb) => PdfColor.fromInt(argb);

final _bg = _c(AppColors.background.toARGB32());
final _surface = _c(AppColors.surface.toARGB32());
final _neon = _c(AppColors.neon.toARGB32());
final _neonBright = _c(AppColors.neonBright.toARGB32());
final _text = _c(AppColors.textPrimary.toARGB32());
final _textSecondary = _c(AppColors.textSecondary.toARGB32());
final _moss = _c(AppColors.moss.toARGB32());
final _outline = _c(AppColors.outlineVariant.toARGB32());
final _highlight = _c(AppColors.forest.toARGB32());

/// Genera un PDF (A4, con los colores de la app) y abre el menú de compartir.
/// El texto es vectorial: se lee nítido a cualquier zoom y se puede imprimir.
/// Las tablas largas continúan en páginas nuevas repitiendo la cabecera.
Future<void> exportPdf<T>(ExportSpec<T> spec) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/pdf/Inter-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/pdf/Inter-Bold.ttf'));
  final logo = pw.MemoryImage(
      (await rootBundle.load(BrandAssets.logo)).buffer.asUint8List());
  final date = DateFormat('dd/MM/yyyy HH:mm', 'es').format(DateTime.now());
  final table = spec.pdfTable();

  final doc = pw.Document(title: spec.heading, author: 'Garage TCG', creator: 'Garage TCG');
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 20),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        buildBackground: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: _bg),
        ),
      ),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 14),
              child: pw.Row(children: [
                pw.Image(logo, width: 54, height: 54),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('GARAGE TCG',
                          style: pw.TextStyle(
                              font: bold, fontSize: 20, letterSpacing: 3, color: _neon)),
                      pw.SizedBox(height: 2),
                      pw.Text(spec.heading,
                          style: pw.TextStyle(font: bold, fontSize: 12, color: _neonBright)),
                    ],
                  ),
                ),
              ]),
            )
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text('GARAGE TCG · ${spec.heading}',
                  style: pw.TextStyle(fontSize: 8, color: _textSecondary)),
            ),
      footer: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(children: [
          pw.Expanded(
            child: pw.Text('Actualizado $date',
                style: pw.TextStyle(fontSize: 7.5, color: _textSecondary)),
          ),
          pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 7.5, color: _textSecondary)),
        ]),
      ),
      build: (ctx) => [
        if (spec.pdfGroups != null) ...[
          for (final g in spec.pdfGroups!) _group(g),
          pw.SizedBox(height: 14),
        ],
        _table(table),
        pw.SizedBox(height: 10),
        pw.Text(spec.legend, style: pw.TextStyle(fontSize: 7.5, color: _text)),
      ],
    ),
  );

  final bytes = await doc.save();
  final dir = await getTemporaryDirectory();
  final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
  final name = '${spec.fileBase}_$stamp.pdf';
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'application/pdf', name: name)],
    text: spec.shareText,
  ));
}

pw.Widget _group(ExportGroupData g) {
  final color = _c(g.color);
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 5),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: color, width: 0.8),
      borderRadius: pw.BorderRadius.circular(5),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 34,
          height: 30,
          alignment: pw.Alignment.center,
          color: color,
          child: pw.Text(g.label,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _bg)),
        ),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: g.items.isEmpty
                ? pw.Text('-', style: pw.TextStyle(fontSize: 9, color: _textSecondary))
                : pw.Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      for (final item in g.items)
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                          decoration: pw.BoxDecoration(
                            color: _surface,
                            border: pw.Border.all(color: _moss, width: 0.5),
                            borderRadius: pw.BorderRadius.circular(3),
                          ),
                          child: pw.Text(item,
                              style: pw.TextStyle(
                                  fontSize: 9, fontWeight: pw.FontWeight.bold, color: _text)),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    ),
  );
}

pw.TextAlign _align(ExportAlign a) => switch (a) {
      ExportAlign.start => pw.TextAlign.left,
      ExportAlign.center => pw.TextAlign.center,
      ExportAlign.end => pw.TextAlign.right,
    };

pw.Widget _table(ExportTableData t) {
  pw.Widget cell(String text, ExportAlign align, pw.TextStyle style, {PdfColor? background}) {
    final child = pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4.5),
      child: pw.Text(text, textAlign: _align(align), style: style, maxLines: 2),
    );
    return background == null ? child : pw.Container(color: background, child: child);
  }

  final head = pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: _neon);
  return pw.Table(
    columnWidths: {
      for (var i = 0; i < t.columns.length; i++) i: pw.FlexColumnWidth(t.columns[i].width),
    },
    border: pw.TableBorder(
      top: pw.BorderSide(color: _moss, width: 0.8),
      bottom: pw.BorderSide(color: _moss, width: 0.8),
      horizontalInside: pw.BorderSide(color: _outline, width: 0.5),
    ),
    children: [
      pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(color: _surface),
        children: [
          for (final c in t.columns) cell(c.label.toUpperCase(), c.align, head),
        ],
      ),
      for (final r in t.rows)
        pw.TableRow(
          decoration: r.background != null
              ? pw.BoxDecoration(color: _c(r.background!))
              : r.highlight
                  ? pw.BoxDecoration(color: _highlight)
                  : null,
          verticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            for (var i = 0; i < t.columns.length; i++)
              if (i < r.cells.length)
                cell(
                  r.cells[i].text,
                  t.columns[i].align,
                  pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: r.cells[i].bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: r.cells[i].color == null
                        ? (r.cells[i].background != null ? _bg : _text)
                        : _c(r.cells[i].color!),
                  ),
                  background:
                      r.cells[i].background == null ? null : _c(r.cells[i].background!),
                )
              else
                pw.SizedBox(),
          ],
        ),
    ],
  );
}

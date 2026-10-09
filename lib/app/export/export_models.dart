import 'package:flutter/widgets.dart';

/// Formato elegido al exportar una tabla.
enum ExportFormat {
  /// Una sola imagen PNG a máxima resolución enviada como ARCHIVO (documento):
  /// WhatsApp no la comprime y al abrirla se hace zoom sin perder nitidez.
  imageFile,

  /// Una sola imagen enviada como FOTO, ajustada al máximo de WhatsApp HD
  /// (4096 px) y con la tabla repartida en columnas si es larga.
  imageHd,
}

/// Columna de una tabla para el PDF. [width] es relativo (se reparte el ancho).
class ExportColumnData {
  const ExportColumnData(this.label, this.width, {this.align = ExportAlign.center});

  final String label;
  final double width;
  final ExportAlign align;
}

enum ExportAlign { start, center, end }

class ExportCellData {
  const ExportCellData(this.text, {this.color, this.bold = false, this.background});

  final String text;

  /// Color ARGB (p. ej. `AppColors.neon.toARGB32()`); null = texto normal.
  final int? color;
  final bool bold;

  /// Fondo de la celda (p. ej. el tier).
  final int? background;
}

class ExportRowData {
  const ExportRowData(this.cells, {this.highlight = false, this.background});

  /// Fondo propio de la fila (ARGB). Tiene prioridad sobre [highlight].
  final int? background;

  final List<ExportCellData> cells;
  final bool highlight;
}

class ExportTableData {
  const ExportTableData({required this.columns, required this.rows});

  final List<ExportColumnData> columns;
  final List<ExportRowData> rows;
}

/// Grupo con etiqueta (p. ej. una fila "S" de la tier list) para el PDF.
class ExportGroupData {
  const ExportGroupData({required this.label, required this.color, required this.items});

  final String label;
  final int color;
  final List<String> items;
}

/// Todo lo necesario para exportar una tabla en cualquiera de los formatos.
class ExportSpec<T> {
  const ExportSpec({
    required this.heading,
    required this.items,
    this.tableBuilder,
    required this.pdfTable,
    required this.legend,
    required this.fileBase,
    required this.shareText,
    this.summary,
    this.pdfGroups,
    this.rowHeightEstimate = 50,
    this.summaryHeightEstimate = 0,
    this.preload = const [],
    this.contentWidth,
    this.page,
  });

  /// Página completa ya diseñada (p. ej. el póster de la tier list). Si no es
  /// null se exporta tal cual, sin la cabecera estándar ni la tabla; su ancho
  /// es [contentWidth] y su alto aproximado [summaryHeightEstimate].
  final Widget? page;

  /// Ancho útil (px lógicos) del contenido; null = ancho de tabla estándar.
  final double? contentWidth;

  /// Imágenes que deben estar cargadas antes de "fotografiar" la tabla
  /// (p. ej. las de los mazos).
  final List<ImageProvider> preload;

  /// Título bajo la marca, p. ej. "RANKING · TEMPORADA T4 2026".
  final String heading;
  final List<T> items;

  /// Tabla (widget) de las filas dadas, para las imágenes. null = sin tabla
  /// (p. ej. la tier list, que solo exporta [summary]).
  final Widget Function(List<T> items, double width)? tableBuilder;

  /// Bloque previo opcional en las imágenes (p. ej. la tier list).
  final Widget? summary;

  /// Tabla completa para el PDF.
  final ExportTableData Function() pdfTable;

  /// Grupos previos opcionales en el PDF (p. ej. la tier list).
  final List<ExportGroupData>? pdfGroups;

  final String legend;
  final String fileBase;
  final String shareText;

  /// Alturas aproximadas (px lógicos) para elegir la resolución de la imagen única.
  final double rowHeightEstimate;
  final double summaryHeightEstimate;
}

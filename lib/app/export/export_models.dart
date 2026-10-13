import 'package:flutter/widgets.dart';

/// Todo lo necesario para exportar una tabla como imagen.
class ExportSpec<T> {
  const ExportSpec({
    required this.heading,
    required this.items,
    this.tableBuilder,
    required this.legend,
    required this.fileBase,
    required this.shareText,
    this.summary,
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

  final String legend;
  final String fileBase;
  final String shareText;

  /// Alturas aproximadas (px lógicos) para elegir la resolución de la imagen única.
  final double rowHeightEstimate;
  final double summaryHeightEstimate;
}

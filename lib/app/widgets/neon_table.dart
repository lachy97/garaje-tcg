import 'package:flutter/material.dart';

import '../theme.dart';

/// Columna de [NeonTable]. [flex] = se estira para ocupar el ancho sobrante
/// (normalmente la del nombre); [width] es su ancho mínimo.
class NeonColumn {
  const NeonColumn(this.label, {required this.width, this.align = TextAlign.center, this.flex = false});

  final String label;
  final double width;
  final TextAlign align;
  final bool flex;
}

class NeonTableRow {
  const NeonTableRow({
    required this.cells,
    this.highlight = false,
    this.dim = false,
    this.footer,
    this.accent,
    this.onTap,
  });

  /// Al tocar la fila (p. ej. abrir la ficha). null = no se puede tocar.
  final VoidCallback? onTap;

  /// Color propio de la fila (p. ej. puestos del ranking): fondo suave de ese
  /// color y una franja a la izquierda. Tiene prioridad sobre [highlight].
  final Color? accent;

  final List<Widget> cells;

  /// Fila destacada (p. ej. 1º del ranking o dentro del corte).
  final bool highlight;

  /// Fila atenuada (p. ej. jugador retirado).
  final bool dim;

  /// Widget a todo el ancho debajo de la fila (p. ej. línea de corte del Top).
  final Widget? footer;
}

/// Tabla con el estilo de la app: cabecera en mayúsculas, filas separadas por
/// líneas finas. Si no cabe en pantalla se desplaza horizontalmente.
///
/// Al desplazarse, las primeras columnas (hasta la del nombre) se quedan
/// fijas a la izquierda, como en una hoja de cálculo.
///
/// Los anchos crecen con el tamaño de letra del teléfono para que nada se corte.
///
/// Con [fixedWidth] se dibuja con ese ancho exacto (para exportar a imagen).
class NeonTable extends StatefulWidget {
  const NeonTable({
    super.key,
    required this.columns,
    required this.rows,
    this.fixedWidth,
    this.horizontalPadding = 12,
    this.fontSize = 14,
    this.rowPadding = 8,
    this.headerColor,
    this.frozenColumns,
    this.background,
  });

  final List<NeonColumn> columns;
  final List<NeonTableRow> rows;
  final double? fixedWidth;
  final double horizontalPadding;

  /// Tamaño base del texto de las filas (la cabecera usa el 80 %).
  /// En las imágenes exportadas se usa más grande para que se lea bien.
  final double fontSize;
  final double rowPadding;
  /// Color de la cabecera (por defecto, el texto secundario del tema).
  final Color? headerColor;

  /// Columnas que se quedan fijas al desplazar en horizontal. null = hasta la
  /// columna que se estira (la del nombre), si es una de las tres primeras.
  final int? frozenColumns;

  /// Color de fondo sobre el que está la tabla (para las columnas fijas).
  /// Por defecto, el fondo de la app.
  final Color? background;

  @override
  State<NeonTable> createState() => _NeonTableState();
}

class _NeonTableState extends State<NeonTable> {
  /// Ancho de la franja de color de la izquierda (todas las filas la llevan).
  static const _stripe = 4.0;

  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<NeonColumn> get columns => widget.columns;
  double get horizontalPadding => widget.horizontalPadding;
  double get fontSize => widget.fontSize;
  double get rowPadding => widget.rowPadding;

  /// Factor por el tamaño de letra del teléfono (1 en imágenes exportadas).
  double _scale = 1;

  double _colWidth(NeonColumn c) => c.width * _scale;

  double get _minWidth =>
      columns.fold<double>(0, (s, c) => s + _colWidth(c)) + horizontalPadding * 2 + _stripe;

  int get _frozenCount {
    if (widget.frozenColumns != null) return widget.frozenColumns!.clamp(0, columns.length);
    final i = columns.indexWhere((c) => c.flex);
    return i >= 0 && i <= 2 ? i + 1 : 0;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fixedWidth != null) {
      _scale = 1;
      return _table(widget.fixedWidth!, scrolling: false);
    }
    _scale = (MediaQuery.textScalerOf(context).scale(fontSize) / fontSize).clamp(1.0, 2.0);
    return LayoutBuilder(builder: (context, constraints) {
      final available = constraints.maxWidth;
      if (available >= _minWidth) return _table(available, scrolling: false);
      return Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: _table(_minWidth, scrolling: true, viewport: available),
        ),
      );
    });
  }

  static Widget _tappable(VoidCallback? onTap, Widget child) =>
      onTap == null ? child : InkWell(onTap: onTap, child: child);

  /// Mueve [child] lo mismo que se desplaza la tabla: así se queda quieto.
  Widget _pinned(Widget child) => ListenableBuilder(
        listenable: _scroll,
        builder: (context, child) {
          final dx = _scroll.hasClients ? _scroll.offset : 0.0;
          return Transform.translate(
            offset: Offset(dx, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Sombra a la derecha solo cuando hay algo debajo.
                boxShadow: dx > 1
                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(2, 0))]
                    : null,
              ),
              child: child,
            ),
          );
        },
        child: child,
      );

  Widget _table(double width, {required bool scrolling, double viewport = 0}) {
    final extra = (width - _minWidth).clamp(0.0, double.infinity);
    final flexCount = columns.where((c) => c.flex).length;
    double widthOf(NeonColumn c) =>
        _colWidth(c) + (c.flex && flexCount > 0 ? extra / flexCount : 0);

    // Columnas fijas: solo si hay desplazamiento y dejan sitio al resto.
    var frozen = scrolling ? _frozenCount : 0;
    double frozenWidth() =>
        _stripe + horizontalPadding + [for (var i = 0; i < frozen; i++) widthOf(columns[i])].fold(0.0, (a, b) => a + b);
    if (frozen > 0 && frozenWidth() > viewport * 0.6) frozen = 0;
    final base = widget.background ?? AppColors.background;

    Alignment alignOf(TextAlign a) => switch (a) {
          TextAlign.start || TextAlign.left => Alignment.centerLeft,
          TextAlign.end || TextAlign.right => Alignment.centerRight,
          _ => Alignment.center,
        };

    final headStyle = TextStyle(
      fontSize: fontSize * 0.8,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: widget.headerColor ?? AppColors.textSecondary,
    );

    Widget headCell(NeonColumn c) => SizedBox(
          width: widthOf(c),
          child: Text(c.label.toUpperCase(), textAlign: c.align, style: headStyle),
        );

    Widget bodyCell(NeonTableRow r, int i) => SizedBox(
          width: widthOf(columns[i]),
          child: Align(
            alignment: alignOf(columns[i].align),
            child: i < r.cells.length ? r.cells[i] : const SizedBox(),
          ),
        );

    Color? rowTint(NeonTableRow r) => r.accent != null
        ? r.accent!.withValues(alpha: 0.13)
        : r.highlight
            ? AppColors.forest.withValues(alpha: 0.35)
            : null;

    TextStyle rowStyle(NeonTableRow r) => TextStyle(
          fontSize: fontSize,
          color: r.dim ? AppColors.textDisabled : AppColors.textPrimary,
        );

    /// Fila completa; con columnas fijas, encima va una copia opaca de ellas
    /// que no se desplaza.
    Widget withFrozen(Widget row, Widget Function() frozenPart) {
      if (frozen == 0) return row;
      return Stack(
        children: [
          row,
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: frozenWidth(),
            child: _pinned(frozenPart()),
          ),
        ],
      );
    }

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          withFrozen(
            Container(
              padding: EdgeInsets.fromLTRB(
                  horizontalPadding + _stripe, rowPadding, horizontalPadding, rowPadding),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.moss, width: 1)),
              ),
              child: Row(children: [for (final c in columns) headCell(c)]),
            ),
            () => Container(
              padding: EdgeInsets.only(left: horizontalPadding + _stripe),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: base,
                border: Border(bottom: BorderSide(color: AppColors.moss, width: 1)),
              ),
              child: Row(children: [for (var i = 0; i < frozen; i++) headCell(columns[i])]),
            ),
          ),
          for (final r in widget.rows) ...[
            _tappable(r.onTap, MergeSemantics(
              child: withFrozen(
                Container(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: rowPadding),
                  decoration: BoxDecoration(
                    color: rowTint(r),
                    border: Border(
                      // Todas las filas llevan la franja (transparente si no hay
                      // color) para que las columnas queden alineadas.
                      left: BorderSide(color: r.accent ?? Colors.transparent, width: _stripe),
                      bottom: BorderSide(color: AppColors.outlineVariant, width: 0.6),
                    ),
                  ),
                  child: DefaultTextStyle.merge(
                    style: rowStyle(r),
                    child: Row(children: [
                      for (var i = 0; i < columns.length; i++) bodyCell(r, i),
                    ]),
                  ),
                ),
                () => ExcludeSemantics(
                  child: Container(
                    padding: EdgeInsets.only(left: horizontalPadding),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      // Fondo opaco: el color de la fila sobre el fondo de la tabla.
                      color: rowTint(r) == null ? base : Color.alphaBlend(rowTint(r)!, base),
                      border: Border(
                        left: BorderSide(color: r.accent ?? Colors.transparent, width: _stripe),
                        bottom: BorderSide(color: AppColors.outlineVariant, width: 0.6),
                      ),
                    ),
                    child: DefaultTextStyle.merge(
                      style: rowStyle(r),
                      child: Row(children: [for (var i = 0; i < frozen; i++) bodyCell(r, i)]),
                    ),
                  ),
                ),
              ),
            )),
            if (r.footer != null) r.footer!,
          ],
        ],
      ),
    );
  }
}

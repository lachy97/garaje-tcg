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
  const NeonTableRow({required this.cells, this.highlight = false, this.dim = false, this.footer});

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
/// Con [fixedWidth] se dibuja con ese ancho exacto (para exportar a imagen).
class NeonTable extends StatelessWidget {
  const NeonTable({
    super.key,
    required this.columns,
    required this.rows,
    this.fixedWidth,
    this.horizontalPadding = 12,
  });

  final List<NeonColumn> columns;
  final List<NeonTableRow> rows;
  final double? fixedWidth;
  final double horizontalPadding;

  double get _minWidth =>
      columns.fold<double>(0, (s, c) => s + c.width) + horizontalPadding * 2;

  @override
  Widget build(BuildContext context) {
    if (fixedWidth != null) return _table(fixedWidth!);
    return LayoutBuilder(builder: (context, constraints) {
      final available = constraints.maxWidth;
      if (available >= _minWidth) return _table(available);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _table(_minWidth),
      );
    });
  }

  Widget _table(double width) {
    final extra = (width - _minWidth).clamp(0.0, double.infinity);
    final flexCount = columns.where((c) => c.flex).length;
    double widthOf(NeonColumn c) =>
        c.width + (c.flex && flexCount > 0 ? extra / flexCount : 0);

    Alignment alignOf(TextAlign a) => switch (a) {
          TextAlign.start || TextAlign.left => Alignment.centerLeft,
          TextAlign.end || TextAlign.right => Alignment.centerRight,
          _ => Alignment.center,
        };

    const headStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: AppColors.textSecondary,
    );

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.moss, width: 1)),
            ),
            child: Row(children: [
              for (final c in columns)
                SizedBox(
                  width: widthOf(c),
                  child: Text(c.label.toUpperCase(), textAlign: c.align, style: headStyle),
                ),
            ]),
          ),
          for (final r in rows) ...[
            Container(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
              decoration: BoxDecoration(
                color: r.highlight ? AppColors.forest.withValues(alpha: 0.35) : null,
                border: const Border(
                    bottom: BorderSide(color: AppColors.outlineVariant, width: 0.6)),
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 14,
                  color: r.dim ? AppColors.textDisabled : AppColors.textPrimary,
                ),
                child: Row(children: [
                  for (var i = 0; i < columns.length; i++)
                    SizedBox(
                      width: widthOf(columns[i]),
                      child: Align(
                        alignment: alignOf(columns[i].align),
                        child: i < r.cells.length ? r.cells[i] : const SizedBox(),
                      ),
                    ),
                ]),
              ),
            ),
            if (r.footer != null) r.footer!,
          ],
        ],
      ),
    );
  }
}

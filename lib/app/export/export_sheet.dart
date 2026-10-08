import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/table_export.dart';
import 'export_models.dart';
import 'pdf_export.dart';

/// Pregunta cómo exportar (imagen única, PDF o imágenes para el chat) y lo hace.
/// Devuelve false si el usuario cancela.
Future<bool> runExport<T>(BuildContext context, ExportSpec<T> spec) async {
  final format = await showModalBottomSheet<ExportFormat>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('¿Cómo quieres exportar?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          _option(ctx, ExportFormat.singleImage, Icons.photo_size_select_large,
              'Imagen única (alta calidad)',
              'Toda la tabla en una sola imagen. Se envía como documento para que '
                  'WhatsApp no la comprima: al abrirla se hace zoom y se lee nítida.'),
          _option(ctx, ExportFormat.pdf, Icons.picture_as_pdf_outlined, 'Documento PDF',
              'Texto nítido a cualquier zoom, varias páginas si hace falta. '
                  'Ideal para guardar o imprimir.'),
          _option(ctx, ExportFormat.pagedImages, Icons.collections_outlined,
              'Imágenes para el chat',
              'Una imagen cada $kExportRowsPerPage filas; se ven directamente en '
                  'el chat de WhatsApp.'),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (format == null || !context.mounted) return false;

  try {
    switch (format) {
      case ExportFormat.singleImage:
        await exportSingleImage(context, spec);
      case ExportFormat.pdf:
        await exportPdf(spec);
      case ExportFormat.pagedImages:
        await exportPagedImages(context, spec);
    }
  } catch (e) {
    if (context.mounted) showMessage(context, 'No se pudo exportar: $e', error: true);
  }
  return true;
}

Widget _option(BuildContext ctx, ExportFormat f, IconData icon, String title, String subtitle) {
  return ListTile(
    leading: Icon(icon, color: AppColors.neon, size: 30),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(subtitle,
        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
    isThreeLine: true,
    onTap: () => Navigator.pop(ctx, f),
  );
}

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/table_export.dart';
import 'export_models.dart';

/// Pregunta cómo exportar (imagen como archivo o imagen HD para el chat) y lo hace.
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
          _option(ctx, ExportFormat.imageFile, Icons.insert_drive_file_outlined,
              'Imagen como archivo (máxima calidad)',
              'Toda la tabla en una sola imagen. Se envía como documento: WhatsApp '
                  'no la comprime y al abrirla se hace zoom y se lee perfecta.'),
          _option(ctx, ExportFormat.imageHd, Icons.hd_outlined, 'Imagen HD para el chat',
              'Una sola imagen que se ve directamente en el chat. Al enviarla en '
                  'WhatsApp toca "HD" para que se vea nítida al hacer zoom.'),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (format == null || !context.mounted) return false;

  try {
    await exportSingleImage(
      context,
      spec,
      format == ExportFormat.imageFile ? ImageExportMode.file : ImageExportMode.hdPhoto,
    );
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

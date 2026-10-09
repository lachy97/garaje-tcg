import 'package:flutter/material.dart';

import '../widgets/common.dart';
import '../widgets/table_export.dart';
import 'export_models.dart';

/// Exporta como UNA imagen en la máxima calidad que admite WhatsApp en HD
/// (≈4096 px por el lado largo). La tabla sale completa en una sola columna.
/// Abre el menú de compartir.
///
/// Al enviarla por WhatsApp hay que tocar "HD" para que no la reduzca.
Future<bool> runExport<T>(BuildContext context, ExportSpec<T> spec) async {
  try {
    await exportSingleImage(context, spec);
    return true;
  } catch (e) {
    if (context.mounted) showMessage(context, 'No se pudo exportar: $e', error: true);
    return false;
  }
}

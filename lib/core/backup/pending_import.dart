import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Importación pendiente: la BD nueva se guarda primero en un archivo aparte
/// y se coloca en su sitio cuando la BD está cerrada (en el momento si se
/// puede cerrar, o al abrir la app la próxima vez). Así una importación nunca
/// deja la app colgada ni a medias.
class PendingImport {
  const PendingImport._();

  static Future<(File data, File meta)> _files() async {
    final dir = await getApplicationSupportDirectory();
    return (
      File('${dir.path}/pending_import.sqlite'),
      File('${dir.path}/pending_import.json'),
    );
  }

  /// Guarda la BD a importar y la ruta del archivo que debe reemplazar.
  /// El .json se escribe al final: sin él, la importación no se aplica.
  static Future<void> save(Uint8List sqlite, String targetPath) async {
    final (data, meta) = await _files();
    await data.writeAsBytes(sqlite, flush: true);
    await meta.writeAsString(jsonEncode({'path': targetPath}), flush: true);
  }

  /// Si hay una importación pendiente la aplica (la BD debe estar cerrada).
  /// Devuelve true si se aplicó.
  static Future<bool> applyIfAny() async {
    final (data, meta) = await _files();
    if (!await meta.exists()) return false;
    try {
      if (!await data.exists()) return false;
      final path = (jsonDecode(await meta.readAsString()) as Map)['path'] as String;
      final bytes = await data.readAsBytes();
      // Escribe al lado y renombra: el cambio de archivo es atómico.
      final tmp = File('$path.importing');
      await tmp.writeAsBytes(bytes, flush: true);
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final f = File('$path$suffix');
        if (await f.exists()) await f.delete();
      }
      await tmp.rename(path);
      return true;
    } finally {
      if (await meta.exists()) await meta.delete();
      if (await data.exists()) await data.delete();
    }
  }
}

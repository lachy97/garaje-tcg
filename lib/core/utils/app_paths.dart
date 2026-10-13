import 'package:path_provider/path_provider.dart';

/// Rutas de la app. Las imágenes propias se guardan RELATIVAS a la carpeta de
/// documentos ("docs:deck_images/x.jpg"): la ruta absoluta cambia al
/// reinstalar o restaurar la app, y una ruta relativa sigue sirviendo (y es
/// la que se podrá sincronizar entre teléfonos).
class AppPaths {
  const AppPaths._();

  static const docsPrefix = 'docs:';

  static String? _documents;

  /// Carpeta de documentos de la app (se llama una vez al arrancar).
  static Future<void> init() async {
    _documents ??= (await getApplicationDocumentsDirectory()).path;
  }

  static String? get documents => _documents;

  /// Ruta guardable para un archivo dentro de la carpeta de documentos.
  static String relative(String subPath) => '$docsPrefix$subPath';

  /// Ruta real de una ruta guardada: relativa ("docs:…"), o absoluta de una
  /// versión anterior (si ya no existe, se busca el archivo por su nombre en
  /// la carpeta actual de imágenes).
  static String? resolve(String stored, {String folder = 'deck_images'}) {
    final docs = _documents;
    if (stored.startsWith(docsPrefix)) {
      return docs == null ? null : '$docs/${stored.substring(docsPrefix.length)}';
    }
    final i = stored.lastIndexOf('/$folder/');
    if (i >= 0 && docs != null) return '$docs${stored.substring(i)}';
    return stored;
  }
}

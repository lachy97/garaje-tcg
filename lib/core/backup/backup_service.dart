import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/app_database.dart';
import '../db/database_provider.dart';
import 'backup_codec.dart';
import 'pending_import.dart';

/// Copia lista para importar (ya validada).
class BackupPreview {
  const BackupPreview(this.header, this.sqlite);

  final BackupHeader header;
  final Uint8List sqlite;
}

/// Copia automática guardada dentro de la app antes de cada importación.
class AutoBackup {
  const AutoBackup(this.file, this.date);

  final File file;
  final DateTime date;
}

/// Exportar / importar la base de datos completa.
class BackupService {
  BackupService(this._ref);

  final Ref _ref;
  static const _keepAuto = 5;

  AppDatabase get _db => _ref.read(databaseProvider);

  // ───────────────────── Exportar ─────────────────────

  /// Copia coherente de la BD (VACUUM INTO) empaquetada y sellada.
  Future<Uint8List> createBackup() async {
    final db = _db;
    final tmpDir = await getTemporaryDirectory();
    final tmp = File('${tmpDir.path}/snapshot_${DateTime.now().millisecondsSinceEpoch}.sqlite');
    if (await tmp.exists()) await tmp.delete();
    await db.customStatement("VACUUM INTO '${tmp.path.replaceAll("'", "''")}'");
    final sqlite = await tmp.readAsBytes();
    await tmp.delete();

    final counts = await db.customSelect(
      'SELECT '
      '(SELECT COUNT(*) FROM players WHERE deleted_at IS NULL) AS p, '
      '(SELECT COUNT(*) FROM tournaments WHERE deleted_at IS NULL) AS t, '
      '(SELECT COUNT(*) FROM decks WHERE deleted_at IS NULL) AS d',
    ).getSingle();

    return BackupCodec.encode(
      BackupHeader(
        exportedAt: DateTime.now(),
        schemaVersion: db.schemaVersion,
        players: counts.read<int>('p'),
        tournaments: counts.read<int>('t'),
        decks: counts.read<int>('d'),
      ),
      sqlite,
    );
  }

  String _fileName() =>
      'garage_tcg_datos_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.${BackupCodec.extension}';

  /// Abre el menú de compartir (WhatsApp, Drive, Bluetooth…).
  Future<void> share() async {
    final bytes = await createBackup();
    final dir = await getTemporaryDirectory();
    final name = _fileName();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/octet-stream', name: name)],
      text: 'Copia de seguridad de Garage TCG. Para cargarla: Ajustes → Importar base de datos.',
    ));
  }

  /// Guarda el archivo en una carpeta del teléfono elegida por el usuario.
  /// Devuelve false si se canceló.
  Future<bool> saveToDevice() async {
    final bytes = await createBackup();
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar copia de seguridad',
      fileName: _fileName(),
      bytes: bytes,
    );
    return path != null;
  }

  // ───────────────────── Importar ─────────────────────

  /// Elige un archivo y lo valida. null si se canceló. Lanza [BackupException].
  Future<BackupPreview?> pickAndInspect() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Elegir copia de Garage TCG (.gtcg)',
      type: FileType.any,
      withData: true,
    );
    final picked = result?.files.singleOrNull;
    if (picked == null) return null;
    final bytes = picked.bytes ??
        (picked.path == null ? null : await File(picked.path!).readAsBytes());
    if (bytes == null) throw const BackupException('No se pudo leer el archivo.');
    return inspect(bytes);
  }

  BackupPreview inspect(Uint8List bytes) {
    final (header, sqlite) = BackupCodec.decode(bytes);
    final version = BackupCodec.sqliteUserVersion(sqlite);
    if (version < 1) {
      throw const BackupException('El archivo no contiene datos de Garage TCG.');
    }
    if (version > _db.schemaVersion) {
      throw const BackupException(
          'La copia viene de una versión más nueva de la app. Actualiza Garage TCG '
          'en este teléfono y vuelve a intentarlo.');
    }
    return BackupPreview(header, sqlite);
  }

  /// Reemplaza TODOS los datos por los de la copia. Antes guarda una copia
  /// automática de los datos actuales dentro de la app.
  ///
  /// La copia se deja como importación pendiente y se coloca en su sitio con
  /// la BD cerrada. Devuelve true si ya quedó aplicada (hay que reiniciar la
  /// app); false si la BD no se pudo cerrar a
  /// tiempo: se aplicará al volver a abrir la app.
  Future<bool> restore(BackupPreview preview) async {
    final current = await createBackup();
    await _saveAuto(current);

    final db = _db;
    final path = await db.filePath();
    await PendingImport.save(preview.sqlite, path);
    try {
      await db.closeOnce().timeout(const Duration(seconds: 8));
    } on Object {
      return false;
    }
    return PendingImport.applyIfAny();
  }

  // ───────────────────── Copias automáticas ─────────────────────

  Future<Directory> _autoDir() async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/copias_automaticas');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _saveAuto(Uint8List bytes) async {
    final dir = await _autoDir();
    final name = 'antes_de_importar_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}'
        '.${BackupCodec.extension}';
    await File('${dir.path}/$name').writeAsBytes(bytes, flush: true);
    final all = await autoBackups();
    for (final old in all.skip(_keepAuto)) {
      await old.file.delete();
    }
  }

  /// Copias automáticas, la más reciente primero.
  Future<List<AutoBackup>> autoBackups() async {
    final dir = await _autoDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.${BackupCodec.extension}'))
        .toList();
    final list = [for (final f in files) AutoBackup(f, f.lastModifiedSync())]
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  Future<BackupPreview> inspectAuto(AutoBackup auto) async =>
      inspect(await auto.file.readAsBytes());
}

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(ref));

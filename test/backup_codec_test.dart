import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/backup/backup_codec.dart';

Uint8List _fakeSqlite({int userVersion = 4}) {
  final b = Uint8List(4096);
  b.setAll(0, 'SQLite format 3'.codeUnits);
  b[15] = 0;
  ByteData.sublistView(b).setUint32(60, userVersion);
  for (var i = 100; i < b.length; i++) {
    b[i] = i % 251;
  }
  return b;
}

void main() {
  final header = BackupHeader(
    exportedAt: DateTime(2026, 10, 8, 20, 30),
    schemaVersion: 4,
    players: 12,
    tournaments: 3,
    decks: 9,
  );

  test('Exportar e importar conserva los datos', () {
    final sqlite = _fakeSqlite();
    final file = BackupCodec.encode(header, sqlite);
    final (h, s) = BackupCodec.decode(file);
    expect(s, sqlite);
    expect(h.players, 12);
    expect(h.tournaments, 3);
    expect(h.decks, 9);
    expect(h.schemaVersion, 4);
    expect(h.exportedAt, DateTime(2026, 10, 8, 20, 30));
    expect(BackupCodec.sqliteUserVersion(s), 4);
  });

  test('Rechaza archivos dañados o que no son de la app', () {
    final file = BackupCodec.encode(header, _fakeSqlite());
    final damaged = Uint8List.fromList(file)..[file.length ~/ 2] ^= 0xFF;
    expect(() => BackupCodec.decode(damaged), throwsA(isA<BackupException>()));

    final cut = Uint8List.sublistView(file, 0, file.length - 10);
    expect(() => BackupCodec.decode(cut), throwsA(isA<BackupException>()));

    expect(() => BackupCodec.decode(Uint8List.fromList('hola'.codeUnits)),
        throwsA(isA<BackupException>()));
    // Una BD SQLite "suelta" (no exportada por la app) no se acepta.
    expect(() => BackupCodec.decode(_fakeSqlite()), throwsA(isA<BackupException>()));
  });
}

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/core/db/app_database.dart';
import 'package:garaje_tcg/core/sync/sync_schema.dart';

/// La cola de sincronización se llena sola con los disparadores.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('insertar, cambiar y borrar dejan la fila en la cola', () async {
    final AppDatabase db;
    try {
      db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();
    } catch (e) {
      stderr.writeln('SQLite no disponible, prueba omitida: $e');
      return;
    }
    addTearDown(db.close);

    Future<List<String>> queued(String t) async => [
          for (final r in await db
              .customSelect("SELECT row_id FROM sync_outbox WHERE tbl = '$t'")
              .get())
            r.read<String>('row_id'),
        ];

    // El catálogo de mazos se siembra al abrir: ya está en la cola.
    expect((await queued('decks')).isNotEmpty, isTrue);

    await db.customStatement('DELETE FROM sync_outbox');
    final id = (await db.playersDao.create(nickname: 'Leo')).id;
    expect(await queued('players'), [id]);

    await db.customStatement('DELETE FROM sync_outbox');
    await db.customStatement("UPDATE players SET nickname = 'Leo B' WHERE id = ?", [id]);
    expect(await queued('players'), [id]);

    await db.customStatement('DELETE FROM sync_outbox');
    await db.customStatement('DELETE FROM players WHERE id = ?', [id]);
    expect(await queued('players'), [id]);

    // Subir todo: todas las filas de todas las tablas.
    await db.customStatement('DELETE FROM sync_outbox');
    await enqueueAllRows(db);
    final decks = await db.customSelect('SELECT COUNT(*) AS n FROM decks').getSingle();
    expect((await queued('decks')).length, decks.read<int>('n'));
  });
}

import 'package:drift/drift.dart';

/// Tablas de la app que se suben al servidor (mismo orden y nombres que
/// server/src/sync.js). Las fotos propias (jugadores, mazos) no se suben:
/// solo su ruta.
const kSyncTables = [
  'players',
  'decks',
  'seasons',
  'points_scale_entries',
  'tournaments',
  'tournament_players',
  'rounds',
  'matches',
  'season_results',
  'ranking_snapshots',
  'deck_snapshots',
  'penalties',
  'deck_lists',
];

/// Milisegundos actuales en SQL.
const _nowMs = "CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)";

/// Cola de cambios pendientes de subir + disparadores que la llenan solos al
/// insertar, cambiar o borrar cualquier fila. Así no hace falta tocar cada
/// pantalla ni cada consulta. Idempotente: se ejecuta en cada apertura.
Future<void> installSyncSchema(GeneratedDatabase db) async {
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS sync_outbox ('
    'tbl TEXT NOT NULL, row_id TEXT NOT NULL, changed_at INTEGER NOT NULL, '
    'PRIMARY KEY (tbl, row_id))',
  );
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS sync_state (k TEXT PRIMARY KEY, v TEXT)',
  );
  // Evento → fila que se anota (NEW al insertar/cambiar, OLD al borrar).
  const events = {'INSERT': 'NEW', 'UPDATE': 'NEW', 'DELETE': 'OLD'};
  for (final t in kSyncTables) {
    for (final e in events.entries) {
      final event = e.key;
      final row = e.value;
      final name = '${t}_${event.toLowerCase()}';
      // Versión anterior (usaba INSERT OR REPLACE, que falla cuando la
      // sentencia que dispara es un "upsert": manda su ON CONFLICT).
      await db.customStatement('DROP TRIGGER IF EXISTS sync_$name');
      // Borrar y volver a insertar: no depende de la resolución de conflictos.
      await db.customStatement(
        'CREATE TRIGGER IF NOT EXISTS sync2_$name '
        'AFTER $event ON $t BEGIN '
        "DELETE FROM sync_outbox WHERE tbl = '$t' AND row_id = $row.id; "
        "INSERT INTO sync_outbox (tbl, row_id, changed_at) VALUES ('$t', $row.id, $_nowMs); "
        'END',
      );
    }
  }
}

/// Pone en la cola TODAS las filas (primera subida de un teléfono, o para
/// volver a subir todo). No toca lo que ya estaba en cola.
Future<void> enqueueAllRows(GeneratedDatabase db) async {
  for (final t in kSyncTables) {
    await db.customStatement(
      'INSERT OR IGNORE INTO sync_outbox (tbl, row_id, changed_at) '
      "SELECT '$t', id, $_nowMs FROM $t",
    );
  }
}

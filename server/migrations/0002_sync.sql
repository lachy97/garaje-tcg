-- Fase 2 · copia de los datos de los teléfonos de los organizadores.
-- Cada fila de la app (jugadores, mazos, torneos…) se guarda tal cual en JSON.

CREATE TABLE IF NOT EXISTS sync_rows (
  community_id TEXT NOT NULL,
  tbl          TEXT NOT NULL,             -- tabla de la app (players, matches…)
  id           TEXT NOT NULL,             -- id de la fila (UUID v7)
  data         TEXT,                      -- fila en JSON (null si se borró)
  deleted      INTEGER NOT NULL DEFAULT 0,
  changed_at   INTEGER NOT NULL,          -- ms del cambio en el teléfono
  seq          INTEGER NOT NULL,          -- orden de llegada (para bajar cambios)
  owner_id     TEXT NOT NULL,             -- cuenta que la subió primero
  updated_by   TEXT NOT NULL,
  received_at  INTEGER NOT NULL,
  PRIMARY KEY (community_id, tbl, id)
);
CREATE INDEX IF NOT EXISTS idx_sync_seq ON sync_rows (community_id, seq);

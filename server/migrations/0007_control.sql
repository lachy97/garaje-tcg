-- Qué teléfono lleva cada torneo. Solo ese teléfono puede subir cambios del
-- torneo; otro teléfono de la misma cuenta (o el administrador) puede "tomar
-- el control" si el primero se queda sin batería o sin datos.
CREATE TABLE IF NOT EXISTS tournament_control (
  community_id  TEXT NOT NULL,
  tournament_id TEXT PRIMARY KEY,
  account_id    TEXT NOT NULL,
  device_id     TEXT NOT NULL,
  device_name   TEXT,
  heartbeat_at  INTEGER NOT NULL,
  took_at       INTEGER NOT NULL
);

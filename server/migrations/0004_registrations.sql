-- Inscripción desde la app: solicitudes de los jugadores a torneos con la
-- inscripción en línea abierta. Una por cuenta y torneo.
-- Estados: pending (espera al organizador) · accepted (aceptada; el teléfono
-- del organizador la inscribirá al sincronizar) · registered (ya inscrito) ·
-- rejected · cancel_requested (el jugador se borra; el organizador la quita) ·
-- cancelled.
CREATE TABLE IF NOT EXISTS registrations (
  id            TEXT PRIMARY KEY,
  community_id  TEXT NOT NULL,
  tournament_id TEXT NOT NULL,
  account_id    TEXT NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  player_id     TEXT,
  deck_name     TEXT,
  status        TEXT NOT NULL,
  reason        TEXT,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  UNIQUE (tournament_id, account_id)
);
CREATE INDEX IF NOT EXISTS idx_reg_tournament ON registrations (community_id, tournament_id);
CREATE INDEX IF NOT EXISTS idx_reg_account ON registrations (account_id);

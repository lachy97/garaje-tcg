-- Jueces por torneo y acciones de juez desde su móvil (resultado, tiempo
-- extra por mesa, penalizaciones) y check-in de los jugadores.
CREATE TABLE IF NOT EXISTS tournament_staff (
  community_id  TEXT NOT NULL,
  tournament_id TEXT NOT NULL,
  account_id    TEXT NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  created_at    INTEGER NOT NULL,
  PRIMARY KEY (tournament_id, account_id)
);
CREATE INDEX IF NOT EXISTS idx_staff_account ON tournament_staff (account_id);
-- play_actions: kind también 'checkin' | 'jresult' | 'extension' | 'penalty'
ALTER TABLE play_actions ADD COLUMN extra INTEGER;        -- minutos de extensión
ALTER TABLE play_actions ADD COLUMN target_player TEXT;   -- a quién (penalización)
ALTER TABLE play_actions ADD COLUMN penalty TEXT;         -- warning | gameLoss | matchLoss | disqualification
ALTER TABLE play_actions ADD COLUMN double_loss INTEGER;  -- resultado de juez: doble derrota

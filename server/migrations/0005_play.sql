-- Durante el torneo, desde el teléfono del jugador: reportar el resultado de
-- su mesa (lo confirma el rival), llamar al juez y retirarse (drop).
-- kind: report | judge | drop
-- status: report → proposed · confirmed · disputed · done (aplicado) · cancelled
--         judge / drop → open · done · cancelled
CREATE TABLE IF NOT EXISTS play_actions (
  id            TEXT PRIMARY KEY,
  community_id  TEXT NOT NULL,
  tournament_id TEXT NOT NULL,
  match_id      TEXT,
  account_id    TEXT NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  player_id     TEXT NOT NULL,
  kind          TEXT NOT NULL,
  g1            INTEGER,
  gd            INTEGER,
  g2            INTEGER,
  other_g1      INTEGER,   -- lo que dice el rival si no coincide
  other_gd      INTEGER,
  other_g2      INTEGER,
  note          TEXT,
  status        TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_play_tournament ON play_actions (community_id, tournament_id, status);
CREATE INDEX IF NOT EXISTS idx_play_match ON play_actions (match_id, kind);

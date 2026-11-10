-- Fase 3 · columnas para filtrar lo que baja a cada teléfono.
ALTER TABLE sync_rows ADD COLUMN tournament_id TEXT;
ALTER TABLE sync_rows ADD COLUMN player_id TEXT;
UPDATE sync_rows SET
  tournament_id = CASE WHEN tbl = 'tournaments' THEN id ELSE json_extract(data, '$.tournament_id') END,
  player_id = json_extract(data, '$.player_id')
WHERE data IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sync_tournament ON sync_rows (community_id, tournament_id);
CREATE INDEX IF NOT EXISTS idx_sync_player ON sync_rows (community_id, tbl, player_id);

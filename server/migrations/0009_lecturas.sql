-- 1.14 · Menos filas leídas (el plan gratis de D1 admite 5 millones al día).
-- Cada consulta frecuente lee solo lo que necesita en vez de recorrer un
-- torneo entero o todos los torneos.

-- Filas de un torneo por orden de llegada: al completar un torneo que se
-- acaba de volver visible solo se leen las anteriores a lo que el teléfono
-- ya tiene. Sustituye a idx_sync_tournament (mismo prefijo).
CREATE INDEX IF NOT EXISTS idx_sync_tournament_seq ON sync_rows (community_id, tournament_id, seq);
DROP INDEX IF EXISTS idx_sync_tournament;

-- Filas de una tabla de un torneo (inscritos de un torneo, para contar
-- plazas) sin leer el resto del torneo ni los inscritos de todos los torneos.
CREATE INDEX IF NOT EXISTS idx_sync_tbl_tournament ON sync_rows (community_id, tbl, tournament_id);

-- Solicitudes por torneo (las consultas no filtran por comunidad).
CREATE INDEX IF NOT EXISTS idx_reg_tournament_status ON registrations (tournament_id, status);

-- Avisos de la mesa: los del jugador y los reportes de su rival.
CREATE INDEX IF NOT EXISTS idx_play_account ON play_actions (tournament_id, account_id);
CREATE INDEX IF NOT EXISTS idx_play_target ON play_actions (tournament_id, target_player);

-- Reportes ya hechos: a quién afectan (el rival), para no buscarlo cada vez.
UPDATE play_actions SET target_player = (
  SELECT CASE WHEN json_extract(m.data, '$.player1_id') = play_actions.player_id
              THEN json_extract(m.data, '$.player2_id') ELSE json_extract(m.data, '$.player1_id') END
    FROM sync_rows m
   WHERE m.community_id = play_actions.community_id AND m.tbl = 'matches' AND m.id = play_actions.match_id)
WHERE kind = 'report' AND target_player IS NULL AND match_id IS NOT NULL;

-- Torneos por estado (inscripciones abiertas) sin recorrer todos.
CREATE INDEX IF NOT EXISTS idx_sync_status ON sync_rows (community_id, tbl, json_extract(data, '$.status'));

-- Estadísticas para que D1 elija bien los índices.
PRAGMA optimize;

-- 1.18 · Arregla las fichas y listas de mazo guardadas por el servidor 1.15–1.17
-- con las fechas como número (la app las guarda como texto ISO 8601 y, al
-- leerlas, fallaba: "Invalid date format 1794820567Z"). Se pasan a texto y
-- se les da un seq nuevo para que los teléfonos las vuelvan a bajar.
UPDATE sync_rows SET
  data = json_set(data,
    '$.created_at', CASE WHEN json_type(data, '$.created_at') = 'integer'
                         THEN strftime('%Y-%m-%dT%H:%M:%fZ', json_extract(data, '$.created_at'), 'unixepoch')
                         ELSE json_extract(data, '$.created_at') END,
    '$.updated_at', CASE WHEN json_type(data, '$.updated_at') = 'integer'
                         THEN strftime('%Y-%m-%dT%H:%M:%fZ', json_extract(data, '$.updated_at'), 'unixepoch')
                         ELSE json_extract(data, '$.updated_at') END),
  -- Mayor que todos los actuales y distinto para cada fila.
  seq = (SELECT MAX(seq) FROM sync_rows) + rowid + 1
WHERE tbl IN ('players', 'deck_lists')
  AND data IS NOT NULL
  AND (json_type(data, '$.created_at') = 'integer' OR json_type(data, '$.updated_at') = 'integer');

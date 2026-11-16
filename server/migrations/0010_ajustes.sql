-- 1.17 · Ajustes del servidor que cambia el administrador desde la app.
-- min_app_build: compilación mínima de la app Android (las anteriores no
-- pueden usar el servidor hasta actualizar).
CREATE TABLE IF NOT EXISTS app_settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

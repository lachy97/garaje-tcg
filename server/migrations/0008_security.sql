-- Límites por dirección IP (intentos de inicio de sesión, registros,
-- códigos, check-in). Se borran solos al pasar la ventana de tiempo.
CREATE TABLE IF NOT EXISTS rate_log (
  key TEXT NOT NULL,
  at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rate_log ON rate_log (key, at);

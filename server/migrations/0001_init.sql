-- Garage TCG · servidor de cuentas (Cloudflare D1, SQLite)
-- Fechas: milisegundos desde 1970 (enteros) salvo created_at/updated_at (ISO).

CREATE TABLE IF NOT EXISTS accounts (
  id           TEXT PRIMARY KEY,
  username     TEXT NOT NULL UNIQUE,          -- minúsculas
  email        TEXT NOT NULL UNIQUE,          -- Gmail en minúsculas
  nickname     TEXT NOT NULL,
  phone        TEXT,
  role         TEXT NOT NULL DEFAULT 'player', -- admin | organizer | judge | player
  player_id    TEXT UNIQUE,                   -- ficha de jugador vinculada
  verified     INTEGER NOT NULL DEFAULT 0,
  community_id TEXT NOT NULL DEFAULT 'garaje',
  salt         TEXT NOT NULL,
  hash         TEXT NOT NULL,                 -- PBKDF2-SHA256
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);

-- Código vigente por correo y propósito ('verify' | 'reset'). Se guarda el hash.
CREATE TABLE IF NOT EXISTS codes (
  email      TEXT NOT NULL,
  purpose    TEXT NOT NULL,
  code_hash  TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  attempts   INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (email, purpose)
);

-- Códigos enviados (para el límite de 3 por hora y 60 s entre códigos).
CREATE TABLE IF NOT EXISTS code_log (
  email TEXT NOT NULL,
  at    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_code_log_email ON code_log (email, at);

-- Inicios de sesión fallidos (máximo 10 cada 15 minutos por usuario/Gmail).
CREATE TABLE IF NOT EXISTS login_fail (
  identifier TEXT NOT NULL,
  at         INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_login_fail ON login_fail (identifier, at);

-- Sesiones (30 días). Se guarda el hash del token, nunca el token.
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_account ON sessions (account_id);

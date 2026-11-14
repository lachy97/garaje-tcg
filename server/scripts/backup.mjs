// Copia de seguridad de la base de datos del servidor (D1) en este PC.
// Uso: npm run backup   (antes de cada torneo; con VPN)
//
// Guarda en server/backups/:
//   garage-tcg_AAAA-MM-DD_HHMM.sql       toda la base (estructura y datos)
//   garage-tcg_AAAA-MM-DD_HHMM.marca.txt marca de Time Travel de este momento
//                                         (para volver justo aquí, ver LEEME §17)
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DB = 'garage-tcg';
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dir = join(root, 'backups');
if (!existsSync(dir)) mkdirSync(dir, { recursive: true });

const d = new Date();
const p = (n) => String(n).padStart(2, '0');
const stamp = `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}`;
const base = `${DB}_${stamp}`;
const sql = join('backups', `${base}.sql`);

const run = (args, capture = false) =>
  spawnSync('npx', ['wrangler', ...args], {
    cwd: root,
    shell: true,
    encoding: 'utf8',
    stdio: capture ? ['inherit', 'pipe', 'inherit'] : 'inherit',
  });

console.log(`\nCopiando la base "${DB}" a server/${sql.replace(/\\/g, '/')} …\n`);
const exp = run(['d1', 'export', DB, '--remote', `--output=${sql}`]);
const file = join(root, sql);
if (exp.status !== 0 || !existsSync(file) || statSync(file).size === 0) {
  console.error('\n✗ No se pudo hacer la copia. ¿Tienes la VPN puesta y la sesión de wrangler abierta (npx wrangler login)?');
  process.exit(1);
}

// Marca de Time Travel: permite volver la base a este minuto exacto.
const info = run(['d1', 'time-travel', 'info', DB], true);
const out = info.stdout ?? '';
const bookmark = out.match(/[0-9a-f]{8}-[0-9a-f]{8}-[0-9a-f]{8}-[0-9a-f]{32}/i)?.[0] ?? null;
writeFileSync(
  join(dir, `${base}.marca.txt`),
  `Copia: ${d.toISOString()}\nBase: ${DB}\nMarca (bookmark): ${bookmark ?? '(no se pudo leer)'}\n\n${out}`,
);

const kb = Math.round(statSync(file).size / 1024);
console.log(`\n✓ Copia hecha: server/${sql.replace(/\\/g, '/')} (${kb} KB)`);
if (bookmark) console.log(`  Marca para volver a este momento: ${bookmark}`);
console.log('  Guárdala fuera de git (tiene correos y teléfonos). No la compartas.\n');

/// Dirección del servidor de cuentas (Cloudflare Workers), sin barra final.
/// Ej.: 'https://garage-tcg-api.tunombre.workers.dev'
///
/// Vacía = servidor simulado dentro del teléfono (como hasta ahora).
/// Se rellena tras publicar el servidor (server/LEEME.md, paso 6) y se
/// compila la app de nuevo.
const kServerUrl = 'https://garage-tcg-api.garagetcg.workers.dev';

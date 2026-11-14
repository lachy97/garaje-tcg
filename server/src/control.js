// Qué teléfono lleva cada torneo (ver migrations/0007_control.sql).
import { ApiError } from './auth.js';

const bad = (m) => new ApiError(400, m);
const NAME_MAX = 40;

export class ControlService {
  constructor(env, auth) {
    this.db = env.DB;
    this.auth = auth;
  }

  /** canTake: esta cuenta puede tomar el control (es su torneo o es admin). */
  static out(c, device, canTake = true) {
    return {
      tournamentId: c.tournament_id,
      mine: c.device_id === device,
      deviceName: c.device_name ?? null,
      nickname: c.nickname ?? null,
      lastSeen: new Date(c.heartbeat_at).toISOString(),
      canTake,
    };
  }

  /** Controles de varios torneos (por id). */
  async load(ids) {
    const map = new Map();
    for (let i = 0; i < ids.length; i += 90) {
      const chunk = ids.slice(i, i + 90);
      const q = await this.db
        .prepare(
          `SELECT c.*, a.nickname FROM tournament_control c LEFT JOIN accounts a ON a.id = c.account_id
            WHERE c.tournament_id IN (${chunk.map(() => '?').join(',')})`,
        )
        .bind(...chunk)
        .all();
      for (const c of q.results ?? []) map.set(c.tournament_id, c);
    }
    return map;
  }

  /** ¿Puede esta cuenta llevar el torneo? (quien lo subió o el administrador). */
  async owns(me, tournamentId) {
    if (me.role === 'admin') return true;
    const r = await this.db
      .prepare("SELECT owner_id FROM sync_rows WHERE community_id = ? AND tbl = 'tournaments' AND id = ?")
      .bind(me.community_id, tournamentId)
      .first();
    return !r || r.owner_id === me.id; // torneo nuevo aún sin subir: de quien lo cree
  }

  async claim(me, tournamentId, device, name) {
    const now = this.auth.now();
    await this.db
      .prepare(
        `INSERT INTO tournament_control (community_id, tournament_id, account_id, device_id, device_name, heartbeat_at, took_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (tournament_id) DO UPDATE SET account_id = excluded.account_id, device_id = excluded.device_id,
           device_name = excluded.device_name, heartbeat_at = excluded.heartbeat_at, took_at = excluded.took_at`,
      )
      .bind(me.community_id, tournamentId, me.id, device, name, now, now)
      .run();
  }

  /** Nombre del teléfono (la app lo manda codificado para URL: lleva tildes). */
  static clean(name) {
    if (typeof name !== 'string' || !name.trim()) return null;
    let n = name;
    try {
      n = decodeURIComponent(name);
    } catch {
      // se usa tal cual
    }
    return n.trim().slice(0, NAME_MAX) || null;
  }

  /**
   * Latido del teléfono que lleva torneos (en cada sincronización):
   * actualiza los suyos, reclama los que no tienen dueño y devuelve quién
   * lleva cada uno. body: { tournamentIds }
   */
  async beat(token, body, device, deviceName) {
    const me = await this.auth.authenticate(token);
    if (me.role !== 'admin' && me.role !== 'organizer') throw new ApiError(403, 'Solo organizadores.');
    if (!device) throw bad('Falta el identificador del teléfono.');
    const ids = (Array.isArray(body?.tournamentIds) ? body.tournamentIds : [])
      .filter((x) => typeof x === 'string' && x)
      .slice(0, 200);
    const name = ControlService.clean(deviceName);
    const current = await this.load(ids);
    const now = this.auth.now();
    const owned = new Map();
    for (const id of ids) owned.set(id, await this.owns(me, id));
    for (const id of ids) {
      const c = current.get(id);
      if (!c) {
        if (owned.get(id)) await this.claim(me, id, device, name);
      } else if (c.device_id === device) {
        await this.db
          .prepare('UPDATE tournament_control SET heartbeat_at = ?, device_name = COALESCE(?, device_name) WHERE tournament_id = ?')
          .bind(now, name, id)
          .run();
      }
    }
    const after = await this.load(ids);
    const controls = [];
    for (const id of ids) {
      const c = after.get(id);
      if (c) controls.push(ControlService.out(c, device, owned.get(id)));
      // Torneo de otro organizador (p. ej. es juez) que nadie reclamó: solo consulta.
      else controls.push({ tournamentId: id, mine: false, deviceName: null, nickname: null, lastSeen: null, canTake: false });
    }
    return { controls };
  }

  /** Tomar el control de un torneo desde este teléfono. */
  async take(token, body, device, deviceName) {
    const me = await this.auth.authenticate(token);
    if (!device) throw bad('Falta el identificador del teléfono.');
    const id = body?.tournamentId;
    if (typeof id !== 'string' || !id) throw bad('Falta el torneo.');
    if ((me.role !== 'admin' && me.role !== 'organizer') || !(await this.owns(me, id))) {
      throw new ApiError(403, 'Solo el organizador del torneo (o el administrador) puede tomar el control.');
    }
    await this.claim(me, id, device, ControlService.clean(deviceName));
    const c = (await this.load([id])).get(id);
    return { control: ControlService.out(c, device) };
  }
}

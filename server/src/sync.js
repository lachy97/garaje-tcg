// Fase 2: los teléfonos de los organizadores suben sus cambios y el servidor
// guarda la copia principal. Gana el cambio más reciente; una fila solo la
// puede cambiar quien la subió primero (o el administrador).
import { ApiError } from './auth.js';
import { ControlService } from './control.js';

/** Tablas de la app que se sincronizan. */
export const SYNC_TABLES = [
  'players',
  'decks',
  'seasons',
  'points_scale_entries',
  'tournaments',
  'tournament_players',
  'rounds',
  'matches',
  'season_results',
  'ranking_snapshots',
  'deck_snapshots',
  'penalties',
  'deck_lists',
];

export const MAX_PUSH_ROWS = 500;
const MAX_ROW_BYTES = 64 * 1024;
const MAX_PULL_ROWS = 1000;

const bad = (m) => new ApiError(400, m);

export class SyncService {
  constructor(env, auth) {
    this.db = env.DB;
    this.auth = auth;
  }

  /** Solo organizadores y el administrador suben datos (por ahora). */
  async writer(token) {
    const a = await this.auth.authenticate(token);
    if (a.role !== 'admin' && a.role !== 'organizer') {
      throw new ApiError(403, 'Solo los organizadores pueden subir datos de torneos.');
    }
    return a;
  }

  /**
   * body.rows: [{ t, id, changedAt, deleted?, data? }]
   * Respuesta: { accepted, stale, rejected: [{ t, id, reason }], seq }
   */
  /**
   * [device]: identificador del teléfono (cabecera X-Device-Id). Si un torneo
   * lo lleva otro teléfono (tournament_control), sus cambios se rechazan
   * ('not_controller'); el primero que sube un torneo sin dueño lo reclama.
   * Las versiones viejas de la app no envían el identificador: no se comprueba.
   */
  async push(token, body, device = '', deviceName = null) {
    const me = await this.writer(token);
    const rows = Array.isArray(body?.rows) ? body.rows : null;
    if (!rows) throw bad('Faltan las filas.');
    if (rows.length > MAX_PUSH_ROWS) throw bad(`Como máximo ${MAX_PUSH_ROWS} filas por envío.`);
    const isAdmin = me.role === 'admin';
    const community = me.community_id;
    const now = this.auth.now();

    // Validar y agrupar por tabla.
    const rejected = [];
    const valid = [];
    for (const r of rows) {
      const t = r?.t;
      const id = r?.id;
      const changedAt = Number(r?.changedAt);
      if (!SYNC_TABLES.includes(t) || typeof id !== 'string' || !id || id.length > 64 || !Number.isFinite(changedAt)) {
        rejected.push({ t, id, reason: 'invalid' });
        continue;
      }
      const deleted = Boolean(r.deleted);
      let data = null;
      if (!deleted) {
        if (!r.data || typeof r.data !== 'object' || Array.isArray(r.data)) {
          rejected.push({ t, id, reason: 'invalid' });
          continue;
        }
        data = JSON.stringify(r.data);
        if (data.length > MAX_ROW_BYTES) {
          rejected.push({ t, id, reason: 'too_large' });
          continue;
        }
      }
      // Para filtrar lo que baja a cada jugador (fase 3).
      const tournamentId = t === 'tournaments' ? id : (r.data?.tournament_id ?? null);
      const playerId = r.data?.player_id ?? null;
      valid.push({
        t,
        id,
        changedAt: Math.trunc(changedAt),
        deleted,
        data,
        tournamentId: deleted ? null : tournamentId,
        playerId: deleted ? null : playerId,
      });
    }

    // Borrados: el torneo se toma de la fila que ya hay en el servidor (para
    // comprobar qué teléfono lo lleva).
    const gone = valid.filter((r) => r.deleted && r.t !== 'tournaments');
    const goneBy = new Map();
    for (const r of gone) {
      if (!goneBy.has(r.t)) goneBy.set(r.t, []);
      goneBy.get(r.t).push(r);
    }
    for (const [t, list] of goneBy) {
      for (let i = 0; i < list.length; i += 90) {
        const chunk = list.slice(i, i + 90);
        const q = await this.db
          .prepare(`SELECT id, tournament_id FROM sync_rows WHERE community_id = ? AND tbl = ? AND id IN (${chunk.map(() => '?').join(',')})`)
          .bind(community, t, ...chunk.map((r) => r.id))
          .all();
        const tid = new Map((q.results ?? []).map((e) => [e.id, e.tournament_id]));
        for (const r of chunk) r.controlTid = tid.get(r.id) ?? null;
      }
    }
    for (const r of valid) if (r.t === 'tournaments') r.controlTid = r.id;
    const tidOf = (r) => r.tournamentId ?? r.controlTid ?? null;

    // Torneos que lleva otro teléfono: sus filas no se aceptan.
    const control = new ControlService({ DB: this.db }, this.auth);
    const tids = [...new Set(valid.map(tidOf).filter(Boolean).map(String))];
    const controls = device ? await control.load(tids) : new Map();
    const blocked = new Set();
    for (const [tid, c] of controls) if (c.device_id !== device) blocked.add(tid);
    if (blocked.size) {
      for (let i = valid.length - 1; i >= 0; i--) {
        const r = valid[i];
        if (tidOf(r) != null && blocked.has(String(tidOf(r)))) {
          rejected.push({ t: r.t, id: r.id, reason: 'not_controller' });
          valid.splice(i, 1);
        }
      }
    }

    // Filas que ya están en el servidor (dueño y fecha del último cambio).
    const existing = new Map();
    const byTable = new Map();
    for (const r of valid) {
      if (!byTable.has(r.t)) byTable.set(r.t, []);
      byTable.get(r.t).push(r.id);
    }
    for (const [t, ids] of byTable) {
      for (let i = 0; i < ids.length; i += 90) {
        const chunk = ids.slice(i, i + 90);
        const q = await this.db
          .prepare(
            `SELECT id, owner_id, changed_at FROM sync_rows WHERE community_id = ? AND tbl = ? AND id IN (${chunk
              .map(() => '?')
              .join(',')})`,
          )
          .bind(community, t, ...chunk)
          .all();
        for (const e of q.results ?? []) existing.set(`${t}|${e.id}`, e);
      }
    }

    // Filas nuevas de un torneo ajeno (el administrador lo siguió desde su
    // teléfono): quedan a nombre del dueño del torneo, para que pueda
    // retomarlo después.
    const tOwner = new Map();
    if (isAdmin && tids.length) {
      for (let i = 0; i < tids.length; i += 90) {
        const chunk = tids.slice(i, i + 90);
        const q = await this.db
          .prepare(`SELECT id, owner_id FROM sync_rows WHERE community_id = ? AND tbl = 'tournaments' AND id IN (${chunk.map(() => '?').join(',')})`)
          .bind(community, ...chunk)
          .all();
        for (const e of q.results ?? []) tOwner.set(e.id, e.owner_id);
      }
    }

    const stmts = [];
    let stale = 0;
    const seen = new Set();
    for (const r of valid) {
      const key = `${r.t}|${r.id}`;
      if (seen.has(key)) continue; // repetida en el mismo envío: vale la primera
      seen.add(key);
      const e = existing.get(key);
      if (e && e.owner_id !== me.id && !isAdmin) {
        rejected.push({ t: r.t, id: r.id, reason: 'not_owner' });
        continue;
      }
      if (e && e.changed_at > r.changedAt) {
        stale++; // en el servidor hay un cambio más reciente
        continue;
      }
      stmts.push(
        this.db
          .prepare(
            `INSERT INTO sync_rows (community_id, tbl, id, data, deleted, changed_at, seq, owner_id, updated_by, received_at,
                                   tournament_id, player_id)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6,
                     (SELECT COALESCE(MAX(seq), 0) + 1 FROM sync_rows WHERE community_id = ?1),
                     ?11, ?7, ?8, ?9, ?10)
             ON CONFLICT (community_id, tbl, id) DO UPDATE SET
               data = excluded.data, deleted = excluded.deleted, changed_at = excluded.changed_at,
               seq = excluded.seq, updated_by = excluded.updated_by, received_at = excluded.received_at,
               tournament_id = COALESCE(excluded.tournament_id, sync_rows.tournament_id),
               player_id = COALESCE(excluded.player_id, sync_rows.player_id)`,
          )
          .bind(community, r.t, r.id, r.data, r.deleted ? 1 : 0, r.changedAt, me.id, now,
                r.tournamentId != null ? String(r.tournamentId) : null,
                r.playerId != null ? String(r.playerId) : null,
                (r.tournamentId != null && tOwner.get(String(r.tournamentId))) || me.id),
      );
    }
    if (stmts.length) await this.db.batch(stmts);
    // Torneos sin teléfono a cargo: los reclama este (el primero que sube).
    if (device) {
      for (const tid of tids) {
        if (!controls.has(tid) && !blocked.has(tid) && (await control.owns(me, tid))) {
          await control.claim(me, tid, device, ControlService.clean(deviceName));
        }
      }
    }
    const last = await this.db
      .prepare('SELECT COALESCE(MAX(seq), 0) AS s FROM sync_rows WHERE community_id = ?')
      .bind(community)
      .first();
    return { accepted: stmts.length, stale, rejected, seq: last?.s ?? 0 };
  }

  /**
   * Cambios con seq > since que esta cuenta puede ver.
   * - Administrador: todo (para restaurar).
   * - Organizadores: sus torneos completos y los datos de los jugadores
   *   (también el teléfono); del resto, lo mismo que un jugador.
   * - Jugadores y jueces: catálogo, temporadas, ranking y tier list; los
   *   torneos terminados (para el ranking y las estadísticas) y aquellos en
   *   los que están inscritos; de los demás jugadores solo el apodo; sus
   *   propias penalizaciones. Sin cover pagado ni notas del organizador.
   * Cuando un torneo pasa a ser visible (termina o se inscribe) se envía
   * entero, aunque sus filas sean anteriores a [since].
   */
  async pull(token, params) {
    const me = await this.auth.authenticate(token);
    const since = Math.max(0, Math.trunc(Number(params.get('since') ?? 0)) || 0);
    const limit = Math.min(MAX_PULL_ROWS, Math.max(1, Math.trunc(Number(params.get('limit') ?? MAX_PULL_ROWS)) || MAX_PULL_ROWS));
    const community = me.community_id;
    const q = await this.db
      .prepare(
        'SELECT tbl, id, data, deleted, changed_at, seq, tournament_id, player_id, owner_id FROM sync_rows WHERE community_id = ? AND seq > ? ORDER BY seq LIMIT ?',
      )
      .bind(community, since, limit)
      .all();
    const delta = q.results ?? [];
    const more = delta.length === limit;
    const seq = delta.length ? delta[delta.length - 1].seq : since;
    const out = (r) => ({
      t: r.tbl,
      id: r.id,
      changedAt: r.changed_at,
      seq: r.seq,
      deleted: Boolean(r.deleted),
      data: r.data ? JSON.parse(r.data) : null,
    });
    if (me.role === 'admin') {
      return { rows: delta.map(out), more, seq, full: true };
    }
    const isOrganizer = me.role === 'organizer';
    if (!delta.length) return { rows: [], more: false, seq };

    const pid = me.player_id ?? null;
    // Torneos visibles: terminados, con inscripción desde la app abierta y
    // en los que está inscrito.
    const tq = await this.db
      .prepare("SELECT id, owner_id, json_extract(data, '$.status') AS status, json_extract(data, '$.online_registration') AS online, json_extract(data, '$.list_visibility') AS lists FROM sync_rows WHERE community_id = ? AND tbl = 'tournaments' AND deleted = 0")
      .bind(community)
      .all();
    const visible = new Set();
    // Torneos que lleva este organizador: le llegan completos (cover, notas,
    // penalizaciones de todos).
    const owned = new Set();
    // Listas de mazo: 'archetype' = no se envían (el mazo ya va en la
    // inscripción); 'after' = solo con el torneo terminado.
    const hiddenLists = new Set();
    for (const t of tq.results ?? []) {
      if (t.lists === 'archetype' || (t.lists === 'after' && t.status !== 'finished')) hiddenLists.add(t.id);
    }
    // Torneos donde es juez: todas las partidas y penalizaciones (sin cover,
    // notas ni teléfonos).
    const judged = new Set();
    const jq = await this.db
      .prepare('SELECT tournament_id FROM tournament_staff WHERE account_id = ?')
      .bind(me.id)
      .all();
    for (const j of jq.results ?? []) {
      judged.add(j.tournament_id);
      visible.add(j.tournament_id);
    }
    for (const t of tq.results ?? []) {
      if (isOrganizer && t.owner_id === me.id) {
        owned.add(t.id);
        visible.add(t.id);
      }
      // Terminados, y en inscripción con la inscripción desde la app abierta
      // (a los organizadores solo les bajan los suyos: los demás no los
      // pueden cambiar).
      if (!isOrganizer && (t.status === 'finished' || (t.status === 'draft' && Number(t.online) === 1))) {
        visible.add(t.id);
      }
    }
    if (pid && !isOrganizer) {
      const eq = await this.db
        .prepare("SELECT tournament_id FROM sync_rows WHERE community_id = ? AND tbl = 'tournament_players' AND player_id = ? AND deleted = 0")
        .bind(community, pid)
        .all();
      for (const e of eq.results ?? []) if (e.tournament_id) visible.add(e.tournament_id);
    }

    const ALWAYS = new Set(['decks', 'seasons', 'points_scale_entries', 'ranking_snapshots', 'deck_snapshots']);
    const PRIVATE_PLAYER = ['full_name', 'photo_path', 'notes', 'konami_id', 'phone'];
    // Datos solo para quien lleva el torneo (se quitan; la app pone el valor
    // por defecto): cover pagado y notas del organizador.
    const ORGANIZER_ONLY = { tournament_players: ['paid'], tournaments: ['notes', 'checkin_code'] };
    const rows = new Map();
    const add = (r) => {
      const key = `${r.tbl}|${r.id}`;
      if (rows.has(key)) return;
      if (r.deleted || !r.data) {
        rows.set(key, out(r)); // borrados: solo el id
        return;
      }
      if (ALWAYS.has(r.tbl)) {
        rows.set(key, out(r));
      } else if (r.tbl === 'players') {
        const o = out(r);
        // El organizador ve los datos de los jugadores (también el teléfono).
        if (r.id !== pid && !isOrganizer) for (const k of PRIVATE_PLAYER) if (k in o.data) o.data[k] = null;
        rows.set(key, o);
      } else if (r.tournament_id && visible.has(r.tournament_id)) {
        const mine = owned.has(r.tournament_id);
        if (r.tbl === 'penalties' && r.player_id !== pid && !mine && !judged.has(r.tournament_id)) return;
        if (r.tbl === 'deck_lists' && !mine && !judged.has(r.tournament_id) && hiddenLists.has(r.tournament_id)) return;
        const o = out(r);
        if (!mine) for (const k of ORGANIZER_ONLY[r.tbl] ?? []) delete o.data[k];
        rows.set(key, o);
      }
    };
    for (const r of delta) add(r);

    // Torneos que se volvieron visibles en este tramo: se envían completos.
    const expand = new Set();
    for (const r of delta) {
      if (r.deleted || !r.tournament_id || !visible.has(r.tournament_id)) continue;
      if (r.tbl === 'tournaments' || (r.tbl === 'tournament_players' && pid && r.player_id === pid)) {
        expand.add(r.tournament_id);
      }
    }
    for (const tid of expand) {
      const all = await this.db
        .prepare(
          'SELECT tbl, id, data, deleted, changed_at, seq, tournament_id, player_id FROM sync_rows WHERE community_id = ? AND tournament_id = ? AND deleted = 0 AND seq <= ?',
        )
        .bind(community, tid, seq)
        .all();
      for (const r of all.results ?? []) add(r);
    }
    return { rows: [...rows.values()], more, seq };
  }

  /** Cuántas filas hay en el servidor por tabla. */
  async status(token) {
    const me = await this.writer(token);
    const q = await this.db
      .prepare(
        'SELECT tbl, COUNT(*) AS n, SUM(deleted) AS d, MAX(received_at) AS last FROM sync_rows WHERE community_id = ? GROUP BY tbl',
      )
      .bind(me.community_id)
      .all();
    const tables = {};
    let last = 0;
    for (const r of q.results ?? []) {
      tables[r.tbl] = { rows: r.n - (r.d ?? 0), deleted: r.d ?? 0 };
      last = Math.max(last, r.last ?? 0);
    }
    return { tables, lastReceivedAt: last ? new Date(last).toISOString() : null };
  }
}

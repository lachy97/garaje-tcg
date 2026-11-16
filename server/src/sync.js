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
// Páginas pequeñas: cada página cuesta CPU (el plan gratis de Workers da
// 10 ms por petición; 1000 filas eran unos 15 ms, 250 unos 4 ms).
const MAX_PULL_ROWS = 250;

/** Margen entre crear y cambiar una inscripción para tratarla como nueva. */
const NEW_ENTRY_MS = 10 * 60 * 1000;

/** Torneo que ve cualquiera: terminado, o en inscripción desde la app. */
function publicTournament(t) {
  return Boolean(t) && (t.status === 'finished' || (t.status === 'draft' && Number(t.online) === 1));
}

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
      // Las fichas de jugador son de toda la comunidad: los organizadores
      // pueden corregir cualquiera (también la suya).
      const sharedPlayer = r.t === 'players' && me.role === 'organizer';
      if (e && e.owner_id !== me.id && !isAdmin && !sharedPlayer) {
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
    // Sin sesión (visitante): lo mismo que un jugador sin ficha: catálogo,
    // ranking, tier list y torneos terminados o con inscripción abierta.
    const me = token
      ? await this.auth.authenticate(token)
      : { id: null, role: 'visitor', player_id: null, community_id: 'garaje' };
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
    // La base se restauró desde una copia (su secuencia volvió atrás): el
    // teléfono va por delante y no recibiría nada. Se le hace bajar todo.
    if (!delta.length && since > 0) {
      const top = await this.db
        .prepare('SELECT COALESCE(MAX(seq), 0) AS s FROM sync_rows WHERE community_id = ?')
        .bind(community)
        .first();
      if (since > Number(top?.s ?? 0)) return { rows: [], more: true, seq: 0, reset: true };
    }
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
    // Solo los torneos que aparecen en este tramo (por clave): no se recorren
    // todos los torneos en cada sincronización de cada teléfono.
    const tids = [...new Set(delta.map((r) => r.tournament_id).filter(Boolean))];
    const tinfo = new Map();
    for (let i = 0; i < tids.length; i += 50) {
      const chunk = tids.slice(i, i + 50);
      const tq = await this.db
        .prepare(
          `SELECT id, owner_id, json_extract(data, '$.status') AS status, json_extract(data, '$.online_registration') AS online,
                  json_extract(data, '$.list_visibility') AS lists
             FROM sync_rows WHERE community_id = ? AND tbl = 'tournaments' AND id IN (${chunk.map(() => '?').join(',')}) AND deleted = 0`,
        )
        .bind(community, ...chunk)
        .all();
      for (const t of tq.results ?? []) tinfo.set(t.id, t);
    }
    // Torneos visibles: terminados, con inscripción desde la app abierta y
    // en los que está inscrito.
    const visible = new Set();
    // Torneos que lleva este organizador: le llegan completos (cover, notas,
    // penalizaciones de todos).
    const owned = new Set();
    // Listas de mazo: 'archetype' = no se envían (el mazo ya va en la
    // inscripción); 'after' = solo con el torneo terminado.
    const hiddenLists = new Set();
    for (const t of tinfo.values()) {
      // Hasta que termina el torneo no se sabe con qué juega cada uno (sí
      // el propio): tampoco las listas, aunque el torneo las enseñe.
      if (t.lists === 'archetype' || t.status !== 'finished') hiddenLists.add(t.id);
    }
    // Torneos donde es juez: todas las partidas y penalizaciones (sin cover,
    // notas ni teléfonos). Los jugadores y visitantes no arbitran.
    const judged = new Set();
    if (me.id && me.role !== 'player' && tids.length) {
      const jq = await this.db
        .prepare('SELECT tournament_id FROM tournament_staff WHERE account_id = ?')
        .bind(me.id)
        .all();
      for (const j of jq.results ?? []) {
        judged.add(j.tournament_id);
        visible.add(j.tournament_id);
      }
    }
    for (const t of tinfo.values()) {
      if (isOrganizer && t.owner_id === me.id) {
        owned.add(t.id);
        visible.add(t.id);
      }
      // Terminados, y en inscripción con la inscripción desde la app abierta
      // (a los organizadores solo les bajan los suyos: los demás no los
      // pueden cambiar).
      if (!isOrganizer && publicTournament(t)) visible.add(t.id);
    }
    const enrolled = new Set();
    if (pid && !isOrganizer && tids.length) {
      const eq = await this.db
        .prepare("SELECT tournament_id FROM sync_rows WHERE community_id = ? AND tbl = 'tournament_players' AND player_id = ? AND deleted = 0")
        .bind(community, pid)
        .all();
      for (const e of eq.results ?? []) {
        if (!e.tournament_id) continue;
        enrolled.add(e.tournament_id);
        visible.add(e.tournament_id);
      }
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
        const tid = r.tournament_id;
        const mine = owned.has(tid);
        const staff = mine || judged.has(tid);
        if (r.tbl === 'penalties' && r.player_id !== pid && !staff) return;
        if (r.tbl === 'deck_lists' && !staff && r.player_id !== pid && hiddenLists.has(tid)) return;
        const o = out(r);
        if (!mine) for (const k of ORGANIZER_ONLY[r.tbl] ?? []) delete o.data[k];
        // Torneo sin terminar: sin el mazo de los demás (al terminar se
        // vuelve a enviar entero).
        if (!staff && tinfo.get(tid)?.status !== 'finished') SyncService.hideDecks(r.tbl, o.data, pid);
        rows.set(key, o);
      }
    };
    for (const r of delta) add(r);

    // Torneos que se volvieron visibles en este tramo: se envían completos
    // (solo lo anterior a [since]; lo posterior ya va en este tramo o en los
    // siguientes). No en la primera descarga (boot=1 o since=0): ahí llega
    // todo igualmente. No se repite en cada cambio de un torneo que ya veía.
    const expand = new Set();
    if (since > 0 && params.get('boot') !== '1') {
      for (const r of delta) {
        const tid = r.tournament_id;
        if (r.deleted || !tid || !visible.has(tid) || owned.has(tid)) continue;
        if (r.tbl === 'tournaments') {
          // Terminó (lo ve todo el mundo y salen las listas de mazo "al
          // terminar") o abrió la inscripción (lo ve quien no está inscrito).
          const t = tinfo.get(tid);
          if (publicTournament(t) && (t.status === 'finished' || (!enrolled.has(tid) && !judged.has(tid)))) expand.add(tid);
        } else if (r.tbl === 'tournament_players' && pid && r.player_id === pid && SyncService.newEntry(r)) {
          // Lo acaban de inscribir.
          expand.add(tid);
        }
      }
    }
    for (const tid of expand) {
      const all = await this.db
        .prepare(
          'SELECT tbl, id, data, deleted, changed_at, seq, tournament_id, player_id FROM sync_rows WHERE community_id = ? AND tournament_id = ? AND seq <= ? AND deleted = 0',
        )
        .bind(community, tid, since)
        .all();
      for (const r of all.results ?? []) add(r);
    }
    return { rows: [...rows.values()], more, seq };
  }

  /**
   * Edita los datos de una ficha de jugador (no resultados ni estadísticas).
   * La propia ficha: su jugador. Cualquiera: organizadores y administrador.
   * body: { nickname, fullName?, konamiId?, phone?, notes? } (notas: solo
   * organizadores). Queda como un cambio más (llega a todos al sincronizar)
   * y actualiza el apodo y el teléfono de la cuenta vinculada.
   */
  async editPlayer(token, playerId, body) {
    const me = await this.auth.authenticate(token);
    const boss = me.role === 'admin' || me.role === 'organizer';
    if (!boss && me.player_id !== playerId) throw new ApiError(403, 'Solo puedes editar tu propia ficha.');
    const community = me.community_id;
    const r = await this.db
      .prepare("SELECT data, changed_at FROM sync_rows WHERE community_id = ? AND tbl = 'players' AND id = ? AND deleted = 0")
      .bind(community, playerId)
      .first();
    if (!r?.data) throw new ApiError(404, 'Esa ficha no existe o aún no está en el servidor.');
    const text = (v, max) => (typeof v === 'string' && v.trim() ? v.trim().slice(0, max) : null);
    const nickname = text(body?.nickname, 40);
    if (!nickname) throw bad('Escribe un nickname.');
    const data = JSON.parse(r.data);
    data.nickname = nickname;
    if ('fullName' in (body ?? {})) data.full_name = text(body.fullName, 80);
    if ('konamiId' in (body ?? {})) data.konami_id = text(body.konamiId, 30);
    if ('phone' in (body ?? {})) data.phone = text(body.phone, 30);
    if (boss && 'notes' in (body ?? {})) data.notes = text(body.notes, 500);
    const now = this.auth.now();
    // Fechas como las guarda la app (texto ISO 8601).
    data.updated_at = new Date(now).toISOString();
    const changed = Math.max(now, Number(r.changed_at ?? 0) + 1);
    await this.db.batch([
      this.db
        .prepare(
          `UPDATE sync_rows SET data = ?1, changed_at = ?2, updated_by = ?3, received_at = ?4,
                  seq = (SELECT COALESCE(MAX(seq), 0) + 1 FROM sync_rows WHERE community_id = ?5)
            WHERE community_id = ?5 AND tbl = 'players' AND id = ?6`,
        )
        .bind(JSON.stringify(data), changed, me.id, now, community, playerId),
      this.db
        .prepare('UPDATE accounts SET nickname = ?, phone = COALESCE(?, phone), updated_at = ? WHERE community_id = ? AND player_id = ?')
        .bind(nickname, data.phone ?? null, new Date(now).toISOString(), community, playerId),
    ]);
    return { ok: true };
  }

  /**
   * Lista de mazo de un jugador del Top de un torneo terminado. La suya: el
   * jugador. Cualquiera del Top: el organizador del torneo y el
   * administrador. body: { tournamentId, playerId, main, extra, side,
   * featuredCard?, backgroundCard?, secondaryCard? } (códigos separados por
   * comas, como en la app). Queda como un cambio más de deck_lists.
   */
  async saveDeckList(token, body) {
    const me = await this.auth.authenticate(token);
    const community = me.community_id;
    const tid = String(body?.tournamentId ?? '');
    const pid = String(body?.playerId ?? '');
    const t = await this.db
      .prepare("SELECT data, owner_id FROM sync_rows WHERE community_id = ? AND tbl = 'tournaments' AND id = ? AND deleted = 0")
      .bind(community, tid)
      .first();
    if (!t?.data) throw new ApiError(404, 'Ese torneo no existe.');
    const td = JSON.parse(t.data);
    const boss = me.role === 'admin' || (me.role === 'organizer' && t.owner_id === me.id);
    if (!boss && me.player_id !== pid) throw new ApiError(403, 'Solo puedes subir tu propia lista.');
    if (!boss && td.status !== 'finished') throw bad('Las listas se suben cuando termina el torneo.');
    // Del Top: Top Cut del torneo (sin Top Cut, los 4 primeros).
    const e = await this.db
      .prepare("SELECT data FROM sync_rows WHERE community_id = ? AND tbl = 'tournament_players' AND tournament_id = ? AND player_id = ? AND deleted = 0")
      .bind(community, tid, pid)
      .first();
    const entry = e?.data ? JSON.parse(e.data) : null;
    const cut = Number(td.top_cut_size ?? 0) > 0 ? Number(td.top_cut_size) : 4;
    const pos = Number(entry?.final_position ?? 0);
    if (!entry || !(pos > 0 && pos <= cut)) throw bad('Solo los jugadores del Top suben su lista.');
    const codes = (v) => String(v ?? '').split(',').map((x) => x.trim()).filter((x) => /^\d{1,10}$/.test(x)).slice(0, 120).join(',');
    const main = codes(body?.main);
    if (!main) throw bad('La lista está vacía.');
    const card = (v) => (v == null || !/^\d{1,10}$/.test(String(v)) ? null : Number(v));
    const old = await this.db
      .prepare("SELECT id, data, changed_at FROM sync_rows WHERE community_id = ? AND tbl = 'deck_lists' AND tournament_id = ? AND player_id = ?")
      .bind(community, tid, pid)
      .first();
    const now = this.auth.now();
    // Fechas como las guarda la app (texto ISO 8601; un número la rompe).
    const iso = new Date(now).toISOString();
    const prev = old?.data ? JSON.parse(old.data) : null;
    const id = old?.id ?? crypto.randomUUID();
    const data = {
      ...(prev ?? {}),
      id,
      created_at: typeof prev?.created_at === 'string' ? prev.created_at : iso,
      updated_at: iso,
      deleted_at: null,
      tournament_id: tid,
      player_id: pid,
      main_deck: main,
      extra_deck: codes(body?.extra),
      side_deck: codes(body?.side),
      featured_card: card(body?.featuredCard),
      background_card: card(body?.backgroundCard),
      secondary_card: card(body?.secondaryCard),
    };
    const changed = Math.max(now, Number(old?.changed_at ?? 0) + 1);
    await this.db
      .prepare(
        `INSERT INTO sync_rows (community_id, tbl, id, data, deleted, changed_at, seq, owner_id, updated_by, received_at, tournament_id, player_id)
         VALUES (?1, 'deck_lists', ?2, ?3, 0, ?4, (SELECT COALESCE(MAX(seq), 0) + 1 FROM sync_rows WHERE community_id = ?1), ?5, ?6, ?7, ?8, ?9)
         ON CONFLICT (community_id, tbl, id) DO UPDATE SET
           data = excluded.data, deleted = 0, changed_at = excluded.changed_at, seq = excluded.seq,
           updated_by = excluded.updated_by, received_at = excluded.received_at`,
      )
      .bind(community, id, JSON.stringify(data), changed, t.owner_id, me.id, now, tid, pid)
      .run();
    return { ok: true, id };
  }

  /**
   * Administrador: cambia el nombre de varios torneos (p. ej. al formato
   * "Torneo #1 · T4 2026"). body: { items: [{ id, name }] } (máx. 200).
   * Queda como un cambio más de cada torneo (llega a todos al sincronizar).
   */
  async renameTournaments(token, body) {
    const me = await this.auth.requireAdmin(token);
    const community = me.community_id;
    const items = (Array.isArray(body?.items) ? body.items : []).slice(0, 200);
    const now = this.auth.now();
    const iso = new Date(now).toISOString();
    let renamed = 0;
    for (const it of items) {
      const id = String(it?.id ?? '');
      const name = typeof it?.name === 'string' ? it.name.trim().slice(0, 80) : '';
      if (!id || !name) continue;
      const r = await this.db
        .prepare("SELECT data, changed_at FROM sync_rows WHERE community_id = ? AND tbl = 'tournaments' AND id = ? AND deleted = 0")
        .bind(community, id)
        .first();
      if (!r?.data) continue;
      const data = JSON.parse(r.data);
      if (data.name === name) continue;
      data.name = name;
      data.updated_at = iso;
      await this.db
        .prepare(
          `UPDATE sync_rows SET data = ?1, changed_at = ?2, updated_by = ?3, received_at = ?4,
                  seq = (SELECT COALESCE(MAX(seq), 0) + 1 FROM sync_rows WHERE community_id = ?5)
            WHERE community_id = ?5 AND tbl = 'tournaments' AND id = ?6`,
        )
        .bind(JSON.stringify(data), Math.max(now, Number(r.changed_at ?? 0) + 1), me.id, now, community, id)
        .run();
      renamed++;
    }
    return { renamed };
  }

  /** Quita los mazos de los rivales de una fila (deja el propio). */
  static hideDecks(tbl, data, pid) {
    if (tbl === 'tournament_players') {
      if (data.player_id !== pid) data.deck_id = null;
    } else if (tbl === 'matches') {
      if (data.player1_id !== pid) data.deck1_id = null;
      if (data.player2_id !== pid) data.deck2_id = null;
    }
  }

  /** Inscripción recién creada (no una actualización de puestos o check-in
   * de una ronda posterior). Sin fechas legibles: se trata como nueva. */
  static newEntry(r) {
    try {
      const d = JSON.parse(r.data);
      const ms = (v) => (typeof v === 'number' ? (v < 1e11 ? v * 1000 : v) : Date.parse(v));
      const c = ms(d.created_at);
      const u = ms(d.updated_at);
      if (!Number.isFinite(c) || !Number.isFinite(u)) return true;
      return u - c <= NEW_ENTRY_MS;
    } catch {
      return true;
    }
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

// Inscripción desde la app: el jugador pide plaza en un torneo con la
// inscripción en línea abierta y el organizador la acepta (a mano o sola).
// La inscripción de verdad (fila de tournament_players) la crea el teléfono
// del organizador, que es el dueño del torneo; el servidor solo guarda las
// solicitudes y su estado.
import { ApiError } from './auth.js';

const bad = (m) => new ApiError(400, m);
const DECK_MAX = 60;
const REASON_MAX = 200;

export class RegistrationService {
  constructor(env, auth) {
    this.db = env.DB;
    this.auth = auth;
  }

  /** Fila del torneo en la copia del servidor (dueño y datos). */
  async tournament(community, id) {
    if (typeof id !== 'string' || !id) throw bad('Falta el torneo.');
    const r = await this.db
      .prepare("SELECT id, data, owner_id FROM sync_rows WHERE community_id = ? AND tbl = 'tournaments' AND id = ? AND deleted = 0")
      .bind(community, id)
      .first();
    if (!r?.data) throw new ApiError(404, 'Ese torneo no existe o se borró.');
    return { id: r.id, owner: r.owner_id, data: JSON.parse(r.data) };
  }

  static isOpen(t) {
    return t.data.status === 'draft' && Number(t.data.online_registration ?? 0) === 1;
  }

  /** Cupo máximo del torneo (null = sin límite). */
  static capacity(t) {
    const n = Number(t.data.capacity ?? 0);
    return n > 0 ? n : null;
  }

  /** Plazas ocupadas: inscritos + aceptadas aún sin inscribir (+ pendientes
   * si [withPending], para no prometer más plazas de las que hay). */
  async taken(community, tournamentId, withPending = false) {
    const e = await this.db
      .prepare("SELECT COUNT(*) AS n FROM sync_rows WHERE community_id = ? AND tbl = 'tournament_players' AND tournament_id = ? AND deleted = 0")
      .bind(community, tournamentId)
      .first();
    const states = withPending ? "('accepted', 'pending')" : "('accepted')";
    const r = await this.db
      .prepare(`SELECT COUNT(*) AS n FROM registrations WHERE tournament_id = ? AND status IN ${states}`)
      .bind(tournamentId)
      .first();
    return (e?.n ?? 0) + (r?.n ?? 0);
  }

  /** Puesto en la lista de espera de cada solicitud que esté en ella. */
  static positions(list) {
    const byT = new Map();
    for (const r of [...list].sort((a, b) => a.created_at - b.created_at)) {
      if (r.status !== 'waitlist') continue;
      const n = (byT.get(r.tournament_id) ?? 0) + 1;
      byT.set(r.tournament_id, n);
      r.wait_position = n;
    }
    return list;
  }

  static autoAccept(t) {
    return Number(t.data.auto_accept ?? 0) === 1;
  }

  /** ¿Ya está inscrito ese jugador (fila de la inscripción no borrada)? */
  async enrolled(community, tournamentId, playerId) {
    if (!playerId) return false;
    const r = await this.db
      .prepare("SELECT 1 AS x FROM sync_rows WHERE community_id = ? AND tbl = 'tournament_players' AND tournament_id = ? AND player_id = ? AND deleted = 0")
      .bind(community, tournamentId, playerId)
      .first();
    return Boolean(r);
  }

  async byId(id) {
    const r = await this.db
      .prepare(
        `SELECT r.*, a.username, a.nickname, a.player_id AS account_player
           FROM registrations r JOIN accounts a ON a.id = r.account_id WHERE r.id = ?`,
      )
      .bind(id)
      .first();
    if (!r) throw new ApiError(404, 'Esa solicitud ya no existe.');
    return r;
  }

  static out(r) {
    return {
      id: r.id,
      tournamentId: r.tournament_id,
      accountId: r.account_id,
      username: r.username,
      nickname: r.nickname,
      playerId: r.player_id ?? r.account_player ?? null,
      linked: Boolean(r.account_player),
      deckName: r.deck_name ?? null,
      status: r.status,
      waitPosition: r.wait_position ?? null,
      reason: r.reason ?? null,
      createdAt: new Date(r.created_at).toISOString(),
      updatedAt: new Date(r.updated_at).toISOString(),
    };
  }

  async setStatus(id, status, extra = {}) {
    const now = this.auth.now();
    await this.db
      .prepare('UPDATE registrations SET status = ?, reason = ?, player_id = COALESCE(?, player_id), updated_at = ? WHERE id = ?')
      .bind(status, extra.reason ?? null, extra.playerId ?? null, now, id)
      .run();
    return RegistrationService.out(await this.byId(id));
  }

  /** El organizador del torneo (el que lo subió) o el administrador. */
  async manager(token, tournamentId) {
    const me = await this.auth.authenticate(token);
    const t = await this.tournament(me.community_id, tournamentId);
    if (me.role !== 'admin' && !(me.role === 'organizer' && t.owner === me.id)) {
      throw new ApiError(403, 'Solo el organizador del torneo puede hacer esto.');
    }
    return { me, t };
  }

  // ───────────────────── Jugador ─────────────────────

  /** Pide plaza (o cambia el mazo de su solicitud). body: { tournamentId, deckName } */
  async request(token, body) {
    const me = await this.auth.authenticate(token);
    const t = await this.tournament(me.community_id, body?.tournamentId);
    if (!RegistrationService.isOpen(t)) {
      throw bad('La inscripción desde la app de este torneo está cerrada.');
    }
    const deck = typeof body?.deckName === 'string' ? body.deckName.trim().slice(0, DECK_MAX) : '';
    if (!deck) throw bad('Elige tu mazo.');
    if (await this.enrolled(me.community_id, t.id, me.player_id)) {
      throw bad('Ya estás inscrito en este torneo.');
    }
    const auto = RegistrationService.autoAccept(t) && me.player_id;
    const now = this.auth.now();
    const old = await this.db
      .prepare('SELECT id, status FROM registrations WHERE tournament_id = ? AND account_id = ?')
      .bind(t.id, me.id)
      .first();
    // Cupo lleno (contando las pendientes): a la lista de espera.
    const cap = RegistrationService.capacity(t);
    const full = cap != null && (await this.taken(me.community_id, t.id, true)) >= cap;
    const status = full ? 'waitlist' : auto ? 'accepted' : 'pending';
    // (Si figuraba como inscrito pero ya no está en la lista, el organizador
    // lo quitó: vuelve a pedirse.)
    if (old) {
      // Cambia el mazo; si estaba rechazada o cancelada, vuelve a pedirse.
      const keep = old.status === 'pending' || old.status === 'accepted' || old.status === 'waitlist';
      await this.db
        .prepare('UPDATE registrations SET deck_name = ?, status = ?, reason = NULL, player_id = ?, updated_at = ? WHERE id = ?')
        .bind(deck, keep ? old.status : status, me.player_id ?? null, now, old.id)
        .run();
      return { registration: RegistrationService.out(await this.byId(old.id)) };
    }
    const id = crypto.randomUUID();
    await this.db
      .prepare(
        `INSERT INTO registrations (id, community_id, tournament_id, account_id, player_id, deck_name, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .bind(id, me.community_id, t.id, me.id, me.player_id ?? null, deck, status, now, now)
      .run();
    return { registration: RegistrationService.out(await this.byId(id)) };
  }

  /** Solicitudes propias (todas). */
  async mine(token) {
    const me = await this.auth.authenticate(token);
    const q = await this.db
      .prepare(
        `SELECT r.*, a.username, a.nickname, a.player_id AS account_player
           FROM registrations r JOIN accounts a ON a.id = r.account_id
          WHERE r.account_id = ? ORDER BY r.updated_at DESC LIMIT 100`,
      )
      .bind(me.id)
      .all();
    // Torneos con la inscripción desde la app abierta (lo que se ve en el
    // teléfono puede estar desfasado si se cerró o empezó).
    const oq = await this.db
      .prepare(
        `SELECT t.id, t.data,
                (SELECT COUNT(*) FROM sync_rows p WHERE p.community_id = t.community_id AND p.tbl = 'tournament_players'
                   AND p.tournament_id = t.id AND p.deleted = 0) AS enrolled
           FROM sync_rows t
          WHERE t.community_id = ? AND t.tbl = 'tournaments' AND t.deleted = 0
            AND json_extract(t.data, '$.status') = 'draft'
            AND json_extract(t.data, '$.online_registration') = 1`,
      )
      .bind(me.community_id)
      .all();
    const open = (oq.results ?? []).map((r) => {
      const d = JSON.parse(r.data);
      return {
        id: r.id,
        name: d.name ?? '',
        date: d.date ?? null,
        swissRounds: d.swiss_rounds ?? null,
        capacity: Number(d.capacity ?? 0) > 0 ? Number(d.capacity) : null,
        topCutSize: d.top_cut_size ?? 0,
        autoAccept: Number(d.auto_accept ?? 0) === 1,
        enrolled: r.enrolled ?? 0,
      };
    });
    // Puesto en la lista de espera: se cuenta entre todas las del torneo.
    const own = q.results ?? [];
    const waiting = own.filter((r) => r.status === 'waitlist').map((r) => r.tournament_id);
    if (waiting.length) {
      const wq = await this.db
        .prepare(
          `SELECT id, tournament_id, status, created_at FROM registrations
            WHERE status = 'waitlist' AND tournament_id IN (${waiting.map(() => '?').join(',')})`,
        )
        .bind(...waiting)
        .all();
      const pos = new Map(RegistrationService.positions(wq.results ?? []).map((r) => [r.id, r.wait_position]));
      for (const r of own) if (pos.has(r.id)) r.wait_position = pos.get(r.id);
    }
    return {
      registrations: own.map(RegistrationService.out),
      playerId: me.player_id ?? null,
      open,
    };
  }

  /** El jugador se borra: antes de inscribirlo, se cancela; si ya está
   * inscrito, el teléfono del organizador lo quitará. */
  async cancel(token, id) {
    const me = await this.auth.authenticate(token);
    const r = await this.byId(id);
    if (r.account_id !== me.id) throw new ApiError(403, 'Esa solicitud no es tuya.');
    const t = await this.tournament(me.community_id, r.tournament_id);
    if (t.data.status !== 'draft') throw bad('El torneo ya empezó: habla con el organizador.');
    if (r.status === 'pending' || r.status === 'accepted' || r.status === 'waitlist') {
      return { registration: await this.setStatus(id, 'cancelled') };
    }
    if (r.status === 'registered') return { registration: await this.setStatus(id, 'cancel_requested') };
    return { registration: RegistrationService.out(r) };
  }

  // ───────────────────── Organizador ─────────────────────

  /** Solicitudes de un torneo (las de jugadores ya borrados no salen). */
  async forTournament(token, tournamentId) {
    const { me } = await this.manager(token, tournamentId);
    const q = await this.db
      .prepare(
        `SELECT r.*, a.username, a.nickname, a.player_id AS account_player
           FROM registrations r JOIN accounts a ON a.id = r.account_id
          WHERE r.community_id = ? AND r.tournament_id = ? ORDER BY r.created_at`,
      )
      .bind(me.community_id, tournamentId)
      .all();
    return { registrations: RegistrationService.positions(q.results ?? []).map(RegistrationService.out) };
  }

  /**
   * Trabajo para el teléfono del organizador: solicitudes aceptadas que hay
   * que inscribir y bajas que hay que quitar, de los torneos que subió él.
   * Antes, si el torneo acepta solo, se aceptan las pendientes de cuentas
   * con ficha vinculada (por si activó "aceptar solas" después).
   */
  async todo(token) {
    const me = await this.auth.authenticate(token);
    if (me.role !== 'admin' && me.role !== 'organizer') return { registrations: [] };
    const tq = await this.db
      .prepare(
        `SELECT id, json_extract(data, '$.status') AS status,
                json_extract(data, '$.online_registration') AS online,
                json_extract(data, '$.auto_accept') AS auto
           FROM sync_rows WHERE community_id = ? AND tbl = 'tournaments' AND deleted = 0 AND owner_id = ?`,
      )
      .bind(me.community_id, me.id)
      .all();
    const mine = (tq.results ?? []).filter((t) => t.status === 'draft');
    if (!mine.length) return { registrations: [] };
    // Por cada torneo: con "aceptar solas", las pendientes con ficha pasan a
    // aceptadas mientras haya plazas; y si se liberan plazas, sube la lista
    // de espera (por orden de llegada).
    for (const tr of mine) {
      if (Number(tr.online) !== 1) continue;
      const t = await this.tournament(me.community_id, tr.id);
      const cap = RegistrationService.capacity(t);
      const auto = Number(tr.auto) === 1;
      const rq = await this.db
        .prepare(
          `SELECT r.id, r.status, a.player_id AS account_player FROM registrations r
             JOIN accounts a ON a.id = r.account_id
            WHERE r.tournament_id = ? AND r.status IN ('pending', 'waitlist') ORDER BY r.created_at`,
        )
        .bind(tr.id)
        .all();
      let taken = await this.taken(me.community_id, tr.id, !auto);
      for (const r of rq.results ?? []) {
        const room = cap == null || taken < cap;
        const toAccept = Boolean(auto && r.account_player && room);
        if (r.status === 'pending' && auto && r.account_player && room) {
          await this.setStatus(r.id, 'accepted', { playerId: r.account_player });
          taken++;
        } else if (r.status === 'waitlist' && room) {
          await this.setStatus(r.id, toAccept ? 'accepted' : 'pending',
            toAccept ? { playerId: r.account_player } : {});
          taken++;
        }
      }
    }
    const ids = mine.map((t) => t.id);
    const q = await this.db
      .prepare(
        `SELECT r.*, a.username, a.nickname, a.player_id AS account_player
           FROM registrations r JOIN accounts a ON a.id = r.account_id
          WHERE r.community_id = ? AND r.status IN ('accepted', 'cancel_requested')
            AND r.tournament_id IN (${ids.map(() => '?').join(',')})`,
      )
      .bind(me.community_id, ...ids)
      .all();
    return { registrations: (q.results ?? []).map(RegistrationService.out) };
  }

  /**
   * Acepta una solicitud con la ficha [playerId]. Si la cuenta no tenía ficha,
   * queda vinculada a esa (si la ficha no es de otra cuenta).
   */
  async accept(token, id, body) {
    const r = await this.byId(id);
    const { me, t } = await this.manager(token, r.tournament_id);
    if (t.data.status !== 'draft') throw bad('El torneo ya empezó.');
    if (!['pending', 'rejected', 'accepted', 'waitlist'].includes(r.status)) {
      return { registration: RegistrationService.out(r) };
    }
    const cap = RegistrationService.capacity(t);
    if (cap != null && r.status !== 'accepted' && (await this.taken(me.community_id, t.id)) >= cap) {
      throw bad(`El cupo (${cap}) está lleno: auméntalo o rechaza a alguien.`);
    }
    const playerId = typeof body?.playerId === 'string' && body.playerId ? body.playerId : r.account_player;
    if (!playerId) throw bad('Elige la ficha de jugador de esta cuenta.');
    if (r.account_player && r.account_player !== playerId) {
      throw bad('Esta cuenta ya está vinculada a otra ficha.');
    }
    if (!r.account_player) {
      const other = await this.db
        .prepare('SELECT username FROM accounts WHERE player_id = ? AND id != ?')
        .bind(playerId, r.account_id)
        .first();
      if (other) throw bad(`Esa ficha ya es de la cuenta @${other.username}.`);
      await this.db
        .prepare('UPDATE accounts SET player_id = ?, updated_at = ? WHERE id = ? AND community_id = ?')
        .bind(playerId, new Date(this.auth.now()).toISOString(), r.account_id, me.community_id)
        .run();
    }
    return { registration: await this.setStatus(id, 'accepted', { playerId }) };
  }

  async reject(token, id, body) {
    const r = await this.byId(id);
    await this.manager(token, r.tournament_id);
    if (r.status === 'registered' || r.status === 'cancel_requested') {
      throw bad('Ya está inscrito: quítalo de la lista de inscritos.');
    }
    const reason = typeof body?.reason === 'string' ? body.reason.trim().slice(0, REASON_MAX) : null;
    return { registration: await this.setStatus(id, 'rejected', { reason: reason || null }) };
  }

  /** El teléfono del organizador ya lo inscribió (o ya lo quitó). */
  async done(token, id) {
    const r = await this.byId(id);
    await this.manager(token, r.tournament_id);
    if (r.status === 'accepted') return { registration: await this.setStatus(id, 'registered') };
    if (r.status === 'cancel_requested') return { registration: await this.setStatus(id, 'cancelled') };
    return { registration: RegistrationService.out(r) };
  }
}


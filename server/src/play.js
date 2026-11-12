// Durante el torneo, desde el teléfono del jugador: reportar el resultado de
// su mesa (el rival lo confirma), llamar al juez y retirarse (drop). El
// teléfono del organizador aplica los resultados confirmados y los drops al
// sincronizar, y ve los avisos (juez, resultados que no coinciden).
import { ApiError } from './auth.js';

const bad = (m) => new ApiError(400, m);
const NOTE_MAX = 200;

/** Marcadores aceptados (juegos J1 - empates - J2), como en la app. */
const ALLOWED = ['2-0-0', '2-0-1', '0-0-2', '1-0-2', '1-1-1'];

export class PlayService {
  constructor(env, auth) {
    this.db = env.DB;
    this.auth = auth;
  }

  async row(community, tbl, id) {
    const r = await this.db
      .prepare('SELECT data, owner_id FROM sync_rows WHERE community_id = ? AND tbl = ? AND id = ? AND deleted = 0')
      .bind(community, tbl, id)
      .first();
    return r?.data ? { ...JSON.parse(r.data), _owner: r.owner_id } : null;
  }

  /** Torneo en juego en el que está inscrito (sin drop) el jugador de la cuenta. */
  async playing(me, tournamentId) {
    if (!me.player_id) throw bad('Tu cuenta no tiene ficha de jugador vinculada.');
    const t = await this.row(me.community_id, 'tournaments', tournamentId);
    if (!t) throw new ApiError(404, 'Ese torneo no existe.');
    if (t.status !== 'swiss' && t.status !== 'topCut') throw bad('El torneo no está en juego.');
    const e = await this.db
      .prepare(
        "SELECT data FROM sync_rows WHERE community_id = ? AND tbl = 'tournament_players' AND tournament_id = ? AND player_id = ? AND deleted = 0",
      )
      .bind(me.community_id, tournamentId, me.player_id)
      .first();
    if (!e) throw new ApiError(403, 'No estás inscrito en este torneo.');
    return { t, entry: JSON.parse(e.data) };
  }

  static out(r) {
    return {
      id: r.id,
      tournamentId: r.tournament_id,
      matchId: r.match_id ?? null,
      playerId: r.player_id,
      nickname: r.nickname ?? null,
      kind: r.kind,
      score: r.g1 == null ? null : { g1: r.g1, gd: r.gd, g2: r.g2 },
      otherScore: r.other_g1 == null ? null : { g1: r.other_g1, gd: r.other_gd, g2: r.other_g2 },
      note: r.note ?? null,
      extra: r.extra ?? null,
      targetPlayer: r.target_player ?? null,
      penalty: r.penalty ?? null,
      doubleLoss: Boolean(r.double_loss),
      status: r.status,
      createdAt: new Date(r.created_at).toISOString(),
      updatedAt: new Date(r.updated_at).toISOString(),
    };
  }

  async byId(id) {
    const r = await this.db
      .prepare('SELECT p.*, a.nickname FROM play_actions p JOIN accounts a ON a.id = p.account_id WHERE p.id = ?')
      .bind(id)
      .first();
    if (!r) throw new ApiError(404, 'Ese aviso ya no existe.');
    return r;
  }

  async insert(me, fields) {
    const id = crypto.randomUUID();
    const now = this.auth.now();
    await this.db
      .prepare(
        `INSERT INTO play_actions (id, community_id, tournament_id, match_id, account_id, player_id, kind, g1, gd, g2, note,
                                   extra, target_player, penalty, double_loss, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .bind(id, me.community_id, fields.tournamentId, fields.matchId ?? null, me.id, me.player_id ?? '', fields.kind,
        fields.g1 ?? null, fields.gd ?? null, fields.g2 ?? null, fields.note ?? null,
        fields.extra ?? null, fields.targetPlayer ?? null, fields.penalty ?? null, fields.doubleLoss ? 1 : null,
        fields.status, now, now)
      .run();
    return id;
  }

  async set(id, fields) {
    const keys = Object.keys(fields);
    await this.db
      .prepare(`UPDATE play_actions SET ${keys.map((k) => `${k} = ?`).join(', ')}, updated_at = ? WHERE id = ?`)
      .bind(...keys.map((k) => fields[k]), this.auth.now(), id)
      .run();
  }

  // ───────────────────── Jugador ─────────────────────

  /**
   * Reporta el resultado de su mesa. body: { tournamentId, matchId, g1, gd, g2 }
   * (juegos vistos desde el jugador 1 de la mesa). Si el rival ya había
   * reportado lo mismo, queda confirmado; si no coincide, queda en disputa
   * para el organizador.
   */
  async report(token, body) {
    const me = await this.auth.authenticate(token);
    const { t } = await this.playing(me, body?.tournamentId);
    const m = await this.row(me.community_id, 'matches', body?.matchId);
    if (!m || m.tournament_id !== body.tournamentId) throw new ApiError(404, 'Esa mesa no existe.');
    if (m.player1_id !== me.player_id && m.player2_id !== me.player_id) {
      throw new ApiError(403, 'Esa no es tu mesa.');
    }
    if (m.is_bye) throw bad('Tienes BYE: no hay que reportar.');
    if (m.result && m.result !== 'pending') throw bad('El organizador ya puso el resultado de esta mesa.');
    const g1 = Number(body.g1);
    const gd = Number(body.gd ?? 0);
    const g2 = Number(body.g2);
    if (!ALLOWED.includes(`${g1}-${gd}-${g2}`)) throw bad('Marcador no válido.');
    if (gd > 0 && t.status === 'topCut') throw bad('En el Top Cut no hay empates.');

    const prev = await this.db
      .prepare("SELECT * FROM play_actions WHERE match_id = ? AND kind = 'report' AND status IN ('proposed', 'confirmed', 'disputed')")
      .bind(m.id)
      .first();
    if (!prev) {
      const id = await this.insert(me, { tournamentId: t.id, matchId: m.id, kind: 'report', g1, gd, g2, status: 'proposed' });
      return { action: PlayService.out(await this.byId(id)) };
    }
    if (prev.status === 'confirmed') throw bad('El resultado ya está confirmado: si hay un error, llama al juez.');
    const same = prev.g1 === g1 && prev.gd === gd && prev.g2 === g2;
    if (prev.account_id === me.id) {
      // Corrige lo que había reportado (si estaba en disputa, sigue en disputa
      // salvo que ahora coincida con el rival).
      const agrees = prev.other_g1 === g1 && prev.other_gd === gd && prev.other_g2 === g2;
      await this.set(prev.id, {
        g1, gd, g2,
        status: prev.status === 'disputed' && !agrees ? 'disputed' : agrees ? 'confirmed' : 'proposed',
      });
    } else if (same) {
      await this.set(prev.id, { status: 'confirmed' });
    } else {
      await this.set(prev.id, { status: 'disputed', other_g1: g1, other_gd: gd, other_g2: g2 });
    }
    return { action: PlayService.out(await this.byId(prev.id)) };
  }

  /** El rival confirma (o dice que no es correcto) lo que reportó el otro. */
  async answer(token, id, ok) {
    const me = await this.auth.authenticate(token);
    const r = await this.byId(id);
    if (r.kind !== 'report') throw bad('Eso no es un resultado.');
    const m = await this.row(me.community_id, 'matches', r.match_id);
    const mine = m && (m.player1_id === me.player_id || m.player2_id === me.player_id);
    if (!mine || r.account_id === me.id) throw new ApiError(403, 'Solo tu rival puede confirmar este resultado.');
    if (r.status !== 'proposed') return { action: PlayService.out(r) };
    await this.set(id, { status: ok ? 'confirmed' : 'disputed' });
    return { action: PlayService.out(await this.byId(id)) };
  }

  /** Llamar al juez desde la mesa. body: { tournamentId, matchId?, note? } */
  async judge(token, body) {
    const me = await this.auth.authenticate(token);
    const { t } = await this.playing(me, body?.tournamentId);
    const open = await this.db
      .prepare("SELECT id FROM play_actions WHERE tournament_id = ? AND account_id = ? AND kind = 'judge' AND status = 'open'")
      .bind(t.id, me.id)
      .first();
    if (open) return { action: PlayService.out(await this.byId(open.id)) };
    const note = typeof body?.note === 'string' ? body.note.trim().slice(0, NOTE_MAX) : null;
    const id = await this.insert(me, { tournamentId: t.id, matchId: body?.matchId ?? null, kind: 'judge', note: note || null, status: 'open' });
    return { action: PlayService.out(await this.byId(id)) };
  }

  /** Retirarse del torneo (drop). Lo aplica el teléfono del organizador. */
  async drop(token, body) {
    const me = await this.auth.authenticate(token);
    const { t, entry } = await this.playing(me, body?.tournamentId);
    if (entry.dropped) throw bad('Ya estás retirado.');
    const open = await this.db
      .prepare("SELECT id FROM play_actions WHERE tournament_id = ? AND account_id = ? AND kind = 'drop' AND status = 'open'")
      .bind(t.id, me.id)
      .first();
    if (open) return { action: PlayService.out(await this.byId(open.id)) };
    const id = await this.insert(me, { tournamentId: t.id, kind: 'drop', status: 'open' });
    return { action: PlayService.out(await this.byId(id)) };
  }

  /** El jugador cancela su llamada al juez o su drop (si aún no se aplicó). */
  async cancel(token, id) {
    const me = await this.auth.authenticate(token);
    const r = await this.byId(id);
    if (r.account_id !== me.id) throw new ApiError(403, 'Ese aviso no es tuyo.');
    if (r.status === 'open' || r.status === 'proposed') await this.set(id, { status: 'cancelled' });
    return { action: PlayService.out(await this.byId(id)) };
  }

  /**
   * Lo que el jugador necesita ver en su mesa: avisos suyos abiertos y el
   * resultado reportado de su mesa (por él o por su rival).
   */
  async mine(token, tournamentId) {
    const me = await this.auth.authenticate(token);
    if (!me.player_id || !tournamentId) return { actions: [] };
    const q = await this.db
      .prepare(
        `SELECT p.*, a.nickname FROM play_actions p JOIN accounts a ON a.id = p.account_id
          WHERE p.community_id = ? AND p.tournament_id = ? AND p.status NOT IN ('cancelled')
            AND (p.account_id = ? OR (p.kind = 'report' AND p.match_id IN (
                  SELECT id FROM sync_rows WHERE community_id = ? AND tbl = 'matches' AND tournament_id = ?
                    AND (json_extract(data, '$.player1_id') = ? OR json_extract(data, '$.player2_id') = ?))))
          ORDER BY p.created_at DESC LIMIT 50`,
      )
      .bind(me.community_id, tournamentId, me.id, me.community_id, tournamentId, me.player_id, me.player_id)
      .all();
    return { actions: (q.results ?? []).map(PlayService.out) };
  }

  // ───────────────────── Organizador ─────────────────────

  /** ¿Es juez de ese torneo? */
  async isJudge(me, tournamentId) {
    const r = await this.db
      .prepare('SELECT 1 AS x FROM tournament_staff WHERE tournament_id = ? AND account_id = ?')
      .bind(tournamentId, me.id)
      .first();
    return Boolean(r);
  }

  /** El organizador del torneo o el administrador ([judges]: también sus jueces). */
  async manager(token, tournamentId, { judges = false } = {}) {
    const me = await this.auth.authenticate(token);
    const t = await this.row(me.community_id, 'tournaments', tournamentId);
    if (!t) throw new ApiError(404, 'Ese torneo no existe.');
    const boss = me.role === 'admin' || (me.role === 'organizer' && t._owner === me.id);
    if (!boss && !(judges && (await this.isJudge(me, tournamentId)))) {
      throw new ApiError(403, judges ? 'Solo el organizador y los jueces del torneo.' : 'Solo el organizador del torneo puede hacer esto.');
    }
    return me;
  }

  /** Avisos abiertos de un torneo (juez, drops, resultados sin aplicar). */
  async forTournament(token, tournamentId) {
    const me = await this.manager(token, tournamentId, { judges: true });
    const q = await this.db
      .prepare(
        `SELECT p.*, a.nickname FROM play_actions p JOIN accounts a ON a.id = p.account_id
          WHERE p.community_id = ? AND p.tournament_id = ? AND p.status IN ('open', 'proposed', 'confirmed', 'disputed')
            AND p.kind IN ('report', 'judge', 'drop')
          ORDER BY p.created_at`,
      )
      .bind(me.community_id, tournamentId)
      .all();
    return { actions: (q.results ?? []).map(PlayService.out) };
  }

  /** Para el teléfono del organizador (en cada sincronización): resultados
   * confirmados y drops de sus torneos en juego, para aplicarlos. */
  async todo(token) {
    const me = await this.auth.authenticate(token);
    if (me.role !== 'admin' && me.role !== 'organizer') return { actions: [] };
    const q = await this.db
      .prepare(
        `SELECT p.*, a.nickname FROM play_actions p JOIN accounts a ON a.id = p.account_id
          WHERE p.community_id = ? AND (
                  (p.kind IN ('report', 'jresult', 'extension', 'penalty') AND p.status = 'confirmed')
               OR (p.kind IN ('drop', 'checkin') AND p.status = 'open'))
            AND p.tournament_id IN (SELECT id FROM sync_rows WHERE community_id = ? AND tbl = 'tournaments'
                                     AND deleted = 0 AND owner_id = ?)`,
      )
      .bind(me.community_id, me.community_id, me.id)
      .all();
    return { actions: (q.results ?? []).map(PlayService.out) };
  }

  /** El organizador cierra un aviso: aplicado, atendido o descartado. */
  async done(token, id) {
    const r = await this.byId(id);
    // Los jueces pueden marcar avisos como atendidos; aplicar resultados,
    // drops y demás lo hace el teléfono del organizador.
    await this.manager(token, r.tournament_id, { judges: ['judge', 'report'].includes(r.kind) });
    if (!['open', 'proposed', 'confirmed', 'disputed'].includes(r.status)) return { action: PlayService.out(r) };
    await this.set(id, { status: 'done' });
    return { action: PlayService.out(await this.byId(id)) };
  }

  // ───────────────────── Check-in ─────────────────────

  /** El jugador hace check-in con el código que da el organizador. */
  async checkin(token, body) {
    const me = await this.auth.authenticate(token);
    if (!me.player_id) throw bad('Tu cuenta no tiene ficha de jugador vinculada.');
    const t = await this.row(me.community_id, 'tournaments', body?.tournamentId);
    if (!t) throw new ApiError(404, 'Ese torneo no existe.');
    if (t.status !== 'draft' || Number(t.check_in ?? 0) !== 1) throw bad('El check-in de este torneo no está abierto.');
    const norm = (v) => String(v ?? '').trim().toUpperCase();
    if (!norm(t.checkin_code) || norm(body?.code) !== norm(t.checkin_code)) throw bad('Código incorrecto.');
    const e = await this.db
      .prepare("SELECT 1 AS x FROM sync_rows WHERE community_id = ? AND tbl = 'tournament_players' AND tournament_id = ? AND player_id = ? AND deleted = 0")
      .bind(me.community_id, t.id, me.player_id)
      .first();
    if (!e) throw new ApiError(403, 'No estás inscrito en este torneo.');
    const open = await this.db
      .prepare("SELECT id FROM play_actions WHERE tournament_id = ? AND account_id = ? AND kind = 'checkin' AND status IN ('open', 'done')")
      .bind(t.id, me.id)
      .first();
    if (open) return { action: PlayService.out(await this.byId(open.id)) };
    const id = await this.insert(me, { tournamentId: t.id, kind: 'checkin', status: 'open' });
    return { action: PlayService.out(await this.byId(id)) };
  }

  // ───────────────────── Juez ─────────────────────

  async judgeMatch(token, body) {
    const me = await this.manager(token, body?.tournamentId, { judges: true });
    const m = await this.row(me.community_id, 'matches', body?.matchId);
    if (!m || m.tournament_id !== body.tournamentId) throw new ApiError(404, 'Esa mesa no existe.');
    return { me, m };
  }

  /** Cancela la acción anterior del mismo tipo en esa mesa (vale la última). */
  async replacePrevious(matchId, kind) {
    await this.db
      .prepare("UPDATE play_actions SET status = 'cancelled', updated_at = ? WHERE match_id = ? AND kind = ? AND status = 'confirmed'")
      .bind(this.auth.now(), matchId, kind)
      .run();
  }

  /** Resultado que pone el juez (lo aplica el teléfono del organizador). */
  async judgeResult(token, body) {
    const { me, m } = await this.judgeMatch(token, body);
    if (m.is_bye) throw bad('Es un BYE.');
    const doubleLoss = body?.doubleLoss === true;
    const g1 = Number(body?.g1);
    const gd = Number(body?.gd ?? 0);
    const g2 = Number(body?.g2);
    if (!doubleLoss && !ALLOWED.includes(`${g1}-${gd}-${g2}`)) throw bad('Marcador no válido.');
    await this.replacePrevious(m.id, 'jresult');
    const id = await this.insert(me, {
      tournamentId: body.tournamentId, matchId: m.id, kind: 'jresult',
      ...(doubleLoss ? { doubleLoss: true } : { g1, gd, g2 }), status: 'confirmed',
    });
    // Los reportes de los jugadores de esa mesa quedan resueltos.
    await this.db
      .prepare("UPDATE play_actions SET status = 'done', updated_at = ? WHERE match_id = ? AND kind = 'report' AND status IN ('proposed', 'disputed', 'confirmed')")
      .bind(this.auth.now(), m.id)
      .run();
    return { action: PlayService.out(await this.byId(id)) };
  }

  /** Tiempo extra para una mesa (total en minutos, 0 = quitarlo). */
  async extension(token, body) {
    const { me, m } = await this.judgeMatch(token, body);
    const minutes = Math.trunc(Number(body?.minutes));
    if (!Number.isFinite(minutes) || minutes < 0 || minutes > 30) throw bad('Entre 0 y 30 minutos.');
    await this.replacePrevious(m.id, 'extension');
    const id = await this.insert(me, { tournamentId: body.tournamentId, matchId: m.id, kind: 'extension', extra: minutes, status: 'confirmed' });
    return { action: PlayService.out(await this.byId(id)) };
  }

  /** Penalización que pone el juez. */
  async penalty(token, body) {
    const me = await this.manager(token, body?.tournamentId, { judges: true });
    const kinds = ['warning', 'gameLoss', 'matchLoss', 'disqualification'];
    if (!kinds.includes(body?.penalty)) throw bad('Tipo de penalización no válido.');
    const target = typeof body?.playerId === 'string' ? body.playerId : '';
    const e = await this.db
      .prepare("SELECT 1 AS x FROM sync_rows WHERE community_id = ? AND tbl = 'tournament_players' AND tournament_id = ? AND player_id = ? AND deleted = 0")
      .bind(me.community_id, body.tournamentId, target)
      .first();
    if (!e) throw bad('Ese jugador no está en el torneo.');
    const note = typeof body?.reason === 'string' ? body.reason.trim().slice(0, NOTE_MAX) : null;
    const id = await this.insert(me, {
      tournamentId: body.tournamentId, matchId: body?.matchId ?? null, kind: 'penalty',
      targetPlayer: target, penalty: body.penalty, note: note || null, status: 'confirmed',
    });
    return { action: PlayService.out(await this.byId(id)) };
  }

  // ───────────────────── Jueces del torneo ─────────────────────

  /** Cuentas que pueden ser jueces (rol juez, organizador o administrador). */
  async candidates(token) {
    const me = await this.auth.authenticate(token);
    if (me.role !== 'admin' && me.role !== 'organizer') throw new ApiError(403, 'Solo organizadores.');
    const q = await this.db
      .prepare("SELECT id, username, nickname, role FROM accounts WHERE community_id = ? AND role IN ('judge', 'organizer', 'admin') ORDER BY nickname")
      .bind(me.community_id)
      .all();
    return { accounts: q.results ?? [] };
  }

  async judges(token, tournamentId) {
    await this.manager(token, tournamentId);
    const q = await this.db
      .prepare(
        `SELECT a.id, a.username, a.nickname, a.role FROM tournament_staff s JOIN accounts a ON a.id = s.account_id
          WHERE s.tournament_id = ? ORDER BY a.nickname`,
      )
      .bind(tournamentId)
      .all();
    return { judges: q.results ?? [] };
  }

  async addJudge(token, tournamentId, body) {
    const me = await this.manager(token, tournamentId);
    const a = await this.db
      .prepare('SELECT id, role FROM accounts WHERE id = ? AND community_id = ?')
      .bind(body?.accountId ?? '', me.community_id)
      .first();
    if (!a) throw new ApiError(404, 'Esa cuenta no existe.');
    if (!['judge', 'organizer', 'admin'].includes(a.role)) throw bad('Esa cuenta no tiene rol de juez.');
    await this.db
      .prepare('INSERT OR IGNORE INTO tournament_staff (community_id, tournament_id, account_id, created_at) VALUES (?, ?, ?, ?)')
      .bind(me.community_id, tournamentId, a.id, this.auth.now())
      .run();
    return this.judges(token, tournamentId);
  }

  async removeJudge(token, tournamentId, accountId) {
    await this.manager(token, tournamentId);
    await this.db
      .prepare('DELETE FROM tournament_staff WHERE tournament_id = ? AND account_id = ?')
      .bind(tournamentId, accountId)
      .run();
    return this.judges(token, tournamentId);
  }

  /** Torneos en los que esta cuenta es juez. */
  async judging(token) {
    const me = await this.auth.authenticate(token);
    const q = await this.db
      .prepare('SELECT tournament_id FROM tournament_staff WHERE account_id = ?')
      .bind(me.id)
      .all();
    return { tournaments: (q.results ?? []).map((r) => r.tournament_id) };
  }
}

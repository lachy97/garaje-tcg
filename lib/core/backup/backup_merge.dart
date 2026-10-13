import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import '../db/app_database.dart';

/// Resumen de una importación integrada.
class MergeReport {
  int tournamentsAdded = 0;
  int tournamentsReplaced = 0;
  int tournamentsSkipped = 0;
  int playersAdded = 0;
  int decksAdded = 0;

  @override
  String toString() {
    final parts = <String>[
      if (tournamentsAdded > 0) '$tournamentsAdded torneo(s) nuevo(s)',
      if (tournamentsReplaced > 0) '$tournamentsReplaced torneo(s) actualizado(s)',
      if (tournamentsSkipped > 0) '$tournamentsSkipped torneo(s) sin tocar',
      if (playersAdded > 0) '$playersAdded jugador(es) nuevo(s)',
      if (decksAdded > 0) '$decksAdded mazo(s) nuevo(s)',
    ];
    return parts.isEmpty ? 'No había nada nuevo que integrar' : parts.join(' · ');
  }
}

/// Qué relación tiene un torneo de la copia con los del teléfono.
enum MergeKind {
  /// No existe en el teléfono.
  newTournament,

  /// Es el mismo torneo (mismo id): una versión de él.
  sameTournament,

  /// Otro torneo con el mismo nombre y la misma fecha (casi seguro el mismo).
  sameNameSameDate,

  /// Mismo nombre pero otra fecha: probablemente es OTRO torneo.
  sameNameOtherDate,

  /// Ese torneo se borró en este teléfono.
  deletedHere,

  /// Es de una temporada cerrada en este teléfono: no se puede tocar.
  lockedSeason,
}

/// Qué hacer con un torneo de la copia.
enum MergeAction {
  /// Añadirlo como torneo nuevo (los del teléfono se quedan).
  add,

  /// Reemplazar el del teléfono por el de la copia.
  replace,

  /// No importarlo.
  skip,
}

/// Un torneo de la copia con su situación y la acción elegida.
class MergeItem {
  MergeItem({
    required this.importId,
    required this.name,
    required this.date,
    required this.kind,
    required this.allowed,
    required this.action,
    this.localId,
    this.localName,
    this.localDate,
    this.localNewer = false,
  });

  final String importId;
  final String name;
  final DateTime? date;
  final MergeKind kind;

  /// Torneo del teléfono afectado (si lo hay).
  final String? localId;
  final String? localName;
  final DateTime? localDate;

  /// El del teléfono tiene cambios más recientes que el de la copia.
  final bool localNewer;

  final List<MergeAction> allowed;
  MergeAction action;
}

/// Lista de torneos de la copia y qué se hará con cada uno.
class MergePlan {
  const MergePlan(this.items);

  final List<MergeItem> items;

  Map<String, MergeAction> get decisions => {for (final i in items) i.importId: i.action};

  /// Hay algo que el usuario debería revisar (dudas o el del teléfono más nuevo).
  bool get needsReview => items.any((i) =>
      i.localNewer ||
      i.kind == MergeKind.sameNameOtherDate ||
      i.kind == MergeKind.deletedHere ||
      i.kind == MergeKind.lockedSeason);
}

/// Integra una copia (.gtcg ya validada) en la BD actual SIN borrar lo que hay.
///
/// 1. [plan] mira cada torneo de la copia y propone qué hacer (se muestra al
///    usuario para que elija).
/// 2. [merge] aplica esas decisiones:
///    - **Torneos**: añadir, reemplazar el del teléfono o no importar.
///      Por defecto: el mismo torneo (mismo id, o mismo nombre y fecha) se
///      reemplaza, salvo que el del teléfono tenga cambios más recientes; con
///      el mismo nombre pero otra fecha se añade como otro torneo; los
///      borrados en este teléfono y los de temporadas cerradas no se tocan.
///    - **Jugadores**: por id y, si no, por apodo. A los existentes solo se les
///      completan datos vacíos; nunca se "resucitan" jugadores borrados aquí.
///    - **Mazos**: por id o por nombre. **Temporadas**: por año y trimestre.
///    - La escala de puntos y los ajustes del teléfono no se tocan.
class BackupMerger {
  BackupMerger(this._db, {Directory? tempDir}) : _tempDir = tempDir;

  final AppDatabase _db;
  final Directory? _tempDir;

  /// Propone qué hacer con cada torneo de la copia (no cambia nada).
  Future<MergePlan> plan(Uint8List sqlite) => _withAttached(sqlite, _plan);

  /// Integra la copia. [decisions] = acción por id de torneo de la copia
  /// (los que falten usan la propuesta de [plan]).
  Future<MergeReport> merge(Uint8List sqlite, {Map<String, MergeAction>? decisions}) async {
    final report = await _withAttached(
        sqlite, () => _db.transaction(() => _merge(decisions ?? const {})));
    // Las pantallas abiertas se refrescan con los datos nuevos.
    _db.markTablesUpdated(_db.allTables);
    return report;
  }

  Future<T> _withAttached<T>(Uint8List sqlite, Future<T> Function() body) async {
    final dir = _tempDir ?? await getTemporaryDirectory();
    final file = File('${dir.path}/integrar_${DateTime.now().microsecondsSinceEpoch}.sqlite');
    await file.writeAsBytes(sqlite, flush: true);
    try {
      // La copia se abre aparte para llevarla al esquema actual (si viene de
      // una versión anterior, Drift la migra igual que al abrir la app).
      final incoming = AppDatabase(NativeDatabase(file));
      await incoming.customSelect('SELECT 1').get();
      await incoming.close();

      await _db.customStatement('ATTACH DATABASE ? AS imp', [file.path]);
      try {
        return await body();
      } finally {
        await _db.customStatement('DETACH DATABASE imp');
      }
    } finally {
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final f = File('${file.path}$suffix');
        if (await f.exists()) await f.delete();
      }
    }
  }

  // ───────────────────────── Plan ─────────────────────────

  Future<MergePlan> _plan() async {
    final locals = await _rows('SELECT t.id, t.name, t.date, t.deleted_at, s.status AS season_status '
        'FROM main.tournaments t LEFT JOIN main.seasons s ON s.id = t.season_id');
    final items = <MergeItem>[];
    for (final t in await _rows('SELECT t.*, s.game AS s_game, s.year AS s_year, '
        's.quarter AS s_quarter FROM imp.tournaments t '
        'LEFT JOIN imp.seasons s ON s.id = t.season_id '
        'WHERE t.deleted_at IS NULL ORDER BY t.date')) {
      final impId = t['id']! as String;
      final name = t['name']! as String;
      final date = _date(t['date']);

      // ¿La temporada de destino está cerrada en este teléfono?
      final target = await _rows(
          'SELECT status FROM main.seasons WHERE game = ? AND year = ? AND quarter = ?',
          [t['s_game'], t['s_year'], t['s_quarter']]);
      final targetClosed =
          target.isNotEmpty && target.first['status'] == SeasonStatus.closed.name;

      Map<String, Object?>? local;
      MergeKind kind;
      final byId = locals.where((l) => l['id'] == impId).firstOrNull;
      if (byId != null) {
        local = byId;
        kind = byId['deleted_at'] != null ? MergeKind.deletedHere : MergeKind.sameTournament;
      } else {
        final key = _key(name);
        final sameName = locals
            .where((l) => l['deleted_at'] == null && _key(l['name']! as String) == key)
            .toList();
        final sameDay = sameName.where((l) => _sameDay(_date(l['date']), date)).firstOrNull;
        if (sameDay != null) {
          local = sameDay;
          kind = MergeKind.sameNameSameDate;
        } else if (sameName.isNotEmpty) {
          local = sameName.first;
          kind = MergeKind.sameNameOtherDate;
        } else {
          kind = MergeKind.newTournament;
        }
      }
      final localClosed = local != null && local['season_status'] == SeasonStatus.closed.name;
      if (targetClosed || localClosed) kind = MergeKind.lockedSeason;

      var localNewer = false;
      if (local != null &&
          (kind == MergeKind.sameTournament || kind == MergeKind.sameNameSameDate)) {
        final mine = await _lastChange('main', local['id']! as String);
        final theirs = await _lastChange('imp', impId);
        localNewer = mine != null && theirs != null && mine.isAfter(theirs);
      }

      final (allowed, action) = switch (kind) {
        MergeKind.newTournament => (const [MergeAction.add, MergeAction.skip], MergeAction.add),
        MergeKind.sameTournament => (
            const [MergeAction.replace, MergeAction.skip],
            localNewer ? MergeAction.skip : MergeAction.replace,
          ),
        MergeKind.sameNameSameDate => (
            const [MergeAction.replace, MergeAction.add, MergeAction.skip],
            localNewer ? MergeAction.skip : MergeAction.replace,
          ),
        MergeKind.sameNameOtherDate => (
            const [MergeAction.add, MergeAction.replace, MergeAction.skip],
            MergeAction.add,
          ),
        MergeKind.deletedHere => (const [MergeAction.replace, MergeAction.skip], MergeAction.skip),
        MergeKind.lockedSeason => (const [MergeAction.skip], MergeAction.skip),
      };

      items.add(MergeItem(
        importId: impId,
        name: name,
        date: date,
        kind: kind,
        localId: local?['id'] as String?,
        localName: local?['name'] as String?,
        localDate: local == null ? null : _date(local['date']),
        localNewer: localNewer,
        allowed: allowed,
        action: action,
      ));
    }
    return MergePlan(items);
  }

  /// Último cambio de un torneo: el más reciente de él, sus rondas, partidas
  /// e inscripciones (los resultados no tocan la fila del torneo).
  Future<DateTime?> _lastChange(String schema, String id) async {
    final rows = await _rows(
      'SELECT updated_at AS u FROM $schema.tournaments WHERE id = ? '
      'UNION ALL SELECT updated_at FROM $schema.rounds WHERE tournament_id = ? '
      'UNION ALL SELECT updated_at FROM $schema.matches WHERE tournament_id = ? '
      'UNION ALL SELECT updated_at FROM $schema.tournament_players WHERE tournament_id = ?',
      [id, id, id, id],
    );
    DateTime? last;
    for (final r in rows) {
      final d = _date(r['u']);
      if (d != null && (last == null || d.isAfter(last))) last = d;
    }
    return last;
  }

  // ───────────────────────── Integración ─────────────────────────

  Future<MergeReport> _merge(Map<String, MergeAction> decisions) async {
    final plan = await _plan();
    for (final item in plan.items) {
      final chosen = decisions[item.importId];
      if (chosen != null && item.allowed.contains(chosen)) item.action = chosen;
    }
    final report = MergeReport();
    final seasons = await _mergeSeasons();
    final decks = await _mergeDecks(report);
    final players = await _mergePlayers(report);
    await _mergeTournaments(report, plan,
        seasons: seasons, decks: decks, players: players);
    await _mergeSnapshots(seasons: seasons, decks: decks, players: players);
    return report;
  }

  /// Temporadas: se reconocen por juego + año + trimestre.
  Future<Map<String, String>> _mergeSeasons() async {
    final map = <String, String>{};
    for (final s in await _rows('SELECT * FROM imp.seasons')) {
      final local = await _rows(
          'SELECT id FROM main.seasons WHERE game = ? AND year = ? AND quarter = ?',
          [s['game'], s['year'], s['quarter']]);
      if (local.isNotEmpty) {
        map[s['id']! as String] = local.first['id']! as String;
      } else {
        // Una temporada nueva entra activa: cerrarla es decisión de cada teléfono.
        await _insert('seasons', {
          ...s,
          'status': SeasonStatus.active.name,
          'closed_at': null,
        });
        map[s['id']! as String] = s['id']! as String;
      }
    }
    return map;
  }

  /// Mazos: por id y, si no, por nombre normalizado. Se incluyen también los
  /// borrados en la copia (pueden tener partidas). Nunca se reactivan mazos
  /// borrados o fusionados en este teléfono. Las fotos propias de otro
  /// teléfono no viajan en la copia: solo se conservan las del catálogo.
  Future<Map<String, String>> _mergeDecks(MergeReport report) async {
    final map = <String, String>{};
    for (final d in await _rows('SELECT * FROM imp.decks')) {
      final impId = d['id']! as String;
      final image = d['image_path'] as String?;
      final assetImage = image != null && image.startsWith('assets/') ? image : null;

      final byId = await _rows('SELECT id, deleted_at, image_path FROM main.decks WHERE id = ?', [impId]);
      // Preferir un mazo ACTIVO con ese nombre (p. ej. el destino de una fusión).
      final byName = await _rows(
          'SELECT id, deleted_at, image_path FROM main.decks '
          'WHERE game = ? AND normalized_name = ? AND deleted_at IS NULL',
          [d['game'], d['normalized_name']]);
      final local = byId.isNotEmpty && byId.first['deleted_at'] == null
          ? byId.first
          : byName.firstOrNull ?? byId.firstOrNull;

      if (local != null) {
        final id = local['id']! as String;
        if (local['deleted_at'] == null && local['image_path'] == null && assetImage != null) {
          await _exec('UPDATE main.decks SET image_path = ? WHERE id = ?', [assetImage, id]);
        }
        map[impId] = id;
      } else {
        // Puede chocar el nombre con un mazo BORRADO del teléfono (índice único):
        // en ese caso se reutiliza ese mazo borrado.
        final deletedSameName = await _rows(
            'SELECT id FROM main.decks WHERE game = ? AND normalized_name = ?',
            [d['game'], d['normalized_name']]);
        if (deletedSameName.isNotEmpty) {
          map[impId] = deletedSameName.first['id']! as String;
          continue;
        }
        await _insert('decks', {...d, 'image_path': assetImage});
        map[impId] = impId;
        if (d['deleted_at'] == null) report.decksAdded++;
      }
    }
    return map;
  }

  /// Jugadores: por id y, si no, por apodo (sin mayúsculas ni espacios extra).
  /// Se incluyen los borrados en la copia (pueden tener partidas: si faltaran,
  /// la importación fallaría). Nunca se reactivan jugadores borrados aquí.
  Future<Map<String, String>> _mergePlayers(MergeReport report) async {
    final map = <String, String>{};
    final localByNick = <String, String>{
      for (final p in await _rows('SELECT id, nickname FROM main.players WHERE deleted_at IS NULL'))
        _key(p['nickname']! as String): p['id']! as String,
    };
    for (final p in await _rows('SELECT * FROM imp.players')) {
      final impId = p['id']! as String;
      final deletedThere = p['deleted_at'] != null;
      final byId = await _rows('SELECT id, deleted_at FROM main.players WHERE id = ?', [impId]);
      String? id;
      if (byId.isNotEmpty && byId.first['deleted_at'] == null) {
        id = impId;
      } else if (!deletedThere && localByNick.containsKey(_key(p['nickname']! as String))) {
        id = localByNick[_key(p['nickname']! as String)];
      } else if (byId.isNotEmpty) {
        id = impId; // borrado aquí: se usa tal cual, sin reactivarlo
      }
      if (id != null) {
        if (!deletedThere) {
          // Solo se completan los datos que faltan en el teléfono.
          await _exec(
              'UPDATE main.players SET full_name = COALESCE(full_name, ?), '
              'konami_id = COALESCE(konami_id, ?), phone = COALESCE(phone, ?), '
              'notes = COALESCE(notes, ?) WHERE id = ?',
              [p['full_name'], p['konami_id'], p['phone'], p['notes'], id]);
        }
        map[impId] = id;
      } else {
        final photo = p['photo_path'] as String?;
        final keepPhoto = photo != null && File(photo).existsSync();
        await _insert('players', {...p, 'photo_path': keepPhoto ? photo : null});
        map[impId] = impId;
        if (!deletedThere) {
          localByNick[_key(p['nickname']! as String)] = impId;
          report.playersAdded++;
        }
      }
    }
    return map;
  }

  Future<void> _mergeTournaments(
    MergeReport report,
    MergePlan plan, {
    required Map<String, String> seasons,
    required Map<String, String> decks,
    required Map<String, String> players,
  }) async {
    String? deck(Object? id) => id == null ? null : decks[id as String] ?? id as String;
    String player(Object? id) => players[id as String] ?? id;

    for (final item in plan.items) {
      if (item.action == MergeAction.skip) {
        report.tournamentsSkipped++;
        continue;
      }
      final t = (await _rows('SELECT * FROM imp.tournaments WHERE id = ?', [item.importId])).first;
      if (item.action == MergeAction.replace && item.localId != null) {
        await _deleteTournament(item.localId!);
        // Mismo id ya borrado de antes (p. ej. "borrado aquí").
        if (item.localId != item.importId) await _deleteTournament(item.importId);
        report.tournamentsReplaced++;
      } else {
        report.tournamentsAdded++;
      }
      final impId = item.importId;
      await _insert('tournaments', {...t, 'season_id': seasons[t['season_id']] ?? t['season_id']});
      for (final r in await _rows(
          'SELECT * FROM imp.rounds WHERE tournament_id = ? AND deleted_at IS NULL', [impId])) {
        await _insert('rounds', r);
      }
      for (final m in await _rows(
          'SELECT * FROM imp.matches WHERE tournament_id = ? AND deleted_at IS NULL', [impId])) {
        await _insert('matches', {
          ...m,
          'player1_id': player(m['player1_id']),
          'player2_id': m['player2_id'] == null ? null : player(m['player2_id']),
          'deck1_id': deck(m['deck1_id']),
          'deck2_id': deck(m['deck2_id']),
        });
      }
      for (final tp in await _rows(
          'SELECT * FROM imp.tournament_players WHERE tournament_id = ? AND deleted_at IS NULL',
          [impId])) {
        await _insert('tournament_players', {
          ...tp,
          'player_id': player(tp['player_id']),
          'deck_id': deck(tp['deck_id']),
        });
      }
      for (final sr in await _rows(
          'SELECT * FROM imp.season_results WHERE tournament_id = ? AND deleted_at IS NULL',
          [impId])) {
        await _insert('season_results', {
          ...sr,
          'season_id': seasons[sr['season_id']] ?? sr['season_id'],
          'player_id': player(sr['player_id']),
        });
      }
      for (final pe in await _rows(
          'SELECT * FROM imp.penalties WHERE tournament_id = ? AND deleted_at IS NULL', [impId])) {
        await _insert('penalties', {...pe, 'player_id': player(pe['player_id'])});
      }
    }
  }

  /// Fotos de temporadas cerradas: solo si el teléfono no tiene las suyas.
  Future<void> _mergeSnapshots({
    required Map<String, String> seasons,
    required Map<String, String> decks,
    required Map<String, String> players,
  }) async {
    for (final MapEntry(key: impSeason, value: season) in seasons.entries) {
      final hasRanking = await _rows(
          'SELECT 1 FROM main.ranking_snapshots WHERE season_id = ? AND deleted_at IS NULL LIMIT 1', [season]);
      if (hasRanking.isEmpty) {
        for (final s in await _rows(
            'SELECT * FROM imp.ranking_snapshots WHERE season_id = ? AND deleted_at IS NULL',
            [impSeason])) {
          final player = players[s['player_id']];
          if (player == null) continue;
          await _insert('ranking_snapshots', {...s, 'season_id': season, 'player_id': player});
        }
      }
      final hasDecks = await _rows(
          'SELECT 1 FROM main.deck_snapshots WHERE season_id = ? AND deleted_at IS NULL LIMIT 1', [season]);
      if (hasDecks.isEmpty) {
        for (final s in await _rows(
            'SELECT * FROM imp.deck_snapshots WHERE season_id = ? AND deleted_at IS NULL',
            [impSeason])) {
          final d = decks[s['deck_id']];
          if (d == null) continue;
          await _insert('deck_snapshots', {...s, 'season_id': season, 'deck_id': d});
        }
      }
    }
  }

  /// Borra del teléfono un torneo con todo lo que cuelga de él.
  Future<void> _deleteTournament(String id) async {
    for (final table in ['penalties', 'matches', 'rounds', 'tournament_players', 'season_results']) {
      await _exec('DELETE FROM main.$table WHERE tournament_id = ?', [id]);
    }
    await _exec('DELETE FROM main.tournaments WHERE id = ?', [id]);
  }

  // ───────────────────────── Utilidades ─────────────────────────

  static String _key(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// Fecha guardada por Drift como texto ("2026-10-04T15:30:00.000 -04:00")
  /// o como segundos (BD antiguas).
  static DateTime? _date(Object? v) {
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v * 1000);
    if (v is String) {
      return DateTime.tryParse(v.replaceFirst(RegExp(r' (?=[+-]\d\d:?\d\d$)'), ''));
    }
    return null;
  }

  static bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    final x = a.toLocal(), y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  Future<List<Map<String, Object?>>> _rows(String sql, [List<Object?> args = const []]) async {
    final rows = await _db
        .customSelect(sql, variables: [for (final a in args) Variable<Object>(a)])
        .get();
    return [for (final r in rows) Map<String, Object?>.of(r.data)];
  }

  Future<void> _exec(String sql, List<Object?> args) => _db.customStatement(sql, args);

  /// Inserta una fila con las mismas columnas que trae la copia (mismo esquema).
  /// Si ya existe una fila con ese id (datos de una importación anterior), se
  /// sustituye.
  Future<void> _insert(String table, Map<String, Object?> row) {
    final cols = row.keys.toList();
    return _exec(
      'INSERT OR REPLACE INTO main."$table" (${cols.map((c) => '"$c"').join(', ')}) '
      'VALUES (${List.filled(cols.length, '?').join(', ')})',
      [for (final c in cols) row[c]],
    );
  }
}

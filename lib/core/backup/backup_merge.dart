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
  int playersAdded = 0;
  int decksAdded = 0;

  @override
  String toString() {
    final parts = <String>[
      if (tournamentsAdded > 0) '$tournamentsAdded torneo(s) nuevo(s)',
      if (tournamentsReplaced > 0) '$tournamentsReplaced torneo(s) actualizado(s)',
      if (playersAdded > 0) '$playersAdded jugador(es) nuevo(s)',
      if (decksAdded > 0) '$decksAdded mazo(s) nuevo(s)',
    ];
    return parts.isEmpty ? 'No había nada nuevo que integrar' : parts.join(' · ');
  }
}

/// Integra una copia (.gtcg ya validada) en la BD actual SIN borrar lo que hay:
///
/// - **Torneos**: si en el teléfono hay uno con el mismo nombre (sin importar
///   mayúsculas ni espacios) o el mismo id, se reemplaza por el de la copia
///   (con sus rondas, partidas, inscripciones y puntos). Los demás se añaden.
///   Los torneos que solo están en el teléfono se quedan como están.
/// - **Jugadores**: se reconocen por id y, si no, por apodo. Los nuevos se
///   añaden; a los existentes solo se les completan datos vacíos.
/// - **Mazos**: por id o por nombre. **Temporadas**: por año y trimestre.
/// - La escala de puntos y los ajustes del teléfono no se tocan.
class BackupMerger {
  BackupMerger(this._db);

  final AppDatabase _db;

  Future<MergeReport> merge(Uint8List sqlite) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/integrar_${DateTime.now().millisecondsSinceEpoch}.sqlite');
    await file.writeAsBytes(sqlite, flush: true);
    try {
      // 1) La copia se abre aparte para llevarla al esquema actual (si viene
      //    de una versión anterior, Drift la migra igual que al abrir la app).
      final incoming = AppDatabase(NativeDatabase(file));
      await incoming.customSelect('SELECT 1').get();
      await incoming.close();

      // 2) Se adjunta como "imp" y se integra en una sola transacción.
      await _db.customStatement('ATTACH DATABASE ? AS imp', [file.path]);
      final MergeReport report;
      try {
        report = await _db.transaction(_merge);
      } finally {
        await _db.customStatement('DETACH DATABASE imp');
      }
      // Las pantallas abiertas se refrescan con los datos nuevos.
      _db.markTablesUpdated(_db.allTables);
      return report;
    } finally {
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final f = File('${file.path}$suffix');
        if (await f.exists()) await f.delete();
      }
    }
  }

  // ───────────────────────── Integración ─────────────────────────

  Future<MergeReport> _merge() async {
    final report = MergeReport();
    final seasons = await _mergeSeasons();
    final decks = await _mergeDecks(report);
    final players = await _mergePlayers(report);
    await _mergeTournaments(report, seasons: seasons, decks: decks, players: players);
    await _mergeSnapshots(seasons: seasons, decks: decks, players: players);
    return report;
  }

  /// Temporadas: se reconocen por juego + año + trimestre.
  Future<Map<String, String>> _mergeSeasons() async {
    final map = <String, String>{};
    for (final s in await _rows('SELECT * FROM imp.seasons WHERE deleted_at IS NULL')) {
      final local = await _rows(
          'SELECT id, deleted_at FROM main.seasons WHERE game = ? AND year = ? AND quarter = ?',
          [s['game'], s['year'], s['quarter']]);
      if (local.isNotEmpty) {
        final id = local.first['id']! as String;
        if (local.first['deleted_at'] != null) {
          await _exec('UPDATE main.seasons SET deleted_at = NULL WHERE id = ?', [id]);
        }
        map[s['id']! as String] = id;
      } else {
        await _insert('seasons', s);
        map[s['id']! as String] = s['id']! as String;
      }
    }
    return map;
  }

  /// Mazos: por id y, si no, por nombre normalizado. Las fotos propias de otro
  /// teléfono no viajan en la copia: solo se conservan las imágenes del catálogo.
  Future<Map<String, String>> _mergeDecks(MergeReport report) async {
    final map = <String, String>{};
    for (final d in await _rows('SELECT * FROM imp.decks WHERE deleted_at IS NULL')) {
      final impId = d['id']! as String;
      final image = d['image_path'] as String?;
      final assetImage = image != null && image.startsWith('assets/') ? image : null;

      var local = await _rows('SELECT id, deleted_at, image_path FROM main.decks WHERE id = ?', [impId]);
      if (local.isEmpty) {
        local = await _rows(
            'SELECT id, deleted_at, image_path FROM main.decks WHERE game = ? AND normalized_name = ?',
            [d['game'], d['normalized_name']]);
      }
      if (local.isNotEmpty) {
        final id = local.first['id']! as String;
        if (local.first['deleted_at'] != null) {
          await _exec('UPDATE main.decks SET deleted_at = NULL WHERE id = ?', [id]);
        }
        if (local.first['image_path'] == null && assetImage != null) {
          await _exec('UPDATE main.decks SET image_path = ? WHERE id = ?', [assetImage, id]);
        }
        map[impId] = id;
      } else {
        await _insert('decks', {...d, 'image_path': assetImage});
        map[impId] = impId;
        report.decksAdded++;
      }
    }
    return map;
  }

  /// Jugadores: por id y, si no, por apodo (sin mayúsculas ni espacios extra).
  Future<Map<String, String>> _mergePlayers(MergeReport report) async {
    final map = <String, String>{};
    final localByNick = <String, String>{
      for (final p in await _rows('SELECT id, nickname FROM main.players WHERE deleted_at IS NULL'))
        _key(p['nickname']! as String): p['id']! as String,
    };
    for (final p in await _rows('SELECT * FROM imp.players WHERE deleted_at IS NULL')) {
      final impId = p['id']! as String;
      final byId = await _rows('SELECT id, deleted_at FROM main.players WHERE id = ?', [impId]);
      String? id;
      if (byId.isNotEmpty) {
        id = impId;
        if (byId.first['deleted_at'] != null) {
          await _exec('UPDATE main.players SET deleted_at = NULL WHERE id = ?', [id]);
        }
      } else {
        id = localByNick[_key(p['nickname']! as String)];
      }
      if (id != null) {
        // Solo se completan los datos que faltan en el teléfono.
        await _exec(
            'UPDATE main.players SET full_name = COALESCE(full_name, ?), '
            'konami_id = COALESCE(konami_id, ?), phone = COALESCE(phone, ?), '
            'notes = COALESCE(notes, ?) WHERE id = ?',
            [p['full_name'], p['konami_id'], p['phone'], p['notes'], id]);
        map[impId] = id;
      } else {
        final photo = p['photo_path'] as String?;
        final keepPhoto = photo != null && File(photo).existsSync();
        await _insert('players', {...p, 'photo_path': keepPhoto ? photo : null});
        map[impId] = impId;
        localByNick[_key(p['nickname']! as String)] = impId;
        report.playersAdded++;
      }
    }
    return map;
  }

  /// Torneos: el de la copia reemplaza al del teléfono con el mismo nombre (o
  /// el mismo id); si no hay ninguno, se añade.
  Future<void> _mergeTournaments(
    MergeReport report, {
    required Map<String, String> seasons,
    required Map<String, String> decks,
    required Map<String, String> players,
  }) async {
    final locals = await _rows('SELECT id, name, deleted_at FROM main.tournaments');
    String? deck(Object? id) => id == null ? null : decks[id as String];

    for (final t in await _rows('SELECT * FROM imp.tournaments WHERE deleted_at IS NULL')) {
      final impId = t['id']! as String;
      final key = _key(t['name']! as String);
      final matching = locals.where((l) =>
          l['id'] == impId || (l['deleted_at'] == null && _key(l['name']! as String) == key));
      var replaced = false;
      for (final l in matching.toList()) {
        await _deleteTournament(l['id']! as String);
        locals.remove(l);
        if (l['deleted_at'] == null) replaced = true;
      }
      replaced ? report.tournamentsReplaced++ : report.tournamentsAdded++;

      await _insert('tournaments', {...t, 'season_id': seasons[t['season_id']] ?? t['season_id']});
      for (final r in await _rows(
          'SELECT * FROM imp.rounds WHERE tournament_id = ? AND deleted_at IS NULL', [impId])) {
        await _insert('rounds', r);
      }
      for (final m in await _rows(
          'SELECT * FROM imp.matches WHERE tournament_id = ? AND deleted_at IS NULL', [impId])) {
        await _insert('matches', {
          ...m,
          'player1_id': players[m['player1_id']] ?? m['player1_id'],
          'player2_id': m['player2_id'] == null ? null : players[m['player2_id']] ?? m['player2_id'],
          'deck1_id': deck(m['deck1_id']),
          'deck2_id': deck(m['deck2_id']),
        });
      }
      for (final tp in await _rows(
          'SELECT * FROM imp.tournament_players WHERE tournament_id = ? AND deleted_at IS NULL',
          [impId])) {
        await _insert('tournament_players', {
          ...tp,
          'player_id': players[tp['player_id']] ?? tp['player_id'],
          'deck_id': deck(tp['deck_id']),
        });
      }
      for (final sr in await _rows(
          'SELECT * FROM imp.season_results WHERE tournament_id = ? AND deleted_at IS NULL',
          [impId])) {
        await _insert('season_results', {
          ...sr,
          'season_id': seasons[sr['season_id']] ?? sr['season_id'],
          'player_id': players[sr['player_id']] ?? sr['player_id'],
        });
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
          'SELECT 1 FROM main.ranking_snapshots WHERE season_id = ? LIMIT 1', [season]);
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
          'SELECT 1 FROM main.deck_snapshots WHERE season_id = ? LIMIT 1', [season]);
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
    for (final table in ['matches', 'rounds', 'tournament_players', 'season_results']) {
      await _exec('DELETE FROM main.$table WHERE tournament_id = ?', [id]);
    }
    await _exec('DELETE FROM main.tournaments WHERE id = ?', [id]);
  }

  // ───────────────────────── SQL ─────────────────────────

  static String _key(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

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

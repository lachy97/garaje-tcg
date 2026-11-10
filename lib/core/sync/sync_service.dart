import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/account.dart';
import '../auth/auth_api.dart';
import '../auth/auth_providers.dart';
import '../auth/http_auth_api.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';
import 'sync_schema.dart';

/// Estado de la subida de datos al servidor.
class SyncStatus {
  const SyncStatus({
    this.enabled = false,
    this.download = false,
    this.reason,
    this.pending = 0,
    this.running = false,
    this.lastSync,
    this.lastError,
    this.lastSent = 0,
    this.rejected = 0,
  });

  /// Este teléfono sube datos (organizador/administrador con servidor real).
  final bool enabled;

  /// Teléfono de jugador o juez: baja datos del servidor (no sube).
  final bool download;

  /// Por qué no está activa (para mostrarlo en Ajustes).
  final String? reason;

  /// Cambios en cola.
  final int pending;
  final bool running;
  final DateTime? lastSync;
  final String? lastError;

  /// Filas enviadas en la última sincronización.
  final int lastSent;

  /// Filas que el servidor no aceptó (de otro organizador, inválidas…).
  final int rejected;

  SyncStatus copyWith({
    bool? enabled,
    String? reason,
    int? pending,
    bool? running,
    DateTime? lastSync,
    String? lastError,
    bool clearError = false,
    int? lastSent,
    int? rejected,
  }) =>
      SyncStatus(
        enabled: enabled ?? this.enabled,
        download: download,
        reason: reason ?? this.reason,
        pending: pending ?? this.pending,
        running: running ?? this.running,
        lastSync: lastSync ?? this.lastSync,
        lastError: clearError ? null : (lastError ?? this.lastError),
        lastSent: lastSent ?? this.lastSent,
        rejected: rejected ?? this.rejected,
      );
}

/// Sube al servidor, cada [interval] y al volver a la app, los cambios de
/// la base local (jugadores, mazos, temporadas, torneos…). Funciona sin
/// conexión: los cambios esperan en la cola hasta que haya internet.
class SyncController extends Notifier<SyncStatus> with WidgetsBindingObserver {
  static const interval = Duration(seconds: 30);
  static const batchSize = 200;

  Timer? _timer;
  Timer? _first;
  bool _busy = false;

  @override
  SyncStatus build() {
    final session = ref.watch(sessionProvider).value;
    final api = ref.watch(authApiProvider);
    ref.watch(databaseProvider);

    _stop();
    ref.onDispose(_stop);

    final String? reason;
    if (api is! HttpAuthApi) {
      reason = 'La app aún no está conectada al servidor.';
    } else if (session == null) {
      reason = 'Inicia sesión con una cuenta de organizador.';
    } else {
      reason = null;
    }
    if (reason != null) return SyncStatus(reason: reason);
    final role = session!.account.role;
    final download = role != AppRole.admin && role != AppRole.organizer;

    _timer = Timer.periodic(interval, (_) => sync());
    WidgetsBinding.instance.addObserver(this);
    // Primera subida al poco de abrir (Timer cancelable: si el proveedor se
    // reconstruye o se descarta antes, no queda una llamada suelta).
    _first = Timer(const Duration(seconds: 3), sync);
    return SyncStatus(enabled: true, download: download);
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _first?.cancel();
    _first = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) sync();
    if (s == AppLifecycleState.paused) sync(); // lo último antes de salir
  }

  AppDatabase get _db => ref.read(databaseProvider);

  /// Pendientes sin lanzar (para los caminos de error).
  Future<int?> _pendingOrNull() async {
    try {
      return await _pendingCount();
    } catch (_) {
      return null;
    }
  }

  Future<int> _pendingCount() async {
    final r = await _db.customSelect('SELECT COUNT(*) AS n FROM sync_outbox').getSingle();
    return r.read<int>('n');
  }

  Future<String?> _state(String k) async {
    final r = await _db
        .customSelect('SELECT v FROM sync_state WHERE k = ?', variables: [Variable.withString(k)])
        .getSingleOrNull();
    return r?.read<String?>('v');
  }

  Future<void> _setState(String k, String v) => _db.customStatement(
      'INSERT OR REPLACE INTO sync_state (k, v) VALUES (?, ?)', [k, v]);

  /// Teléfono de jugador: vuelve a bajar todo desde el principio.
  Future<void> redownloadAll() async {
    if (!ref.mounted) return;
    final id = ref.read(sessionProvider).value?.account.id;
    if (id == null) return;
    await _db.customStatement('DELETE FROM sync_state WHERE k = ?', ['pull_seq:$id']);
    if (!ref.mounted) return;
    await sync();
  }

  /// Vuelve a poner en cola todas las filas (por si el servidor perdió algo).
  Future<void> resendAll() async {
    if (!ref.mounted) return;
    await enqueueAllRows(_db);
    if (!ref.mounted) return;
    await sync();
  }

  /// Sube lo que haya en la cola. No lanza: deja el error en el estado.
  Future<void> sync() async {
    // El temporizador o el ciclo de vida pueden llamar con el proveedor ya
    // descartado: entonces no se puede usar ref ni state.
    if (!ref.mounted || !state.enabled || _busy) return;
    final session = ref.read(sessionProvider).value;
    final api = ref.read(authApiProvider);
    if (session == null || api is! HttpAuthApi) return;
    _busy = true;
    state = state.copyWith(running: true);
    var sent = 0;
    var rejected = 0;
    try {
      if (state.download) {
        final got = await _pull(session, api);
        if (!ref.mounted) return;
        state = state.copyWith(
          running: false,
          pending: 0,
          lastSync: DateTime.now(),
          lastSent: got,
          clearError: true,
        );
        return;
      }
      // Primera vez que esta cuenta sube desde este teléfono: todo.
      const key = 'all_enqueued_for';
      if (await _state(key) != session.account.id) {
        await enqueueAllRows(_db);
        await _setState(key, session.account.id);
      }
      while (true) {
        final batch = await _db
            .customSelect('SELECT tbl, row_id, changed_at FROM sync_outbox '
                'ORDER BY changed_at LIMIT $batchSize')
            .get();
        if (batch.isEmpty) break;
        final rows = await _payload(batch);
        final res = await api.request('POST', 'v1/sync/push',
            body: {'rows': rows}, token: session.token);
        final bad = (res['rejected'] as List?) ?? const [];
        rejected += bad.length;
        sent += rows.length - bad.length;
        // Se quitan de la cola solo si no cambiaron mientras se enviaban.
        await _db.transaction(() async {
          for (final e in batch) {
            await _db.customStatement(
              'DELETE FROM sync_outbox WHERE tbl = ? AND row_id = ? AND changed_at = ?',
              [e.read<String>('tbl'), e.read<String>('row_id'), e.read<int>('changed_at')],
            );
          }
        });
        if (batch.length < batchSize || !ref.mounted) break;
      }
      if (!ref.mounted) return;
      final pending = await _pendingCount();
      if (!ref.mounted) return;
      state = state.copyWith(
        running: false,
        pending: pending,
        lastSync: DateTime.now(),
        lastSent: sent,
        rejected: rejected,
        clearError: true,
      );
    } on AuthNetworkException catch (e) {
      final pending = await _pendingOrNull();
      if (ref.mounted) state = state.copyWith(running: false, pending: pending, lastError: e.message);
    } on AuthException catch (e) {
      final pending = await _pendingOrNull();
      if (ref.mounted) {
        state = state.copyWith(running: false, pending: pending, lastError: e.message);
        // Sesión vencida o rol cambiado: se actualiza la cuenta.
        unawaited(ref.read(sessionProvider.notifier).refreshAccount());
      }
    } catch (e) {
      if (ref.mounted) state = state.copyWith(running: false, lastError: 'Error al sincronizar: $e');
    } finally {
      _busy = false;
    }
  }

  // ───────────────────── Bajar (jugadores y jueces) ─────────────────────

  final Map<String, Set<String>> _columns = {};

  /// Columnas de una tabla local (para ignorar las que no existan aquí).
  Future<Set<String>> _cols(String t) async => _columns[t] ??= {
        for (final r in await _db.customSelect('PRAGMA table_info($t)').get())
          r.read<String>('name'),
      };

  /// Baja los cambios que esta cuenta puede ver y los guarda en la base
  /// local (sin volver a ponerlos en la cola de subida). Devuelve cuántas
  /// filas llegaron.
  Future<int> _pull(Session session, HttpAuthApi api) async {
    final account = session.account;
    // Si cambia la ficha vinculada, se baja todo de nuevo.
    final seqKey = 'pull_seq:${account.id}';
    final playerKey = 'pull_player:${account.id}';
    final player = account.playerId ?? '';
    var since = int.tryParse(await _state(seqKey) ?? '') ?? 0;
    if ((await _state(playerKey) ?? '') != player) since = 0;
    var total = 0;
    while (ref.mounted) {
      final res = await api.request('GET', 'v1/sync/pull?since=$since', token: session.token);
      final rows = [
        for (final r in (res['rows'] as List?) ?? const []) (r as Map).cast<String, Object?>(),
      ];
      if (rows.isNotEmpty) await _apply(rows);
      total += rows.length;
      since = (res['seq'] as num?)?.toInt() ?? since;
      await _setState(seqKey, '$since');
      await _setState(playerKey, player);
      if (res['more'] != true) break;
    }
    return total;
  }

  Future<void> _apply(List<Map<String, Object?>> rows) async {
    // Con las claves foráneas desactivadas: las filas pueden llegar en
    // cualquier orden (p. ej. una partida antes que su ronda).
    await _db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await _db.transaction(() async {
        await _db.customStatement("INSERT OR REPLACE INTO sync_state (k, v) VALUES ('applying', '1')");
        for (final r in rows) {
          final t = r['t'];
          final id = r['id'];
          if (t is! String || id is! String || !kSyncTables.contains(t)) continue;
          final data = r['data'];
          if (r['deleted'] == true || data is! Map) {
            await _db.customStatement('DELETE FROM $t WHERE id = ?', [id]);
            continue;
          }
          final cols = await _cols(t);
          final entries = [
            for (final e in data.entries)
              if (e.key is String && cols.contains(e.key)) MapEntry(e.key as String, e.value),
          ];
          if (entries.isEmpty) continue;
          await _db.customStatement(
            'INSERT OR REPLACE INTO $t (${entries.map((e) => e.key).join(', ')}) '
            'VALUES (${List.filled(entries.length, '?').join(', ')})',
            [for (final e in entries) e.value],
          );
        }
        await _db.customStatement("DELETE FROM sync_state WHERE k = 'applying'");
      });
    } finally {
      await _db.customStatement('PRAGMA foreign_keys = ON');
    }
    // Avisar a las pantallas de que cambiaron los datos.
    _db.markTablesUpdated(_db.allTables);
  }

  /// Filas actuales de la cola (o "borrada" si ya no existe).
  Future<List<Map<String, Object?>>> _payload(List<QueryRow> batch) async {
    final byTable = <String, List<QueryRow>>{};
    for (final e in batch) {
      byTable.putIfAbsent(e.read<String>('tbl'), () => []).add(e);
    }
    final out = <Map<String, Object?>>[];
    for (final MapEntry(key: t, value: entries) in byTable.entries) {
      if (!kSyncTables.contains(t)) continue;
      final ids = [for (final e in entries) e.read<String>('row_id')];
      final found = <String, Map<String, Object?>>{};
      for (var i = 0; i < ids.length; i += 90) {
        final chunk = ids.sublist(i, i + 90 > ids.length ? ids.length : i + 90);
        final rows = await _db
            .customSelect(
              'SELECT * FROM $t WHERE id IN (${List.filled(chunk.length, '?').join(',')})',
              variables: [for (final id in chunk) Variable.withString(id)],
            )
            .get();
        for (final r in rows) {
          found[r.data['id']! as String] = Map<String, Object?>.from(r.data);
        }
      }
      for (final e in entries) {
        final id = e.read<String>('row_id');
        final data = found[id];
        out.add({
          't': t,
          'id': id,
          'changedAt': e.read<int>('changed_at'),
          if (data == null) 'deleted': true else 'data': data,
        });
      }
    }
    return out;
  }

  /// Cuenta los pendientes (para Ajustes).
  Future<void> refreshPending() async {
    if (!ref.mounted) return;
    final pending = await _pendingCount();
    if (ref.mounted) state = state.copyWith(pending: pending);
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);

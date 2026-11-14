import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/tournaments/presentation/my_table.dart';
import '../auth/account.dart';
import '../auth/auth_providers.dart';
import '../auth/http_auth_api.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';
import '../play/play.dart';
import '../registrations/registrations.dart';
import 'tournament_keeper.dart';

/// Avisos en el teléfono sin servicios de Google: los genera la propia app
/// cuando sincroniza (cada 30 s con la app abierta o recién cerrada). Si el
/// sistema cierra la app, los avisos llegan al volver a abrirla.
class AppNotifier {
  AppNotifier._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('ic_notification')),
      );
      _ready = true;
    } catch (_) {
      // Sin avisos en este teléfono: la app sigue igual.
    }
  }

  /// Android 13+: pide permiso para mostrar avisos (una vez).
  static Future<void> requestPermission() async {
    await init();
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  static bool _asked = false;

  /// La primera vez que se entra a la app: pedir permiso para los avisos.
  static Future<void> askOnce() async {
    if (_asked) return;
    _asked = true;
    final p = await SharedPreferences.getInstance();
    if (p.getBool('notify.asked') ?? false) return;
    await p.setBool('notify.asked', true);
    await requestPermission();
  }

  static Future<void> show(String key, String title, String body) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        key.hashCode & 0x7fffffff,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'garage_avisos',
            'Avisos del torneo',
            channelDescription: 'Ronda nueva, tu mesa, el tiempo, resultados y avisos del juez',
            importance: Importance.high,
            priority: Priority.high,
            // Icono pequeño: la casa del logo en blanco (Android lo tiñe).
            icon: 'ic_notification',
            color: Color(0xFF8CF04C),
          ),
        ),
      );
    } catch (_) {}
  }
}

/// Avisos activados en Ajustes (por defecto, sí).
class NotifyEnabledController extends Notifier<bool> {
  static const key = 'notify.enabled';

  @override
  bool build() {
    SharedPreferences.getInstance().then((p) {
      final v = p.getBool(key);
      if (v != null && ref.mounted && v != state) state = v;
    });
    return true;
  }

  Future<void> set(bool on) async {
    state = on;
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, on);
    if (on) await AppNotifier.requestPermission();
  }
}

final notifyEnabledProvider = NotifierProvider<NotifyEnabledController, bool>(NotifyEnabledController.new);

const _seenKey = 'notify.seen';

/// Mantener la app activa (aviso fijo) durante los torneos en juego.
const _backgroundKey = 'notify.background';

class KeepAliveController extends Notifier<bool> {
  @override
  bool build() {
    SharedPreferences.getInstance().then((p) {
      final v = p.getBool(_backgroundKey);
      if (v != null && ref.mounted && v != state) state = v;
    });
    return true;
  }

  Future<void> set(bool on) async {
    state = on;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_backgroundKey, on);
    if (!on) await TournamentKeeper.set(false);
  }
}

final keepAliveProvider = NotifierProvider<KeepAliveController, bool>(KeepAliveController.new);

/// Revisa si hay algo nuevo que avisar. No lanza nunca.
bool _checking = false;

Future<void> checkNotifications(Ref ref) async {
  if (_checking) return;
  _checking = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(NotifyEnabledController.key) ?? true)) {
      await TournamentKeeper.set(false);
      return;
    }
    var playing = 0; // mesas mías en torneos en juego
    final session = ref.read(sessionProvider).value;
    final http = ref.read(authApiProvider);
    if (session == null || http is! HttpAuthApi) {
      await TournamentKeeper.set(false);
      return;
    }
    final seen = (prefs.getStringList(_seenKey) ?? const <String>[]).toSet();
    final fresh = <String>[];

    Future<void> notify(String key, String title, String body) async {
      if (seen.contains(key) || fresh.contains(key)) return;
      fresh.add(key);
      await AppNotifier.show(key, title, body);
    }

    final account = session.account;
    final play = PlayApi(http, session);
    final pid = account.playerId;

    // ── Jugador: mi mesa, el tiempo y el resultado del rival ──
    if (pid != null) {
      final tables = await ref.read(myTablesProvider(pid).future);
      playing = tables.length;
      for (final t in tables) {
        final base = '${t.tournamentId}:${t.roundLabel}';
        await notify(
          'table:$base',
          '${t.tournamentName} · ${t.roundLabel}',
          t.bye ? 'Tienes BYE (ganas 2-0).' : 'Mesa ${t.table ?? '?'} contra ${t.opponent ?? '?'}'
              '${t.opponentDeck == null ? '' : ' (${t.opponentDeck})'}.',
        );
        if (t.bye || t.score != null) continue;
        final start = t.timerStartedAt;
        if (start != null) {
          final left = Duration(minutes: t.roundMinutes) - DateTime.now().difference(start);
          if (left <= Duration.zero) {
            await notify('time0:$base', 'Se acabó el tiempo', 'Mesa ${t.table ?? '?'}: reporta tu resultado.');
          } else if (left <= const Duration(minutes: 5)) {
            await notify('time5:$base', 'Quedan ${left.inMinutes + 1} minutos', 'Mesa ${t.table ?? '?'} · ${t.tournamentName}');
          }
        }
        for (final a in await play.mine(t.tournamentId)) {
          if (a.kind == PlayKind.report && a.status == PlayStatus.proposed && a.playerId != pid && a.matchId == t.matchId) {
            await notify('confirm:${a.id}', '${a.nickname ?? 'Tu rival'} reportó el resultado',
                '${a.score?.outcome(asP1: t.iAmP1) ?? ''}: confírmalo en Torneos.');
          }
        }
      }
    }

    // ── Inscripción desde la app: cambios en mis solicitudes ──
    try {
      final regs = await RegistrationsApi(http, session).mine();
      final names = {for (final o in regs.open) o.id: o.name};
      for (final r in regs.requests.values) {
        final name = names[r.tournamentId] ?? 'el torneo';
        final msg = switch (r.status) {
          RegistrationStatus.accepted || RegistrationStatus.registered => 'Te aceptaron en $name.',
          RegistrationStatus.rejected => 'No te aceptaron en $name${r.reason == null ? '' : ': ${r.reason}'}.',
          RegistrationStatus.waitlist => 'Estás en la lista de espera de $name (puesto ${r.waitPosition ?? '?'}).',
          _ => null,
        };
        // Aceptada y luego inscrita es el mismo aviso.
        final state = r.status == RegistrationStatus.registered ? RegistrationStatus.accepted : r.status;
        if (msg != null) await notify('reg:${r.id}:${state.name}', 'Inscripción', msg);
      }
    } on AuthException {
      // Servidor sin inscripciones desde la app.
    }

    // ── Organizador y jueces: llamadas al juez, resultados en disputa y
    // solicitudes nuevas ──
    final db = ref.read(databaseProvider);
    final role = account.role;
    final judging = await play.judging().catchError((_) => <String>{});
    final mine = role == AppRole.admin || role == AppRole.organizer;
    final live = <Tournament>[];
    final draft = <Tournament>[];
    for (final t in await db.tournamentsDao.watchAll().first) {
      final relevant = mine || judging.contains(t.id);
      if (!relevant) continue;
      if (t.status == TournamentStatus.swiss || t.status == TournamentStatus.topCut) live.add(t);
      if (mine && t.status == TournamentStatus.draft && t.onlineRegistration) draft.add(t);
    }
    for (final t in live) {
      List<PlayAction> actions;
      try {
        actions = await play.forTournament(t.id);
      } on AuthException {
        continue; // no es suyo (otro organizador)
      }
      for (final a in actions) {
        if (a.kind == PlayKind.judge && a.status == PlayStatus.open) {
          await notify('judge:${a.id}', 'Llaman al juez', '${a.nickname ?? '?'} · ${t.name}${a.note == null ? '' : ': ${a.note}'}');
        } else if (a.kind == PlayKind.report && a.status == PlayStatus.disputed) {
          await notify('disp:${a.id}', 'Resultado en disputa', 'Los jugadores no coinciden · ${t.name}');
        }
      }
    }
    for (final t in draft) {
      try {
        final reqs = await RegistrationsApi(http, session).forTournament(t.id);
        for (final r in reqs) {
          if (r.status == RegistrationStatus.pending) {
            await notify('req:${r.id}', 'Nueva solicitud', '${r.nickname} quiere inscribirse en ${t.name}.');
          }
        }
      } on AuthException {
        continue;
      }
    }

    // Servicio "Torneo en curso": mientras juego, llevo o arbitro un torneo
    // en juego, para que la app siga avisando minimizada.
    final background = prefs.getBool(_backgroundKey) ?? true;
    await TournamentKeeper.set(
      background && (playing > 0 || live.isNotEmpty),
      text: live.isNotEmpty ? live.map((t) => t.name).join(', ') : 'Siguiendo tu mesa y tus avisos',
    );

    if (fresh.isNotEmpty) {
      final all = [...seen, ...fresh];
      await prefs.setStringList(_seenKey, all.length > 400 ? all.sublist(all.length - 400) : all);
    }
  } catch (_) {
    // Sin conexión u otro fallo: se reintenta en la próxima sincronización.
  } finally {
    _checking = false;
  }
}
